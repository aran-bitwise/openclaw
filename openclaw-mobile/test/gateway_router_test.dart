import 'package:test/test.dart';

import '../lib/application/gateway_router.dart';
import '../lib/domain/models.dart';

void main() {
  test('gateway resolves route fields', () {
    final router = GatewayRouter();
    final route = router.resolve(
      InboundEnvelope(
        channelId: 'channel-1',
        agentId: 'agent-1',
        sessionId: 'session-1',
        eventType: EventType.message,
        idempotencyKey: 'k1',
        payload: const {'t': 'x'},
      ),
    );
    expect(route.sessionId, 'session-1');
  });
}
