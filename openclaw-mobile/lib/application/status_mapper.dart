import '../domain/models.dart';

String queueStateLabel(QueueState state) {
  switch (state) {
    case QueueState.queued:
      return 'queued';
    case QueueState.processing:
      return 'processing';
    case QueueState.completed:
      return 'completed';
    case QueueState.failed:
      return 'failed';
    case QueueState.deadLetter:
      return 'dead-lettered';
  }
}
