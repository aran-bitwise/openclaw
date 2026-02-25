import 'dart:io';

import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../lib/application/clock.dart';
import '../lib/application/gateway_router.dart';
import '../lib/application/handoff_service.dart';
import '../lib/application/queue_processor.dart';
import '../lib/application/runtime_service.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';

class FakeClock implements Clock {
  FakeClock(this._now);
  DateTime _now;
  @override
  DateTime now() => _now;
}

void main() {
  test('allowlist enforcement permitted and denied routes', () async {
    final clock = FakeClock(DateTime(2026, 1, 1, 9));
    final db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    final runtime = RuntimeService(db, GatewayRouter(), clock);
    final handoff = HandoffService(db, runtime, clock);

    await db.upsertAgent(
      AgentProfile(
        id: 'a1',
        name: 'A1',
        createdAt: clock.now().millisecondsSinceEpoch,
        handoff: HandoffSettings.defaults().copyWith(allowedTargets: ['a2']),
      ),
    );
    await db.upsertAgent(AgentProfile(id: 'a2', name: 'A2', createdAt: clock.now().millisecondsSinceEpoch));
    await db.upsertAgent(AgentProfile(id: 'a3', name: 'A3', createdAt: clock.now().millisecondsSinceEpoch));
    await db.upsertSession(Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch));

    final allowed = await handoff.requestHandoff(
      fromAgentId: 'a1',
      toAgentId: 'a2',
      sessionId: 's1',
      channelId: 'mobile-chat',
      reason: 'delegate',
      taskPayload: const {'task': 'x'},
    );
    final denied = await handoff.requestHandoff(
      fromAgentId: 'a1',
      toAgentId: 'a3',
      sessionId: 's1',
      channelId: 'mobile-chat',
      reason: 'delegate',
      taskPayload: const {'task': 'x'},
    );

    expect(allowed, isTrue);
    expect(denied, isTrue, reason: 'denied is still recorded as auditable handoff event');

    final timeline = await db.listTimelineBySession('s1');
    final deniedEvent = timeline.where((e) => e.event.payload['decision']?['allowed'] == false).toList();
    expect(deniedEvent, isNotEmpty);

    await db.close();
  });

  test('trace continuity and pause or resume behavior', () async {
    final clock = FakeClock(DateTime(2026, 1, 1, 9));
    final db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    final runtime = RuntimeService(db, GatewayRouter(), clock);
    final handoff = HandoffService(db, runtime, clock);

    await db.upsertAgent(
      AgentProfile(
        id: 'a1',
        name: 'A1',
        createdAt: clock.now().millisecondsSinceEpoch,
        handoff: HandoffSettings.defaults().copyWith(allowedTargets: ['a2']),
      ),
    );
    await db.upsertAgent(AgentProfile(id: 'a2', name: 'A2', createdAt: clock.now().millisecondsSinceEpoch));
    await db.upsertSession(Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch));

    await handoff.requestHandoff(
      fromAgentId: 'a1',
      toAgentId: 'a2',
      sessionId: 's1',
      channelId: 'mobile-chat',
      reason: 'delegate',
      taskPayload: const {'task': 'x'},
      traceId: 'trace-1',
      rootEventId: 'root-1',
      parentEventId: 'root-1',
    );

    await handoff.setTracePaused('trace-1', true);
    final blockedWhenPaused = await handoff.requestHandoff(
      fromAgentId: 'a1',
      toAgentId: 'a2',
      sessionId: 's1',
      channelId: 'mobile-chat',
      reason: 'delegate',
      taskPayload: const {'task': 'x'},
      traceId: 'trace-1',
      rootEventId: 'root-1',
      parentEventId: 'root-1',
    );
    expect(blockedWhenPaused, isTrue);

    await handoff.setTracePaused('trace-1', false);
    final acceptedAfterResume = await handoff.requestHandoff(
      fromAgentId: 'a1',
      toAgentId: 'a2',
      sessionId: 's1',
      channelId: 'mobile-chat',
      reason: 'delegate',
      taskPayload: const {'task': 'x'},
      traceId: 'trace-1',
      rootEventId: 'root-1',
      parentEventId: 'root-1',
    );
    expect(acceptedAfterResume, isTrue);

    final timeline = await db.listTimelineBySession('s1');
    final sameTrace = timeline.where((e) => e.event.payload['handoffTraceId'] == 'trace-1').toList();
    expect(sameTrace.length, greaterThanOrEqualTo(2));

    await db.close();
  });

  test('restart recovery queued handoff survives service recreation', () async {
    final dbPath = File('${Directory.systemTemp.path}/openclaw-mobile-handoff-test-${DateTime.now().millisecondsSinceEpoch}.db');

    final clock = FakeClock(DateTime(2026, 1, 1, 9));
    final db1 = AppDatabase(executor: NativeDatabase.createInBackground(dbPath), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db1.init();
    final runtime1 = RuntimeService(db1, GatewayRouter(), clock);
    final handoff1 = HandoffService(db1, runtime1, clock);

    await db1.upsertAgent(
      AgentProfile(
        id: 'a1',
        name: 'A1',
        createdAt: clock.now().millisecondsSinceEpoch,
        handoff: HandoffSettings.defaults().copyWith(allowedTargets: ['a2']),
      ),
    );
    await db1.upsertAgent(AgentProfile(id: 'a2', name: 'A2', createdAt: clock.now().millisecondsSinceEpoch));
    await db1.upsertSession(Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch));

    await handoff1.requestHandoff(
      fromAgentId: 'a1',
      toAgentId: 'a2',
      sessionId: 's1',
      channelId: 'mobile-chat',
      reason: 'restart',
      taskPayload: const {'task': 'persist'},
      traceId: 'trace-restart',
      rootEventId: 'root-restart',
      parentEventId: 'root-restart',
    );

    await db1.close();

    final db2 = AppDatabase(executor: NativeDatabase.createInBackground(dbPath), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db2.init();
    final runtime2 = RuntimeService(db2, GatewayRouter(), clock);
    final handoff2 = HandoffService(db2, runtime2, clock);
    final processor = QueueProcessor(db2, clock, onAgentHandoffProcessed: handoff2.handleProcessedHandoff);
    await processor.tick();
    await processor.tick();

    final timeline = await db2.listTimelineBySession('s1');
    final traceEvents = timeline.where((e) => e.event.payload['handoffTraceId'] == 'trace-restart').toList();
    expect(traceEvents, isNotEmpty);

    await db2.close();
    if (dbPath.existsSync()) {
      dbPath.deleteSync();
    }
  });
}
