import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'clock.dart';
import 'memory_service.dart';
import 'safety_check_service.dart';
import 'tooling_service.dart';
import 'workflow_dispatcher.dart';

typedef EventRunner = Future<String> Function(Event event);
typedef TurnHook = Future<void> Function(Event event, Session session, {bool? success});
typedef HandoffProcessedHook = Future<void> Function(Event event, Session session);

class QueueProcessor {
  QueueProcessor(
    this._db,
    this._clock, {
    EventRunner? runner,
    this.onTurnStart,
    this.onTurnEnd,
    this.onAgentHandoffProcessed,
    this.memoryService,
    this.toolingService,
    this.safetyCheckService,
    this.workflowDispatcher,
  }) : _runner = runner;

  final AppDatabase _db;
  final Clock _clock;
  final EventRunner? _runner;
  final TurnHook? onTurnStart;
  final TurnHook? onTurnEnd;
  final HandoffProcessedHook? onAgentHandoffProcessed;
  final MemoryService? memoryService;
  final ToolingService? toolingService;
  final SafetyCheckService? safetyCheckService;
  final WorkflowDispatcher? workflowDispatcher;
  final _uuid = const Uuid();

  Future<void> tick() async {
    final next = await _db.dequeueNextEligible();
    if (next == null) return;

    await _db.markProcessing(next.id);

    try {
      final event = await _db.getEventById(next.eventId);
      if (event == null) {
        await _db.markFailure(next.id, next.attemptCount + 1, next.maxAttempts);
        return;
      }

      final session = await _db.getSessionById(event.sessionId);
      if (session != null) {
        await onTurnStart?.call(event, session);
      }

      final memoryReads = session == null ? <MemoryEntry>[] : await (memoryService?.readForRun(session: session) ?? Future.value(<MemoryEntry>[]));
      final toolExecution = (session == null || toolingService == null)
          ? null
          : await toolingService!.maybeInvokeFromEvent(
              event,
              session,
              consentApproved: event.payload['toolConsentApproved'] == true,
            );
      final workflowOutput = await _maybeRunWorkflow(event, session);
      final safetyOutcome = workflowOutput is SafetyCheckOutcome ? workflowOutput : null;
      final rawOutput = workflowOutput is SafetyCheckOutcome
          ? workflowOutput.summary
          : workflowOutput is String
              ? workflowOutput
              : await (_runner?.call(event) ?? _stubRun(event));
      final output = toolExecution == null
          ? rawOutput
          : '$rawOutput\nTool ${toolExecution.invocation.toolId}: ${toolExecution.invocation.outcome} (${toolExecution.invocation.decisionReason})';
      final runResult = RunResult(
        id: _uuid.v4(),
        eventId: next.eventId,
        output: output,
        completedAt: _clock.now().millisecondsSinceEpoch,
      );

      if (session != null && memoryService != null) {
        final writes = memoryService!.buildWritesForRun(
          session: session,
          event: event,
          runResult: runResult,
          readEntries: memoryReads,
        );
        if (safetyOutcome != null) {
          final now = _clock.now().millisecondsSinceEpoch;
          writes.add(
            MemoryEntry(
              id: _uuid.v4(),
              scope: MemoryScope.session,
              scopeId: session.id,
              entryType: MemoryEntryType.fact,
              content: safetyOutcome.toMemoryContent(
                at: _clock.now(),
                mode: event.payload['modeOverride']?.toString() ?? 'latest',
                scheduled: event.payload['trigger']?.toString() != 'manual',
              ),
              sourceEventId: event.id,
              sourceRunId: runResult.id,
              sourceAgentId: session.agentId,
              sourceSessionId: session.id,
              sourceHandoffTraceId: event.payload['handoffTraceId']?.toString(),
              sourceRootEventId: event.payload['rootEventId']?.toString(),
              importance: 3,
              createdAt: now,
              updatedAt: now,
              lastAccessedAt: now,
            ),
          );
        }
        await _db.insertRunResultWithMemory(
          runResult: runResult,
          eventId: event.id,
          readEntries: memoryReads,
          writeEntries: writes,
        );
        try {
          await memoryService!.compactSessionMemory(session.id);
          await memoryService!.compactAgentMemory(session.agentId);
        } catch (_) {
          // Compaction is best-effort and must never block queue processing.
        }
      } else {
        await _db.insertRunResult(runResult);
      }

      await _applyHeartbeatSuppressionIfNeeded(event, output);
      await _db.markCompleted(next.id);

      if (session != null) {
        await onTurnEnd?.call(event, session, success: true);
        if (event.type == EventType.agentHandoff) {
          await onAgentHandoffProcessed?.call(event, session);
        }
      }
    } catch (_) {
      await _db.markFailure(next.id, next.attemptCount + 1, next.maxAttempts);
      final event = await _db.getEventById(next.eventId);
      final session = event == null ? null : await _db.getSessionById(event.sessionId);
      if (event != null && session != null) {
        await onTurnEnd?.call(event, session, success: false);
      }
    }
  }

  Future<Object?> _maybeRunWorkflow(Event event, Session? session) async {
    if (session == null || workflowDispatcher == null) return null;
    if (event.type != EventType.cron) return null;
    final result = await workflowDispatcher!.dispatch(event, session);
    if (!result.handled) return null;
    return result.output;
  }

  Future<void> _applyHeartbeatSuppressionIfNeeded(Event event, String output) async {
    if (event.type != EventType.heartbeat) return;
    final session = await _db.getSessionById(event.sessionId);
    if (session == null) return;
    final agent = await _db.getAgent(session.agentId);
    if (agent == null) return;

    final hb = agent.heartbeat;
    if (!output.contains(hb.suppressionToken)) return;

    final suppressedUntil = _clock.now().add(Duration(minutes: hb.suppressionWindowMinutes)).millisecondsSinceEpoch;
    await _db.upsertAgent(agent.copyWith(heartbeat: hb.copyWith(suppressedUntil: suppressedUntil)));
  }

  Future<String> _stubRun(Event event) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (event.id.contains('fail')) {
      throw StateError('forced failure');
    }
    if (event.type == EventType.heartbeat) {
      return 'HEARTBEAT_OK';
    }
    if (event.type == EventType.internalHook) {
      return 'hook-processed:${event.payload['hookType']}';
    }
    if (event.type == EventType.webhook) {
      return 'webhook-processed:${event.payload['relayEventId'] ?? event.id}';
    }
    return 'processed:${event.id}';
  }
}
