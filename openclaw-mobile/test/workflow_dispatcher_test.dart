import 'package:test/test.dart';

import '../lib/application/workflow_dispatcher.dart';
import '../lib/domain/models.dart';

void main() {
  test('routes known workflow and ignores unknown', () async {
    final dispatcher = WorkflowDispatcher(
      handlers: {
        'safety_check': (event, session) async => const WorkflowDispatchResult(handled: true, output: 'ok'),
      },
    );

    final session = Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: 1);
    final known = Event(id: 'e1', sessionId: 's1', type: EventType.cron, payload: {'workflow': 'safety_check'}, idempotencyKey: 'k1', createdAt: 1);
    final unknown = Event(id: 'e2', sessionId: 's1', type: EventType.cron, payload: {'workflow': 'unknown'}, idempotencyKey: 'k2', createdAt: 1);

    final knownResult = await dispatcher.dispatch(known, session);
    final unknownResult = await dispatcher.dispatch(unknown, session);

    expect(knownResult.handled, isTrue);
    expect(knownResult.output, 'ok');
    expect(unknownResult.handled, isFalse);
    expect(unknownResult.output, isNull);
  });
}
