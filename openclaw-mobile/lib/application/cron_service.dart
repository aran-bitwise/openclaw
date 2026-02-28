import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'clock.dart';
import 'queue_processor.dart';
import 'runtime_service.dart';

class CronService {
  CronService(this._db, this._runtime, this._processor, this._clock, {this.catchUpCap = 3});

  final AppDatabase _db;
  final RuntimeService _runtime;
  final QueueProcessor _processor;
  final Clock _clock;
  final int catchUpCap;
  final _uuid = const Uuid();

  Future<int> triggerDueSchedules() async {
    await _db.init();
    final schedules = await _db.listCronSchedules();
    var generated = 0;

    for (final schedule in schedules) {
      if (!schedule.enabled) continue;
      final dueTimes = _resolveDueTimes(schedule, _clock.now());
      if (dueTimes.isEmpty) continue;

      var mutable = schedule;
      for (final dueAt in dueTimes) {
        final idempotencyKey = 'cron-${schedule.scheduleId}-${dueAt ~/ 60000}';
        final inserted = await _runtime.sendCron(
          agentId: schedule.agentId,
          sessionId: schedule.sessionId,
          channelId: schedule.channelId,
          prompt: schedule.promptTemplate,
          scheduleId: schedule.scheduleId,
          dueAt: dueAt,
          idempotencyKey: idempotencyKey,
          extraPayload: _isSafetySchedule(schedule) ? _safetyPayload(scheduleId: schedule.scheduleId, dueAt: dueAt, mode: 'latest', trigger: 'scheduled', consentApproved: false) : null,
        );

        mutable = mutable.copyWith(lastRunAt: dueAt, nextRunAt: _nextOccurrence(schedule.rule, dueAt));
        await _db.upsertCronSchedule(mutable);

        if (inserted) generated += 1;
      }
    }

    if (generated > 0) {
      await _processor.tick();
    }
    return generated;
  }

  Future<void> createDefaultSchedule({required String agentId, required String sessionId, required String channelId}) async {
    final now = _clock.now();
    final first = now.add(const Duration(minutes: 5));
    final minute = first.hour * 60 + first.minute;
    final schedule = CronSchedule(
      scheduleId: 'cron-${_uuid.v4()}',
      agentId: agentId,
      channelId: channelId,
      sessionId: sessionId,
      enabled: true,
      rule: CronScheduleRule(type: CronScheduleType.daily, timeOfDayMinute: minute),
      timezoneId: 'local-device',
      missedRunPolicy: MissedRunPolicy.skip,
      promptTemplate: 'Daily cron check-in.',
      nextRunAt: _nextOccurrence(CronScheduleRule(type: CronScheduleType.daily, timeOfDayMinute: minute), now.millisecondsSinceEpoch),
    );
    await _db.upsertCronSchedule(schedule);
  }

  Future<void> runScheduleNow(String scheduleId) async {
    final schedule = await _db.getCronSchedule(scheduleId);
    if (schedule == null) return;
    final dueAt = _clock.now().millisecondsSinceEpoch;
    final idempotencyKey = 'cron-${schedule.scheduleId}-${dueAt ~/ 60000}';
    final inserted = await _runtime.sendCron(
      agentId: schedule.agentId,
      sessionId: schedule.sessionId,
      channelId: schedule.channelId,
      prompt: schedule.promptTemplate,
      scheduleId: schedule.scheduleId,
      dueAt: dueAt,
      idempotencyKey: idempotencyKey,
      extraPayload: _isSafetySchedule(schedule) ? _safetyPayload(scheduleId: schedule.scheduleId, dueAt: dueAt, mode: 'latest', trigger: 'scheduled', consentApproved: false) : null,
    );

    if (inserted) {
      await _db.upsertCronSchedule(schedule.copyWith(lastRunAt: dueAt, nextRunAt: _nextOccurrence(schedule.rule, dueAt)));
      await _processor.tick();
    }
  }

  Future<void> createSafetyCheckSchedule({required String agentId, required String sessionId, required String channelId}) async {
    final now = _clock.now();
    final first = now.add(const Duration(minutes: 2));
    final minute = first.hour * 60 + first.minute;
    final schedule = CronSchedule(
      scheduleId: 'safety-check-${_uuid.v4()}',
      agentId: agentId,
      channelId: channelId,
      sessionId: sessionId,
      enabled: true,
      rule: CronScheduleRule(type: CronScheduleType.daily, timeOfDayMinute: minute),
      timezoneId: 'local-device',
      missedRunPolicy: MissedRunPolicy.skip,
      promptTemplate: 'Safety Check Run',
      nextRunAt: _nextOccurrence(CronScheduleRule(type: CronScheduleType.daily, timeOfDayMinute: minute), now.millisecondsSinceEpoch),
    );
    await _db.upsertCronSchedule(schedule);
  }

