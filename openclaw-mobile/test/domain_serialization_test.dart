import 'package:test/test.dart';

import '../lib/domain/models.dart';

void main() {
  test('domain model serialization round-trip preserves schemaVersion', () {
    final agent = AgentProfile(id: 'a1', name: 'Agent', createdAt: 1, schemaVersion: 2);
    final roundTrip = AgentProfile.fromJson(agent.toJson());
    expect(roundTrip.schemaVersion, 2);
    expect(roundTrip.id, 'a1');
  });
}
