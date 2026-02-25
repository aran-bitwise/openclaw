import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'clock.dart';
import 'gateway_router.dart';

class RuntimeService {
  RuntimeService(this._db, this._router, this._clock);

  final AppDatabase _db;
  final GatewayRouter _router;
  final Clock _clock;
  final _uuid = const Uuid();

  Future<bool> ingestEnvelope(InboundEnvelope envelope, {int? createdAtMs}) async {
    final route = _router.resolve(envelope);
    final createdAt = createdAtMs ?? _clock.now().millisecondsSinceEpoch;

    await _db.upsertSession(
      Session(
        id: route.sessionId,
        agentId: route.agentId,
        channelId: route.channelId,
        createdAt: createdAt,
      ),
    );

    final event = Event(
      id: _uuid.v4(),
      sessionId: route.sessionId,
      type: envelope.eventType,
      payload: envelope.payload,
      idempotencyKey: envelope.idempotencyKey,
      createdAt: createdAt,
    );
    final inserted = await _db.insertEvent(event);
    if (!inserted) return false;

    await _db.enqueue(queueId: _uuid.v4(), eventId: event.id, sessionId: route.sessionId);
    return true;
  }

  Future<bool> sendHumanMessage({
    required String agentId,
    required String sessionId,
    required String channelId,
    required String text,
    String? idempotencyKey,
    String phase = 'request',
    Map<String, dynamic>? extraPayload,
  }) {
    return ingestEnvelope(
      InboundEnvelope(
        channelId: channelId,
        agentId: agentId,
        sessionId: sessionId,
        eventType: EventType.humanMessage,
        idempotencyKey: idempotencyKey ?? 'msg-${_uuid.v4()}',
        payload: {
          'text': text,
          'source': 'human',
          if (extraPayload != null) ...extraPayload,
        },
      ),
    );
  }

  Future<bool> sendHeartbeat({
    required String agentId,
    required String sessionId,
    required String channelId,
    required String prompt,
    required String idempotencyKey,
  }) {
    return ingestEnvelope(
      InboundEnvelope(
        channelId: channelId,
        agentId: agentId,
        sessionId: sessionId,
        eventType: EventType.heartbeat,
        idempotencyKey: idempotencyKey,
        payload: {
          'text': prompt,
          'source': 'heartbeat',
          'generatedAt': _clock.now().toIso8601String(),
        },
      ),
    );
  }

  Future<bool> sendCron({
    required String agentId,
    required String sessionId,
    required String channelId,
    required String prompt,
    required String scheduleId,
    required int dueAt,
    required String idempotencyKey,
  }) {
    return ingestEnvelope(
      InboundEnvelope(
        channelId: channelId,
        agentId: agentId,
        sessionId: sessionId,
        eventType: EventType.cron,
        idempotencyKey: idempotencyKey,
        payload: {
          'text': prompt,
          'source': 'cron',
          'scheduleId': scheduleId,
          'dueAt': dueAt,
          'generatedAt': _clock.now().toIso8601String(),
        },
      ),
    );
  }

  Future<bool> sendInternalHook({
    required String agentId,
    required String sessionId,
    required String channelId,
    required HookType hookType,
    required String rootEventId,
    required String parentEventId,
    required int depth,
    required String orderKey,
    required String prompt,
    required String idempotencyKey,
    int? createdAtMs,
  }) {
    return ingestEnvelope(
      InboundEnvelope(
        channelId: channelId,
        agentId: agentId,
        sessionId: sessionId,
        eventType: EventType.internalHook,
        idempotencyKey: idempotencyKey,
        payload: {
          'text': prompt,
          'source': 'internalHook',
          'hookType': hookType.name,
          'rootEventId': rootEventId,
          'parentEventId': parentEventId,
          'depth': depth,
          'orderKey': orderKey,
        },
      ),
      createdAtMs: createdAtMs,
    );
  }


  Future<bool> sendAgentHandoff({
    required String fromAgentId,
    required String toAgentId,
    required String sessionId,
    required String channelId,
    required String handoffReason,
    required Map<String, dynamic> taskPayload,
    required String handoffTraceId,
    required Map<String, dynamic> decision,
    required String rootEventId,
    required String parentEventId,
    required int depth,
    required String orderKey,
    String? idempotencyKey,
    String phase = 'request',
  }) {
    return ingestEnvelope(
      InboundEnvelope(
        channelId: channelId,
        agentId: toAgentId,
        sessionId: sessionId,
        eventType: EventType.agentHandoff,
        idempotencyKey: idempotencyKey ?? 'handoff-${_uuid.v4()}',
        payload: {
          'text': 'Handoff: $handoffReason',
          'source': 'agentHandoff',
          'fromAgentId': fromAgentId,
          'toAgentId': toAgentId,
          'handoffReason': handoffReason,
          'taskPayload': taskPayload,
          'handoffTraceId': handoffTraceId,
          'decision': decision,
          'phase': phase,
          'rootEventId': rootEventId,
          'parentEventId': parentEventId,
          'depth': depth,
          'orderKey': orderKey,
        },
      ),
    );
  }

  Future<void> updateHeartbeatSettings(String agentId, HeartbeatSettings settings) async {
    final agent = await _db.getAgent(agentId);
    if (agent == null) return;
    await _db.upsertAgent(agent.copyWith(heartbeat: settings));
  }

  Future<void> updateHookSettings(String agentId, HookSettings settings) async {
    final agent = await _db.getAgent(agentId);
    if (agent == null) return;
    await _db.upsertAgent(agent.copyWith(hooks: settings));
  }

  Future<void> updateHandoffSettings(String agentId, HandoffSettings settings) async {
    final agent = await _db.getAgent(agentId);
    if (agent == null) return;
    await _db.upsertAgent(agent.copyWith(handoff: settings));
  }

  Future<bool> retryEvent(String eventId) => _db.retryEvent(eventId);
}
