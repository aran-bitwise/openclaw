import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'clock.dart';
import 'runtime_service.dart';

class HandoffService {
  HandoffService(this._db, this._runtime, this._clock);

  final AppDatabase _db;
  final RuntimeService _runtime;
  final Clock _clock;
  final _uuid = const Uuid();
  int _sequence = 0;

  Future<bool> requestHandoff({
    required String fromAgentId,
    required String toAgentId,
    required String sessionId,
    required String channelId,
    required String reason,
    required Map<String, dynamic> taskPayload,
    String? rootEventId,
    String? parentEventId,
    String? traceId,
    int depth = 0,
  }) async {
    final sourceAgent = await _db.getAgent(fromAgentId);
    if (sourceAgent == null) return false;

    final effectiveTraceId = traceId ?? 'trace-${_uuid.v4()}';
    final effectiveRoot = rootEventId ?? 'root-${_uuid.v4()}';
    final effectiveParent = parentEventId ?? effectiveRoot;

    final activeChains = await _db.countActiveHandoffTraces();
    if (activeChains >= sourceAgent.handoff.maxConcurrentChains) {
      return _emitDenied(
        fromAgentId: fromAgentId,
        toAgentId: toAgentId,
        sessionId: sessionId,
        channelId: channelId,
        reason: reason,
        taskPayload: taskPayload,
        traceId: effectiveTraceId,
        rootEventId: effectiveRoot,
        parentEventId: effectiveParent,
        depth: depth,
        denyReason: 'concurrent_cap_exceeded',
      );
    }

    final trace = await _db.getHandoffTrace(effectiveTraceId);
    if (trace != null && trace['paused'] == 1) {
      return _emitDenied(
        fromAgentId: fromAgentId,
        toAgentId: toAgentId,
        sessionId: sessionId,
        channelId: channelId,
        reason: reason,
        taskPayload: taskPayload,
        traceId: effectiveTraceId,
        rootEventId: effectiveRoot,
        parentEventId: effectiveParent,
        depth: depth,
        denyReason: 'trace_paused',
      );
    }

    if (!sourceAgent.handoff.enabled || !sourceAgent.handoff.allowedTargets.contains(toAgentId)) {
      return _emitDenied(
        fromAgentId: fromAgentId,
        toAgentId: toAgentId,
        sessionId: sessionId,
        channelId: channelId,
        reason: reason,
        taskPayload: taskPayload,
        traceId: effectiveTraceId,
        rootEventId: effectiveRoot,
        parentEventId: effectiveParent,
        depth: depth,
        denyReason: 'allowlist_denied',
      );
    }

    final nextDepth = depth + 1;
    if (nextDepth > sourceAgent.handoff.maxDepth) {
      return _emitDenied(
        fromAgentId: fromAgentId,
        toAgentId: toAgentId,
        sessionId: sessionId,
        channelId: channelId,
        reason: reason,
        taskPayload: taskPayload,
        traceId: effectiveTraceId,
        rootEventId: effectiveRoot,
        parentEventId: effectiveParent,
        depth: depth,
        denyReason: 'depth_cap_exceeded',
      );
    }

    final chainCap = sourceAgent.handoff.maxDepth;
    if (trace != null && (trace['depth'] as int? ?? 0) >= chainCap) {
      return _emitDenied(
        fromAgentId: fromAgentId,
        toAgentId: toAgentId,
        sessionId: sessionId,
        channelId: channelId,
        reason: reason,
        taskPayload: taskPayload,
        traceId: effectiveTraceId,
        rootEventId: effectiveRoot,
        parentEventId: effectiveParent,
        depth: depth,
        denyReason: 'chain_cap_exceeded',
      );
    }

    final decision = {
      'allowed': true,
      'reason': sourceAgent.handoff.requireApprovalForHighRisk ? 'allowed_low_risk_or_auto_approved' : 'allowed',
      'approvalRequired': sourceAgent.handoff.requireApprovalForHighRisk,
      'approved': true,
    };

    final inserted = await _runtime.sendAgentHandoff(
      fromAgentId: fromAgentId,
      toAgentId: toAgentId,
      sessionId: sessionId,
      channelId: channelId,
      handoffReason: reason,
      taskPayload: taskPayload,
      handoffTraceId: effectiveTraceId,
      decision: decision,
      rootEventId: effectiveRoot,
      parentEventId: effectiveParent,
      depth: nextDepth,
      orderKey: '$effectiveTraceId-${_sequence++}',
      idempotencyKey: 'handoff-$effectiveTraceId-$nextDepth-${_sequence++}',
    );

    if (!inserted) return false;

    await _db.upsertHandoffTrace(
      traceId: effectiveTraceId,
      rootEventId: effectiveRoot,
      sourceAgentId: fromAgentId,
      currentAgentId: toAgentId,
      paused: false,
      depth: nextDepth,
      visitedAgents: [fromAgentId, toAgentId],
      active: true,
    );

    return true;
  }