  Future<void> runSafetyCheckNow({
    required String agentId,
    required String sessionId,
    required String channelId,
    String modeOverride = 'latest',
    String? replayCheckId,
  }) async {
    final dueAt = _clock.now().millisecondsSinceEpoch;
    final bucket = dueAt ~/ 60000;
    final idempotencyKey = 'safety-manual-$sessionId-$modeOverride-$bucket';
    final inserted = await _runtime.sendCron(
      agentId: agentId,
      sessionId: sessionId,
      channelId: channelId,
      prompt: 'Safety Check Run',
      scheduleId: 'safety-manual',
      dueAt: dueAt,
      idempotencyKey: idempotencyKey,
      extraPayload: {
        ..._safetyPayload(scheduleId: 'safety-manual', dueAt: dueAt, mode: modeOverride, trigger: 'manual', consentApproved: true),
        if (replayCheckId != null) 'checkId': replayCheckId,
      },
    );
    if (inserted) {
      await _processor.tick();
    }
  }

  bool _isSafetySchedule(CronSchedule schedule) {
    return schedule.scheduleId.startsWith('safety-check-') || schedule.promptTemplate.toLowerCase().contains('safety check');
  }



  Map<String, dynamic> _safetyPayload({
    required String scheduleId,
    required int dueAt,
    required String mode,
    required String trigger,
    required bool consentApproved,
  }) {
    return {
      'workflow': 'safety_check',
      'trigger': trigger,
      'modeOverride': mode,
      'checkId': _checkId(scheduleId: scheduleId, dueAt: dueAt, mode: mode),
      'toolConsentApproved': consentApproved,
    };
  }

  String _checkId({required String scheduleId, required int dueAt, required String mode}) {
    final bucket = dueAt ~/ 60000;
    return 'check:$scheduleId:$mode:$bucket';
  }

  List<int> _resolveDueTimes(CronSchedule schedule, DateTime now) {
    final nowMs = now.millisecondsSinceEpoch;
    final firstDue = schedule.nextRunAt ?? _nextOccurrence(schedule.rule, schedule.lastRunAt ?? nowMs - 60000);
    if (firstDue > nowMs) {
      return [];
    }

    if (schedule.missedRunPolicy == MissedRunPolicy.skip) {
      return [firstDue];
    }

    final due = <int>[];
    var cursor = firstDue;
    var count = 0;
    while (cursor <= nowMs && count < catchUpCap) {
      due.add(cursor);
      cursor = _nextOccurrence(schedule.rule, cursor);
      count += 1;
    }
    return due;
  }

  int _nextOccurrence(CronScheduleRule rule, int fromMs) {
    final from = DateTime.fromMillisecondsSinceEpoch(fromMs).toLocal();
    switch (rule.type) {
      case CronScheduleType.daily:
        final minute = rule.timeOfDayMinute ?? 9 * 60;
        var candidate = DateTime(from.year, from.month, from.day, minute ~/ 60, minute % 60);
        if (!candidate.isAfter(from)) {
          candidate = candidate.add(const Duration(days: 1));
        }
        return candidate.millisecondsSinceEpoch;
      case CronScheduleType.weekly:
        final weekday = rule.weekday ?? DateTime.monday;
        final minute = rule.timeOfDayMinute ?? 9 * 60;
        var daysAhead = (weekday - from.weekday) % 7;
        var candidate = DateTime(from.year, from.month, from.day, minute ~/ 60, minute % 60).add(Duration(days: daysAhead));
        if (!candidate.isAfter(from)) {
          candidate = candidate.add(const Duration(days: 7));
        }
        return candidate.millisecondsSinceEpoch;
      case CronScheduleType.custom:
        final minutes = (rule.everyNMinutes ?? 60).clamp(5, 720).toInt();
        final bucketMs = Duration(minutes: minutes).inMilliseconds;
        return ((fromMs ~/ bucketMs) + 1) * bucketMs;
    }
  }
}
