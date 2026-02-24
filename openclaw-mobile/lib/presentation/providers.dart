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

final sessionsProvider = FutureProvider<List<Session>>((ref) async {
  final db = ref.watch(databaseProvider);
  await db.init();
  return db.listSessions();
});

final sessionEventsProvider = FutureProvider.family<List<Event>, String>((ref, sessionId) async {
  final db = ref.watch(databaseProvider);
  await db.init();
  return db.listEventsBySession(sessionId);
});

final queueViewProvider = FutureProvider<List<Map<String, Object?>>>((ref) async {
  final db = ref.watch(databaseProvider);
  await db.init();
  return db.listQueueItems();
});
