import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'clock.dart';
import 'runtime_service.dart';

class HookService {
  HookService(this._db, this._runtime, this._clock);

  final AppDatabase _db;
  final RuntimeService _runtime;
  final Clock _clock;

  bool _startupEmitted = false;
  int _sequence = 0;

  Future<void> emitStartupHookOnce(String launchId) async {
    if (_startupEmitted) return;
    final agents = await _db.listAgents();
    for (final agent in agents) {
      if (!agent.hooks.isHookEnabled(HookType.startup)) continue;
      final session = await _db.latestSessionForAgent(agent.id);
      if (session == null) continue;
      final now = _clock.now().millisecondsSinceEpoch;
      final key = 'startup-${agent.id}-$launchId';
      await _runtime.sendInternalHook(
        agentId: agent.id,
        sessionId: session.id,
        channelId: session.channelId,
        hookType: HookType.startup,
        rootEventId: key,
        parentEventId: key,
        depth: 0,
        orderKey: '$key-${_sequence++}',
        prompt: agent.hooks.promptTemplates[HookType.startup.name] ?? 'Startup hook executed.',
        idempotencyKey: key,
        createdAtMs: now,
      );
    }
    _startupEmitted = true;
  }

  Future<void> emitTurnStartForEvent(Event event, Session session) async {
    if (event.type == EventType.internalHook) return;
    await _emitHookFromEvent(event, session, HookType.turnStart, true);
  }

  Future<void> emitTurnEndForEvent(Event event, Session session, {required bool success}) async {
    if (event.type == EventType.internalHook) return;
    await _emitHookFromEvent(event, session, HookType.turnEnd, success);
  }

  Future<void> emitManualHook({required Session session, required HookType type}) async {
    final parent = 'manual-${type.name}-${_clock.now().millisecondsSinceEpoch}';
    final event = Event(
      id: parent,
      sessionId: session.id,
      type: EventType.humanMessage,
      payload: const {'source': 'manual'},
      idempotencyKey: parent,
      createdAt: _clock.now().millisecondsSinceEpoch,
    );
    await _emitHookFromEvent(event, session, type, true);
  }

  Future<void> _emitHookFromEvent(Event event, Session session, HookType hookType, bool success) async {
    final agent = await _db.getAgent(session.agentId);
    if (agent == null) return;
    final hooks = agent.hooks;
    if (!hooks.isHookEnabled(hookType)) return;

    final root = event.payload['rootEventId']?.toString() ?? event.id;
    final depth = (event.payload['depth'] as int? ?? 0) + 1;
    if (depth > hooks.maxDepth) return;

    final emitted = await _db.countHookEventsForRoot(root);
    if (emitted >= hooks.maxHookEventsPerRoot) return;

    final now = _clock.now().millisecondsSinceEpoch;
    final idempotency = 'hook-${hookType.name}-$root-$depth-${now ~/ 1000}';
    final prompt = hooks.promptTemplates[hookType.name] ?? '${hookType.name} hook';
    final suffix = success ? '' : ' (previous event failed)';
    final inserted = await _runtime.sendInternalHook(
      agentId: session.agentId,
      sessionId: session.id,
      channelId: session.channelId,
      hookType: hookType,
      rootEventId: root,
      parentEventId: event.id,
      depth: depth,
      orderKey: '$root-$depth-${_sequence++}',
      prompt: '$prompt$suffix',
      idempotencyKey: idempotency,
      createdAtMs: now + _sequence,
    );

    if (inserted) {
      }
  }
}
