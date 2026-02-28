import 'package:test/test.dart';

import '../lib/application/status_mapper.dart';
import '../lib/domain/models.dart';

void main() {
  test('maps queue states to UI labels', () {
    expect(queueStateLabel(QueueState.queued), 'queued');
    expect(queueStateLabel(QueueState.processing), 'processing');
    expect(queueStateLabel(QueueState.completed), 'completed');
    expect(queueStateLabel(QueueState.failed), 'failed');
    expect(queueStateLabel(QueueState.deadLetter), 'dead-lettered');
  });
}
