import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../lib/application/clock.dart';
import '../lib/application/gateway_router.dart';
import '../lib/application/hook_service.dart';
import '../lib/application/queue_processor.dart';
import '../lib/application/runtime_service.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';

class FakeClock implements Clock {
  FakeClock(this._now);
  DateTime _now;
  @override
  DateTime now() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

void main() {
  late AppDatabase db;
  late RuntimeService runtime;
  late HookService hooks;
  late QueueProcessor processor;
  late FakeClock clock;

  setUp(() async {
    clock = FakeClock(DateTime(2026, 1, 1, 9, 0));
    db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    runtime = RuntimeService(db, GatewayRouter(), clock);
    hooks = HookService(db, runtime, clock);
    processor = QueueProcessor(
      db,
      clock,
      onTurnStart: (event, session, {success}) => hooks.emitTurnStartForEvent(event, session),
      onTurnEnd: (event, session, {success}) => hooks.emitTurnEndForEvent(event, session, success: success ?? true),
    );

    await db.upsertAgent(AgentProfile(id: 'a1', name: 'A1', createdAt: clock.now().millisecondsSinceEpoch));
    await db.upsertSession(
      Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('startup hook emitted once per launch', () async {
    await hooks.emitStartupHookOnce('launch-1');
    await hooks.emitStartupHookOnce('launch-1');

    final timeline = await db.listTimelineBySession('s1');
    final startup = timeline.where((t) => t.event.payload['hookType'] == 'startup').toList();
    expect(startup.length, 1);
  });

  test('turnStart and turnEnd hook ancestry is populated', () async {
    await runtime.sendHumanMessage(agentId: 'a1', sessionId: 's1', channelId: 'mobile-chat', text: 'hello');
    await processor.tick();
    await processor.tick();
    await processor.tick();

    final timeline = await db.listTimelineBySession('s1');
    final turnStart = timeline.firstWhere((t) => t.event.payload['hookType'] == 'turnStart').event;
    final turnEnd = timeline.firstWhere((t) => t.event.payload['hookType'] == 'turnEnd').event;

    expect(turnStart.payload['rootEventId'], isNotNull);
    expect(turnStart.payload['parentEventId'], isNotNull);
    expect(turnEnd.payload['parentEventId'], isNotNull);
    expect(turnEnd.payload['depth'], greaterThanOrEqualTo(1));
  });

  test('loop prevention maxDepth and root cap enforced', () async {
    final agent = (await db.getAgent('a1'))!;
    await db.upsertAgent(agent.copyWith(hooks: agent.hooks.copyWith(maxDepth: 1, maxHookEventsPerRoot: 1)));

    await runtime.sendHumanMessage(agentId: 'a1', sessionId: 's1', channelId: 'mobile-chat', text: 'limited');
    await processor.tick();
    await processor.tick();
    await processor.tick();

    final rootEvent = (await db.listTimelineBySession('s1')).first.event.id;
    final count = await db.countHookEventsForRoot(rootEvent);
    expect(count, lessThanOrEqualTo(1));
  });
}
