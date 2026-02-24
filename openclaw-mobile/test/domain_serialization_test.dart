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
}
