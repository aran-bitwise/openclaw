import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/gateway_router.dart';
import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'providers.dart';

class OpenClawMobileApp extends ConsumerWidget {
  const OpenClawMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'OpenClaw Mobile',
      home: const WorkbenchScreen(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}

class WorkbenchScreen extends ConsumerStatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  ConsumerState<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends ConsumerState<WorkbenchScreen> {
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      final db = ref.read(databaseProvider);
      await db.init();
      await db.upsertAgent(
        AgentProfile(id: 'default-agent', name: 'Default Agent', createdAt: DateTime.now().millisecondsSinceEpoch),
      );
      ref.invalidate(agentsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsProvider);
    final queueAsync = ref.watch(queueViewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('OpenClaw Mobile M1-M4')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final db = ref.read(databaseProvider);
                    await db.upsertSession(
                      Session(
                        id: 'session-${_uuid.v4()}',
                        agentId: 'default-agent',
                        channelId: 'mobile-chat',
                        createdAt: DateTime.now().millisecondsSinceEpoch,
                      ),
                    );
                    ref.invalidate(sessionsProvider);
                  },
                  child: const Text('Create session'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final sessions = await ref.read(sessionsProvider.future);
                    if (sessions.isEmpty) return;
                    await ref.read(runtimeProvider).ingestEnvelope(
                      InboundEnvelope(
                        channelId: sessions.first.channelId,
                        agentId: sessions.first.agentId,
                        sessionId: sessions.first.id,
                        eventType: EventType.message,
                        idempotencyKey: 'msg-${_uuid.v4()}',
                        payload: {'text': 'hello from debug'},
                      ),
                    );
                    ref.invalidate(queueViewProvider);
                    ref.invalidate(sessionEventsProvider(sessions.first.id));
                  },
                  child: const Text('Inject event'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await ref.read(queueProcessorProvider).tick();
                    ref.invalidate(queueViewProvider);
                    final sessions = await ref.read(sessionsProvider.future);
                    for (final s in sessions) {
                      ref.invalidate(sessionEventsProvider(s.id));
                    }
                  },
                  child: const Text('Process next'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Sessions', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: sessionsAsync.when(
                data: (sessions) => ListView(
                  children: sessions
                      .map(
                        (s) => ExpansionTile(
                          title: Text('${s.id} (${s.channelId})'),
                          children: [
                            Consumer(
                              builder: (context, ref, _) {
                                final eventsAsync = ref.watch(sessionEventsProvider(s.id));
                                return eventsAsync.when(
                                  data: (events) => Column(
                                    children: events
                                        .map((e) => ListTile(title: Text(e.type.name), subtitle: Text(e.payload.toString())))
                                        .toList(),
                                  ),
                                  loading: () => const LinearProgressIndicator(),
                                  error: (err, _) => Text('error: $err'),
                                );
                              },
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (err, _) => Text('error: $err'),
              ),
            ),
            const Divider(),
            const Text('Queue inspector', style: TextStyle(fontWeight: FontWeight.bold)),
            queueAsync.when(
              data: (rows) => Text(rows.map((e) => e.toString()).join('\n')),
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('error: $err'),
            ),
          ],
        ),
      ),
    );
  }
}
