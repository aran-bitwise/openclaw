import 'clock.dart';
import 'queue_processor.dart';
import 'runtime_service.dart';
import '../domain/models.dart';
import '../infrastructure/app_database.dart';

class HeartbeatService {
  HeartbeatService(this._db, this._runtime, this._processor, this._clock);

  final AppDatabase _db;
  final RuntimeService _runtime;
  final QueueProcessor _processor;
  final Clock _clock;

  Future<int> triggerDueHeartbeats() async {
    await _db.init();
    final agents = await _db.listAgents();
    var generated = 0;

    for (final agent in agents) {
      if (!shouldGenerateHeartbeat(agent.heartbeat, _clock.now())) continue;
      final session = await _db.latestSessionForAgent(agent.id);
      if (session == null) continue;

      final bucket = _heartbeatBucket(agent.heartbeat.intervalMinutes, _clock.now());
      final idempotencyKey = 'hb-${agent.id}-$bucket';
      final inserted = await _runtime.sendHeartbeat(
        agentId: agent.id,
        sessionId: session.id,
        channelId: session.channelId,
        prompt: agent.heartbeat.promptTemplate,
        idempotencyKey: idempotencyKey,
      );
      if (!inserted) continue;

      await _runtime.updateHeartbeatSettings(
        agent.id,
        agent.heartbeat.copyWith(lastFiredAt: _clock.now().millisecondsSinceEpoch),
      );
      generated += 1;
    }

    if (generated > 0) {
      await _processor.tick();
    }
    return generated;
  }

  bool shouldGenerateHeartbeat(HeartbeatSettings settings, DateTime now) {
    if (!settings.enabled) return false;

    final minuteOfDay = now.hour * 60 + now.minute;
    final inWindow = minuteOfDay >= settings.activeHours.startMinuteOfDay &&
        minuteOfDay <= settings.activeHours.endMinuteOfDay;
    if (!inWindow) return false;

    if (settings.suppressedUntil != null && now.millisecondsSinceEpoch < settings.suppressedUntil!) {
      return false;
    }

    if (settings.lastFiredAt == null) return true;
    final elapsedMs = now.millisecondsSinceEpoch - settings.lastFiredAt!;
    return elapsedMs >= Duration(minutes: settings.intervalMinutes).inMilliseconds;
  }

  int _heartbeatBucket(int intervalMinutes, DateTime now) {
    final intervalMs = Duration(minutes: intervalMinutes).inMilliseconds;
    return now.millisecondsSinceEpoch ~/ intervalMs;
  }
}
