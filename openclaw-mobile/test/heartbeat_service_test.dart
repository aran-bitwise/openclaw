import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../lib/application/clock.dart';
import '../lib/application/gateway_router.dart';
import '../lib/application/heartbeat_service.dart';
import '../lib/application/queue_processor.dart';
import '../lib/application/runtime_service.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';

class FakeClock implements Clock {
  FakeClock(this._now);
  DateTime _now;
  @override
  DateTime now() => _now;
  void jumpTo(DateTime value) => _now = value;
  void advance(Duration delta) => _now = _now.add(delta);
}

void main() {
  late AppDatabase db;
  late RuntimeService runtime;
  late QueueProcessor processor;
  late HeartbeatService service;
  late FakeClock clock;

  setUp(() async {
    clock = FakeClock(DateTime(2026, 1, 1, 9, 0));
    db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    runtime = RuntimeService(db, GatewayRouter(), clock);
    processor = QueueProcessor(db, clock);
    service = HeartbeatService(db, runtime, processor, clock);

    await db.upsertAgent(
      AgentProfile(
        id: 'a1',
        name: 'Agent 1',
        createdAt: clock.now().millisecondsSinceEpoch,
        heartbeat: HeartbeatSettings(
          enabled: true,
          intervalMinutes: 10,
          activeHours: ActiveHoursWindow(startMinuteOfDay: 8 * 60, endMinuteOfDay: 22 * 60),
          promptTemplate: 'status ping',
          suppressionWindowMinutes: 60,
        ),
      ),
    );
    await db.upsertSession(
      Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('heartbeat decision logic respects active hours and interval', () async {
    final count1 = await service.triggerDueHeartbeats();
    expect(count1, 1);

    final count2 = await service.triggerDueHeartbeats();
    expect(count2, 0, reason: 'interval gating prevents immediate duplicate');

    clock.advance(const Duration(minutes: 11));
    final count3 = await service.triggerDueHeartbeats();
    expect(count3, 1);

    clock.jumpTo(DateTime(2026, 1, 1, 23, 0));
    final count4 = await service.triggerDueHeartbeats();
    expect(count4, 0, reason: 'outside active window');
  });

  test('suppression token persists and suppresses future heartbeats', () async {
    await service.triggerDueHeartbeats();
    final updated = await db.getAgent('a1');
    expect(updated?.heartbeat.suppressedUntil, isNotNull);

    clock.advance(const Duration(minutes: 30));
    final suppressed = await service.triggerDueHeartbeats();
    expect(suppressed, 0);

    clock.advance(const Duration(minutes: 35));
    final unsuppressed = await service.triggerDueHeartbeats();
    expect(unsuppressed, 1);
  });

  test('heartbeat idempotency key dedupes within same interval bucket', () async {
    final first = await service.triggerDueHeartbeats();
    expect(first, 1);

    final second = await service.triggerDueHeartbeats();
    expect(second, 0);
  });
}
