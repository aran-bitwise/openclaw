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


test('handoff settings serialization round-trip', () {
  final settings = HandoffSettings.defaults().copyWith(allowedTargets: ['writer-agent']);
  final roundTrip = HandoffSettings.fromJson(settings.toJson());
  expect(roundTrip.allowedTargets, contains('writer-agent'));
  expect(roundTrip.maxConcurrentChains, greaterThan(0));
});

test('memory entry serialization supports scope and provenance', () {
  final entry = MemoryEntry(
    id: 'm1',
    scope: MemoryScope.session,
    scopeId: 's1',
    entryType: MemoryEntryType.summary,
    content: 'Summary',
    sourceEventId: 'e1',
    sourceRunId: 'r1',
    sourceAgentId: 'a1',
    sourceSessionId: 's1',
    sourceHandoffTraceId: 'trace-1',
    sourceRootEventId: 'root-1',
    importance: 3,
    pinned: true,
    summaryOfEntryIds: const ['m0', 'm2'],
    createdAt: 1,
    updatedAt: 2,
    lastAccessedAt: 3,
  );

  final roundTrip = MemoryEntry.fromJson(entry.toJson());
  expect(roundTrip.scope, MemoryScope.session);
  expect(roundTrip.sourceRunId, 'r1');
  expect(roundTrip.summaryOfEntryIds, contains('m2'));
});
