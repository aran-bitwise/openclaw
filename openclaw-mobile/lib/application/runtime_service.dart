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

  Future<bool> ingestEnvelope(InboundEnvelope envelope) async {
    final route = _router.resolve(envelope);
    await _db.upsertSession(
      Session(
        id: route.sessionId,
        agentId: route.agentId,
        channelId: route.channelId,
        createdAt: _clock.now().millisecondsSinceEpoch,
      ),
    );

    final event = Event(
      id: _uuid.v4(),
      sessionId: route.sessionId,
      type: envelope.eventType,
      payload: envelope.payload,
      idempotencyKey: envelope.idempotencyKey,
      createdAt: _clock.now().millisecondsSinceEpoch,
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
  }) {
    return ingestEnvelope(
      InboundEnvelope(
        channelId: channelId,
        agentId: agentId,
        sessionId: sessionId,
        eventType: EventType.humanMessage,
        idempotencyKey: idempotencyKey ?? 'msg-${_uuid.v4()}',
        payload: {'text': text, 'source': 'human'},
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

  Future<void> updateHeartbeatSettings(String agentId, HeartbeatSettings settings) async {
    final agent = await _db.getAgent(agentId);
    if (agent == null) return;
    await _db.upsertAgent(agent.copyWith(heartbeat: settings));
  }

  Future<bool> retryEvent(String eventId) => _db.retryEvent(eventId);
}
