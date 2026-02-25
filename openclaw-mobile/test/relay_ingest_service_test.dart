import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../lib/application/clock.dart';
import '../lib/application/gateway_router.dart';
import '../lib/application/queue_processor.dart';
import '../lib/application/relay_ingest_service.dart';
import '../lib/application/runtime_service.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';
import '../lib/infrastructure/relay_client.dart';

class FakeClock implements Clock {
  FakeClock(this._now);
  DateTime _now;
  @override
  DateTime now() => _now;
}

class FakeRelayClient implements RelayClient {
  FakeRelayClient(this.events);

  final List<RelayEventEnvelope> events;
  final List<String> acked = [];

  @override
  Future<void> ackEvent(String relayEventId) async {
    acked.add(relayEventId);
  }

  @override
  Future<List<RelayEventEnvelope>> fetchPendingEvents({required int sinceMs, int limit = 50}) async {
    return events.where((e) => e.receivedAt >= sinceMs).take(limit).toList();
  }
}

void main() {
  late AppDatabase db;
  late RuntimeService runtime;
  late QueueProcessor processor;
  late FakeRelayClient relayClient;
  late RelayIngestService relay;

  setUp(() async {
    final clock = FakeClock(DateTime(2026, 1, 1, 9, 0));
    db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    runtime = RuntimeService(db, GatewayRouter(), clock);
    processor = QueueProcessor(db, clock);

    await db.upsertAgent(AgentProfile(id: 'a1', name: 'Agent', createdAt: clock.now().millisecondsSinceEpoch));
    await db.upsertSession(
      Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch),
    );

    relayClient = FakeRelayClient([
      RelayEventEnvelope(
        relayEventId: 'relay-1',
        receivedAt: clock.now().millisecondsSinceEpoch,
        source: 'generic',
        idempotencyKey: 'delivery-1',
        agentId: 'a1',
        channelId: 'mobile-chat',
        sessionId: 's1',
        payload: const {'text': 'hello from webhook'},
      ),
      RelayEventEnvelope(
        relayEventId: 'relay-1-dup',
        receivedAt: clock.now().millisecondsSinceEpoch,
        source: 'generic',
        idempotencyKey: 'delivery-1',
        agentId: 'a1',
        channelId: 'mobile-chat',
        sessionId: 's1',
        payload: const {'text': 'duplicate'},
      ),
    ]);

    relay = RelayIngestService(relayClient, runtime, processor, clock);
  });

  tearDown(() async {
    await db.close();
  });

  test('maps relay event to webhook event and acks', () async {
    final accepted = await relay.syncPendingRelayEvents();

    expect(accepted, 1);
    expect(relayClient.acked.length, 2, reason: 'duplicate is acked too to avoid replay loop');

    final timeline = await db.listTimelineBySession('s1');
    final webhook = timeline.firstWhere((e) => e.event.type == EventType.webhook);
    expect(webhook.event.payload['source'], 'webhook');
    expect(webhook.state, QueueState.completed);
  });
}
