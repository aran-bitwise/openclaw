import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'clock.dart';

typedef EventRunner = Future<String> Function(Event event);
typedef TurnHook = Future<void> Function(Event event, Session session, {bool? success});
typedef HandoffProcessedHook = Future<void> Function(Event event, Session session);

class QueueProcessor {
  QueueProcessor(this._db, this._clock, {EventRunner? runner, this.onTurnStart, this.onTurnEnd, this.onAgentHandoffProcessed}) : _runner = runner;

  final AppDatabase _db;
  final Clock _clock;
  final EventRunner? _runner;
  final TurnHook? onTurnStart;
  final TurnHook? onTurnEnd;
  final HandoffProcessedHook? onAgentHandoffProcessed;
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

      final output = await (_runner?.call(event) ?? _stubRun(event));
      await _db.insertRunResult(
        RunResult(
          id: _uuid.v4(),
          eventId: next.eventId,
          output: output,
          completedAt: _clock.now().millisecondsSinceEpoch,
        ),
      );

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
