import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/clock.dart';
import '../application/cron_service.dart';
import '../application/gateway_router.dart';
import '../application/heartbeat_service.dart';
import '../application/hook_service.dart';
import '../application/queue_processor.dart';
import '../application/runtime_service.dart';
import '../domain/models.dart';
import '../infrastructure/app_database.dart';

final clockProvider = Provider<Clock>((_) => SystemClock());

final databaseProvider = Provider<AppDatabase>((ref) {
  final clock = ref.watch(clockProvider);
  final db = AppDatabase(nowMs: () => clock.now().millisecondsSinceEpoch);
  ref.onDispose(db.close);
  return db;
});

final runtimeProvider = Provider<RuntimeService>((ref) {
  return RuntimeService(ref.watch(databaseProvider), GatewayRouter(), ref.watch(clockProvider));
});

final hookServiceProvider = Provider<HookService>((ref) {
  return HookService(ref.watch(databaseProvider), ref.watch(runtimeProvider), ref.watch(clockProvider));
});

final queueProcessorProvider = Provider<QueueProcessor>((ref) {
  return QueueProcessor(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
    onTurnStart: (event, session, {success}) => ref.read(hookServiceProvider).emitTurnStartForEvent(event, session),
    onTurnEnd: (event, session, {success}) => ref
        .read(hookServiceProvider)
        .emitTurnEndForEvent(event, session, success: success ?? true),
  );
});

final cronServiceProvider = Provider<CronService>((ref) {
  return CronService(
    ref.watch(databaseProvider),
    ref.watch(runtimeProvider),
    ref.watch(queueProcessorProvider),
    ref.watch(clockProvider),
  );
});

final heartbeatServiceProvider = Provider<HeartbeatService>((ref) {
  return HeartbeatService(
    ref.watch(databaseProvider),
    ref.watch(runtimeProvider),
    ref.watch(queueProcessorProvider),
    ref.watch(clockProvider),
  );
});

final agentsProvider = FutureProvider<List<AgentProfile>>((ref) async {
  final db = ref.watch(databaseProvider);
  await db.init();
  return db.listAgents();
});

final selectedAgentIdProvider = StateProvider<String?>((_) => null);
final selectedSessionIdProvider = StateProvider<String?>((_) => null);

final sessionsByAgentProvider = FutureProvider<List<Session>>((ref) async {
  final db = ref.watch(databaseProvider);
  await db.init();
  final agentId = ref.watch(selectedAgentIdProvider);
  if (agentId == null) return [];
  return db.listSessionsByAgent(agentId);
});

final timelineProvider = FutureProvider<List<TimelineItem>>((ref) async {
  final db = ref.watch(databaseProvider);
  await db.init();
  final sessionId = ref.watch(selectedSessionIdProvider);
  if (sessionId == null) return [];
  return db.listTimelineBySession(sessionId);
});

final queueViewProvider = FutureProvider<List<Map<String, Object?>>>((ref) async {
  final db = ref.watch(databaseProvider);
  await db.init();
  return db.listQueueItems();
});
