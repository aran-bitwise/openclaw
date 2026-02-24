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
        eventType: EventType.message,
        idempotencyKey: 'dup-key',
        payload: const {'text': 'a'},
      ),
    );
    final accepted2 = await runtime.ingestEnvelope(
      InboundEnvelope(
        channelId: 'c1',
        agentId: 'a1',
        sessionId: 's1',
        eventType: EventType.message,
        idempotencyKey: 'dup-key',
        payload: const {'text': 'b'},
      ),
    );

    expect(accepted1, isTrue);
    expect(accepted2, isFalse);
  });

  test('processes queued event and marks completed', () async {
    await runtime.ingestEnvelope(
      InboundEnvelope(
        channelId: 'c1',
        agentId: 'a1',
        sessionId: 's1',
        eventType: EventType.message,
        idempotencyKey: 'ok-1',
        payload: const {'text': 'run'},
      ),
    );

    await processor.tick();
    final rows = await db.listQueueItems();
    expect(rows.single['state'], QueueState.completed.name);
  });

  test('failed events retry then dead-letter', () async {
    final inserted = await db.insertEvent(
      Event(
        id: 'force-fail-event',
        sessionId: 's1',
        type: EventType.message,
        payload: const {'text': 'fail'},
        idempotencyKey: 'fail-key',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    expect(inserted, isTrue);
    await db.enqueue(queueId: 'q1', eventId: 'force-fail-event', sessionId: 's1');

    await processor.tick();
    await processor.tick();
    await processor.tick();
    await processor.tick();

    final rows = await db.listQueueItems();
    expect(rows.single['state'], QueueState.deadLetter.name);
  });
}
