import 'package:test/test.dart';

import '../lib/domain/models.dart';

void main() {
  test('domain model serialization round-trip preserves schemaVersion', () {
    final agent = AgentProfile(
      id: 'a1',
      name: 'Agent',
      createdAt: 1,
      schemaVersion: 2,
      heartbeat: HeartbeatSettings(
        enabled: true,
        intervalMinutes: 15,
        activeHours: ActiveHoursWindow(startMinuteOfDay: 540, endMinuteOfDay: 1020),
        promptTemplate: 'ping',
      ),
    );

    final roundTrip = AgentProfile.fromJson(agent.toJson());
    expect(roundTrip.schemaVersion, 2);
    expect(roundTrip.id, 'a1');
    expect(roundTrip.heartbeat.enabled, isTrue);
    expect(roundTrip.heartbeat.intervalMinutes, 15);
  });

  test('cron schedule serialization round-trip', () {
    final schedule = CronSchedule(
      scheduleId: 'cron-1',
      agentId: 'a1',
      channelId: 'mobile-chat',
      sessionId: 's1',
      enabled: true,
      rule: CronScheduleRule(type: CronScheduleType.custom, everyNMinutes: 30),
      timezoneId: 'local-device',
      missedRunPolicy: MissedRunPolicy.catchUp,
      promptTemplate: 'Do cron work',
      lastRunAt: 10,
      nextRunAt: 20,
    );

    final roundTrip = CronSchedule.fromJson(schedule.toJson());
    expect(roundTrip.scheduleId, 'cron-1');
    expect(roundTrip.rule.type, CronScheduleType.custom);
    expect(roundTrip.rule.everyNMinutes, 30);
    expect(roundTrip.missedRunPolicy, MissedRunPolicy.catchUp);
  });
}
