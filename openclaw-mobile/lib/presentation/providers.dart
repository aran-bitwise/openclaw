import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/gateway_router.dart';
import '../application/queue_processor.dart';
import '../application/runtime_service.dart';
import '../domain/models.dart';
import '../infrastructure/app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final runtimeProvider = Provider<RuntimeService>((ref) {
  return RuntimeService(ref.watch(databaseProvider), GatewayRouter());
});

final queueProcessorProvider = Provider<QueueProcessor>((ref) {
  return QueueProcessor(ref.watch(databaseProvider));
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