  Future<void> handleProcessedHandoff(Event event, Session session) async {
    if (event.type != EventType.agentHandoff) return;
    final decision = Map<String, dynamic>.from(event.payload['decision'] as Map? ?? {});
    if (decision['allowed'] != true) return;
    final phase = event.payload['phase']?.toString() ?? 'request';
    if (phase == 'result') return;

    final traceId = event.payload['handoffTraceId']?.toString();
    if (traceId == null) return;

    final fromAgentId = event.payload['fromAgentId']?.toString() ?? session.agentId;
    final toAgentId = event.payload['toAgentId']?.toString() ?? session.agentId;
    final rootEventId = event.payload['rootEventId']?.toString() ?? event.id;
    final depth = (event.payload['depth'] as int? ?? 0) + 1;

    await _runtime.sendAgentHandoff(
      fromAgentId: toAgentId,
      toAgentId: fromAgentId,
      sessionId: session.id,
      channelId: session.channelId,
      handoffReason: 'handoff_result',
      taskPayload: {
        'result': 'Task handled by $toAgentId',
        'originalTask': event.payload['taskPayload'],
      },
      handoffTraceId: traceId,
      decision: const {'allowed': true, 'reason': 'handoff_result_return'},
      rootEventId: rootEventId,
      parentEventId: event.id,
      depth: depth,
      orderKey: '$traceId-${_sequence++}',
      idempotencyKey: 'handoff-result-$traceId-$depth-${_sequence++}',
      phase: 'result',
    );

    await _db.upsertHandoffTrace(
      traceId: traceId,
      rootEventId: rootEventId,
      sourceAgentId: fromAgentId,
      currentAgentId: fromAgentId,
      paused: false,
      depth: depth,
      visitedAgents: [fromAgentId, toAgentId],
      active: false,
    );
  }

  Future<void> setTracePaused(String traceId, bool paused) => _db.setHandoffTracePaused(traceId, paused);

  Future<List<Map<String, dynamic>>> listTracesForAgent(String agentId) => _db.listHandoffTracesByAgent(agentId);

  Future<bool> runDemoResearchToWriter({
    required String sourceAgentId,
    required String targetAgentId,
    required String sessionId,
    required String channelId,
    required String message,
  }) {
    return requestHandoff(
      fromAgentId: sourceAgentId,
      toAgentId: targetAgentId,
      sessionId: sessionId,
      channelId: channelId,
      reason: 'research_to_writer_demo',
      taskPayload: {'message': message, 'pipeline': 'research->writer'},
    );
  }

  Future<bool> _emitDenied({
    required String fromAgentId,
    required String toAgentId,
    required String sessionId,
    required String channelId,
    required String reason,
    required Map<String, dynamic> taskPayload,
    required String traceId,
    required String rootEventId,
    required String parentEventId,
    required int depth,
    required String denyReason,
  }) {
    return _runtime.sendAgentHandoff(
      fromAgentId: fromAgentId,
      toAgentId: toAgentId,
      sessionId: sessionId,
      channelId: channelId,
      handoffReason: reason,
      taskPayload: taskPayload,
      handoffTraceId: traceId,
      decision: {'allowed': false, 'reason': denyReason},
      rootEventId: rootEventId,
      parentEventId: parentEventId,
      depth: depth,
      orderKey: '$traceId-deny-${_sequence++}',
      idempotencyKey: 'handoff-denied-$traceId-${_sequence++}',
    );
  }
}
