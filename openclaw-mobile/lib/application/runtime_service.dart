import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'gateway_router.dart';

class RuntimeService {
  RuntimeService(this._db, this._router);

  final AppDatabase _db;
  final GatewayRouter _router;
  final _uuid = const Uuid();

  Future<bool> ingestEnvelope(InboundEnvelope envelope) async {
    final route = _router.resolve(envelope);
    await _db.upsertSession(
      Session(
        id: route.sessionId,
        agentId: route.agentId,
        channelId: route.channelId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final event = Event(
      id: _uuid.v4(),
      sessionId: route.sessionId,
      type: envelope.eventType,
      payload: envelope.payload,
      idempotencyKey: envelope.idempotencyKey,
      createdAt: DateTime.now().millisecondsSinceEpoch,
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
        payload: {'text': text},
      ),
    );
  }

  Future<bool> retryEvent(String eventId) => _db.retryEvent(eventId);
}
