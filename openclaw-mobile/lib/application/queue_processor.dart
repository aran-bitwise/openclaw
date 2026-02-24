import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';

class QueueProcessor {
  QueueProcessor(this._db);
  final AppDatabase _db;
  final _uuid = const Uuid();

  Future<void> tick() async {
    final next = await _db.dequeueNextEligible();
    if (next == null) return;

    await _db.markProcessing(next.id);

    try {
      final output = await _stubRun(next.eventId);
      await _db.insertRunResult(
        RunResult(
          id: _uuid.v4(),
          eventId: next.eventId,
          output: output,
          completedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _db.markCompleted(next.id);
    } catch (_) {
      await _db.markFailure(next.id, next.attemptCount + 1, next.maxAttempts);
    }
  }

  Future<String> _stubRun(String eventId) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (eventId.contains('fail')) {
      throw StateError('forced failure');
    }
    return 'processed:$eventId';
  }
}
