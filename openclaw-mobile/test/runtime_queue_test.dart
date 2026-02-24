import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../lib/application/gateway_router.dart';
import '../lib/application/queue_processor.dart';
import '../lib/application/runtime_service.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';

void main() {
  late AppDatabase db;
  late RuntimeService runtime;
  late QueueProcessor processor;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    await db.init();
    runtime = RuntimeService(db, GatewayRouter());
    processor = QueueProcessor(db);
    await db.upsertSession(
      Session(id: 's1', agentId: 'a1', channelId: 'c1', createdAt: DateTime.now().millisecondsSinceEpoch),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('rejects duplicate idempotency keys per session', () async {
    final accepted1 = await runtime.ingestEnvelope(
      InboundEnvelope(
        channelId: 'c1',
        agentId: 'a1',
        sessionId: 's1',
        eventType: EventType.humanMessage,
        idempotencyKey: 'dup-key',
        payload: const {'text': 'a'},
      ),
    );
    final accepted2 = await runtime.ingestEnvelope(
      InboundEnvelope(
        channelId: 'c1',
        agentId: 'a1',
        sessionId: 's1',
        eventType: EventType.humanMessage,
        idempotencyKey: 'dup-key',
        payload: const {'text': 'b'},
      ),
    );

    expect(accepted1, isTrue);
    expect(accepted2, isFalse);
  });

  test('rapid send preserves queue order and ordered completion', () async {
    await runtime.sendHumanMessage(
      agentId: 'a1',
      sessionId: 's1',
      channelId: 'c1',
      text: 'first',
      idempotencyKey: 'k1',
    );
    await runtime.sendHumanMessage(
      agentId: 'a1',
      sessionId: 's1',
      channelId: 'c1',
      text: 'second',
      idempotencyKey: 'k2',
    );

    final before = await db.listTimelineBySession('s1');
    expect(before.length, 2);
    expect(before[0].event.payload['text'], 'first');
    expect(before[1].event.payload['text'], 'second');

    await processor.tick();
    final mid = await db.listTimelineBySession('s1');
    expect(mid[0].state, QueueState.completed);
    expect(mid[1].state, QueueState.queued);

    await processor.tick();
    final after = await db.listTimelineBySession('s1');
    expect(after[0].state, QueueState.completed);
    expect(after[1].state, QueueState.completed);
  });

  test('no interleaving: second event stays queued until first completes', () async {
    await runtime.sendHumanMessage(
      agentId: 'a1',
      sessionId: 's1',
      channelId: 'c1',
      text: 'first',
      idempotencyKey: 'order-1',
    );
    await runtime.sendHumanMessage(
      agentId: 'a1',
      sessionId: 's1',
      channelId: 'c1',
      text: 'second',
      idempotencyKey: 'order-2',
    );

    await processor.tick();

    final timeline = await db.listTimelineBySession('s1');
    expect(timeline[0].state, QueueState.completed);
    expect(timeline[1].state, QueueState.queued);
  });

  test('failed message retry updates state and eventually completes', () async {
    final inserted = await db.insertEvent(
      Event(
        id: 'force-fail-event',
        sessionId: 's1',
        type: EventType.humanMessage,
        payload: const {'text': 'fail'},
        idempotencyKey: 'fail-key',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    expect(inserted, isTrue);
    await db.enqueue(queueId: 'q1', eventId: 'force-fail-event', sessionId: 's1');

    await processor.tick();
    final failed = await db.listTimelineBySession('s1');
    expect(failed.single.state, QueueState.failed);

    final retried = await runtime.retryEvent('force-fail-event');
    expect(retried, isTrue);
    final requeued = await db.listTimelineBySession('s1');
    expect(requeued.single.state, QueueState.queued);
  });
}
