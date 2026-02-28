import 'clock.dart';
import 'queue_processor.dart';
import 'runtime_service.dart';
import '../domain/models.dart';
import '../infrastructure/relay_client.dart';

class RelayIngestService {
  RelayIngestService(this._relayClient, this._runtime, this._processor, this._clock);

  final RelayClient _relayClient;
  final RuntimeService _runtime;
  final QueueProcessor _processor;
  final Clock _clock;

  int _lastSyncAtMs = 0;

  Future<int> syncPendingRelayEvents({int limit = 50}) async {
    final events = await _relayClient.fetchPendingEvents(sinceMs: _lastSyncAtMs, limit: limit);
    var acceptedCount = 0;

    for (final relayEvent in events) {
      final accepted = await _runtime.ingestEnvelope(
        InboundEnvelope(
          channelId: relayEvent.channelId,
          agentId: relayEvent.agentId,
          sessionId: relayEvent.sessionId,
          eventType: EventType.webhook,
          idempotencyKey: relayEvent.idempotencyKey,
          payload: {
            'text': relayEvent.payload['text']?.toString() ?? 'Webhook event from ${relayEvent.source}',
            'source': 'webhook',
            'provider': relayEvent.source,
            'relayEventId': relayEvent.relayEventId,
            'receivedAt': relayEvent.receivedAt,
            'raw': relayEvent.payload,
          },
        ),
        createdAtMs: relayEvent.receivedAt,
      );

      // Ack on accepted OR local duplicate to preserve at-least-once semantics without replay storms.
      await _relayClient.ackEvent(relayEvent.relayEventId);
      if (accepted) acceptedCount += 1;
      if (relayEvent.receivedAt > _lastSyncAtMs) {
        _lastSyncAtMs = relayEvent.receivedAt;
      }
    }

    if (acceptedCount > 0) {
      await _processor.tick();
    }
    return acceptedCount;
  }

  void resetSyncCursor() {
    _lastSyncAtMs = 0;
  }

  int get lastSyncAtMs => _lastSyncAtMs;
}
