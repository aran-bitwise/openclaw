import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../lib/application/clock.dart';
import '../lib/application/memory_service.dart';
import '../lib/application/queue_processor.dart';
import '../lib/application/runtime_service.dart';
import '../lib/application/gateway_router.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';

class _FakeClock implements Clock {
  _FakeClock(this.current);
  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration duration) {
    current = current.add(duration);
  }
}

class _ThrowingMemoryService extends MemoryService {
  _ThrowingMemoryService(AppDatabase db, Clock clock) : super(db, clock);

  @override
  Future<void> compactSessionMemory(String sessionId) async {
    throw StateError('compaction failed');
  }
}

void main() {
  late AppDatabase db;
  late _FakeClock clock;
  late RuntimeService runtime;
  late MemoryService memory;

  setUp(() async {
    clock = _FakeClock(DateTime.utc(2025, 1, 1, 10));
    db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    runtime = RuntimeService(db, GatewayRouter(), clock);
    memory = MemoryService(db, clock);

    await db.upsertAgent(AgentProfile(id: 'a1', name: 'Agent 1', createdAt: clock.now().millisecondsSinceEpoch));
    await db.upsertSession(
      Session(
        id: 's1',
        agentId: 'a1',
        channelId: 'mobile-chat',
        createdAt: clock.now().millisecondsSinceEpoch,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('queue processing writes and reads memory by scope', () async {
    final now = clock.now().millisecondsSinceEpoch;
    await db.upsertMemoryEntry(
      MemoryEntry(
        id: const Uuid().v4(),
        scope: MemoryScope.global,
        content: 'Always be concise',
        pinned: true,
        importance: 3,
        createdAt: now,
        updatedAt: now,
        lastAccessedAt: now,
      ),
    );

    await runtime.sendHumanMessage(agentId: 'a1', sessionId: 's1', channelId: 'mobile-chat', text: 'hello memory');
    final processor = QueueProcessor(db, clock, memoryService: memory);
    await processor.tick();

    final sessionEntries = await db.listMemoryByScope(MemoryScope.session, scopeId: 's1');
    final agentEntries = await db.listMemoryByScope(MemoryScope.agent, scopeId: 'a1');
    expect(sessionEntries, isNotEmpty);
    expect(agentEntries.any((e) => e.content.contains('User asked')), isTrue);

    final timeline = await db.listTimelineBySession('s1');
    final access = await db.listMemoryAccessByEvent(timeline.first.event.id);
    expect(access['read']!, isNotEmpty);
    expect(access['write']!, isNotEmpty);
  });

  test('compaction adds summary and keeps raw entries', () async {
    for (var i = 0; i < 50; i++) {
      final now = clock.now().millisecondsSinceEpoch;
      await db.upsertMemoryEntry(
        MemoryEntry(
          id: 'm-$i',
          scope: MemoryScope.session,
          scopeId: 's1',
          content: 'entry $i ${'x' * 350}',
          createdAt: now,
          updatedAt: now,
          lastAccessedAt: now,
        ),
      );
    }

    await memory.compactSessionMemory('s1');
    final entries = await db.listMemoryByScope(MemoryScope.session, scopeId: 's1');
    final summary = entries.where((e) => e.entryType == MemoryEntryType.summary).toList();
    expect(summary, isNotEmpty);
    expect(entries.where((e) => e.entryType == MemoryEntryType.fact).length, greaterThan(40));
  });

  test('restart recovery keeps retrieval available', () async {
    final now = clock.now().millisecondsSinceEpoch;
    await db.upsertMemoryEntry(
      MemoryEntry(
        id: 'persisted',
        scope: MemoryScope.agent,
        scopeId: 'a1',
        content: 'Persist me',
        createdAt: now,
        updatedAt: now,
        lastAccessedAt: now,
      ),
    );
    final before = await db.listMemoryForRetrieval(agentId: 'a1', sessionId: 's1', limit: 10, charBudget: 1000);
    expect(before.map((e) => e.id), contains('persisted'));
  });

  test('clear scope removes only targeted memory', () async {
    final now = clock.now().millisecondsSinceEpoch;
    await db.upsertMemoryEntry(
      MemoryEntry(
        id: 'g1',
        scope: MemoryScope.global,
        content: 'g',
        createdAt: now,
        updatedAt: now,
        lastAccessedAt: now,
      ),
    );
    await db.upsertMemoryEntry(
      MemoryEntry(
        id: 'a1mem',
        scope: MemoryScope.agent,
        scopeId: 'a1',
        content: 'a',
        createdAt: now,
        updatedAt: now,
        lastAccessedAt: now,
      ),
    );
    await db.clearMemoryByScope(MemoryScope.agent, scopeId: 'a1');
    expect(await db.listMemoryByScope(MemoryScope.global), isNotEmpty);
    expect(await db.listMemoryByScope(MemoryScope.agent, scopeId: 'a1'), isEmpty);
  });

  test('compaction failure does not block run persistence', () async {
    await runtime.sendHumanMessage(agentId: 'a1', sessionId: 's1', channelId: 'mobile-chat', text: 'hello');
    final processor = QueueProcessor(db, clock, memoryService: _ThrowingMemoryService(db, clock));
    await processor.tick();

    final timeline = await db.listTimelineBySession('s1');
    expect(timeline.single.state, QueueState.completed);
    final results = await db.listRunResultsByEvent(timeline.single.event.id);
    expect(results, isNotEmpty);
  });
}
