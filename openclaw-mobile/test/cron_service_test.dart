import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../lib/application/clock.dart';
import '../lib/application/cron_service.dart';
import '../lib/application/gateway_router.dart';
import '../lib/application/queue_processor.dart';
import '../lib/application/runtime_service.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';

class FakeClock implements Clock {
  FakeClock(this._now);
  DateTime _now;

  @override
  DateTime now() => _now;

  void set(DateTime value) => _now = value;
}

void main() {
  late AppDatabase db;
  late RuntimeService runtime;
  late QueueProcessor processor;
  late CronService cron;
  late FakeClock clock;

  setUp(() async {
    clock = FakeClock(DateTime(2026, 1, 5, 9, 0)); // Monday
    db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    runtime = RuntimeService(db, GatewayRouter(), clock);
    processor = QueueProcessor(db, clock);
    cron = CronService(db, runtime, processor, clock, catchUpCap: 2);

    await db.upsertAgent(AgentProfile(id: 'a1', name: 'A1', createdAt: clock.now().millisecondsSinceEpoch));
    await db.upsertSession(
      Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('daily schedule due emits cron event and processes', () async {
    final next = DateTime(2026, 1, 5, 9, 1).millisecondsSinceEpoch;
    await db.upsertCronSchedule(
      CronSchedule(
        scheduleId: 'daily-1',
        agentId: 'a1',
        channelId: 'mobile-chat',
        sessionId: 's1',
        enabled: true,
        rule: CronScheduleRule(type: CronScheduleType.daily, timeOfDayMinute: 9 * 60 + 1),
        timezoneId: 'local-device',
        missedRunPolicy: MissedRunPolicy.skip,
        promptTemplate: 'daily run',
        nextRunAt: next,
      ),
    );

    clock.set(DateTime(2026, 1, 5, 9, 1));
    final generated = await cron.triggerDueSchedules();
    expect(generated, 1);

    final timeline = await db.listTimelineBySession('s1');
    expect(timeline.last.event.type, EventType.cron);
    expect(timeline.last.state, QueueState.completed);
  });

  test('weekly schedule waits for matching weekday/time boundary', () async {
    final next = DateTime(2026, 1, 6, 10, 0).millisecondsSinceEpoch; // Tuesday
    await db.upsertCronSchedule(
      CronSchedule(
        scheduleId: 'weekly-1',
        agentId: 'a1',
        channelId: 'mobile-chat',
        sessionId: 's1',
        enabled: true,
        rule: CronScheduleRule(type: CronScheduleType.weekly, weekday: DateTime.tuesday, timeOfDayMinute: 600),
        timezoneId: 'local-device',
        missedRunPolicy: MissedRunPolicy.skip,
        promptTemplate: 'weekly run',
        nextRunAt: next,
      ),
    );

    final generatedNow = await cron.triggerDueSchedules();
    expect(generatedNow, 0);

    clock.set(DateTime(2026, 1, 6, 10, 0));
    final generatedLater = await cron.triggerDueSchedules();
    expect(generatedLater, 1);
  });

  test('custom schedule uses idempotency bucket to avoid duplicates', () async {
    final due = DateTime(2026, 1, 5, 9, 0).millisecondsSinceEpoch;
    await db.upsertCronSchedule(
      CronSchedule(
        scheduleId: 'custom-1',
        agentId: 'a1',
        channelId: 'mobile-chat',
        sessionId: 's1',
        enabled: true,
        rule: CronScheduleRule(type: CronScheduleType.custom, everyNMinutes: 15),
        timezoneId: 'local-device',
        missedRunPolicy: MissedRunPolicy.skip,
        promptTemplate: 'custom run',
        nextRunAt: due,
      ),
    );

    final one = await cron.triggerDueSchedules();
    final two = await cron.triggerDueSchedules();

    expect(one, 1);
    expect(two, 0);
  });

  test('missed run policy skip only emits one run', () async {
    await db.upsertCronSchedule(
      CronSchedule(
        scheduleId: 'skip-1',
        agentId: 'a1',
        channelId: 'mobile-chat',
        sessionId: 's1',
        enabled: true,
        rule: CronScheduleRule(type: CronScheduleType.custom, everyNMinutes: 10),
        timezoneId: 'local-device',
        missedRunPolicy: MissedRunPolicy.skip,
        promptTemplate: 'skip run',
        nextRunAt: DateTime(2026, 1, 5, 8, 0).millisecondsSinceEpoch,
      ),
    );

    clock.set(DateTime(2026, 1, 5, 10, 0));
    final generated = await cron.triggerDueSchedules();
    expect(generated, 1);
  });

  test('missed run policy catch up respects cap', () async {
    await db.upsertCronSchedule(
      CronSchedule(
        scheduleId: 'catch-1',
        agentId: 'a1',
        channelId: 'mobile-chat',
        sessionId: 's1',
        enabled: true,
        rule: CronScheduleRule(type: CronScheduleType.custom, everyNMinutes: 10),
        timezoneId: 'local-device',
        missedRunPolicy: MissedRunPolicy.catchUp,
        promptTemplate: 'catchup run',
        nextRunAt: DateTime(2026, 1, 5, 8, 0).millisecondsSinceEpoch,
      ),
    );

    clock.set(DateTime(2026, 1, 5, 10, 0));
    final generated = await cron.triggerDueSchedules();
    expect(generated, 2, reason: 'catch-up capped at 2 in test instance');
  });
}
