import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/status_mapper.dart';
import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'providers.dart';

class OpenClawMobileApp extends ConsumerWidget {
  const OpenClawMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'OpenClaw Mobile',
      home: const ChatWorkbenchScreen(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}

class ChatWorkbenchScreen extends ConsumerStatefulWidget {
  const ChatWorkbenchScreen({super.key});

  @override
  ConsumerState<ChatWorkbenchScreen> createState() => _ChatWorkbenchScreenState();
}

class _ChatWorkbenchScreenState extends ConsumerState<ChatWorkbenchScreen> {
  final _uuid = const Uuid();
  final _composer = TextEditingController();
  Timer? _refreshTimer;

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
      ref.read(selectedAgentIdProvider.notifier).state = 'default-agent';
    });

    _refreshTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!mounted) return;
      ref.invalidate(timelineProvider);
      ref.invalidate(queueViewProvider);
      ref.invalidate(sessionsByAgentProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agentsAsync = ref.watch(agentsProvider);
    final sessionsAsync = ref.watch(sessionsByAgentProvider);
    final timelineAsync = ref.watch(timelineProvider);
    final selectedAgent = ref.watch(selectedAgentIdProvider);
    final selectedSession = ref.watch(selectedSessionIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenClaw Chat (Milestone 5)'),
        actions: [
          IconButton(
            tooltip: 'Process now',
            onPressed: () async {
              await ref.read(queueProcessorProvider).tick();
              ref.invalidate(timelineProvider);
              ref.invalidate(queueViewProvider);
            },
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: agentsAsync.when(
                    data: (agents) => DropdownButtonFormField<String>(
                      value: selectedAgent,
                      decoration: const InputDecoration(labelText: 'Agent'),
                      items: agents
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (value) {
                        ref.read(selectedAgentIdProvider.notifier).state = value;
                        ref.read(selectedSessionIdProvider.notifier).state = null;
                        ref.invalidate(sessionsByAgentProvider);
                      },
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (err, _) => Text('error: $err'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final db = ref.read(databaseProvider);
                    final id = 'agent-${_uuid.v4()}';
                    await db.upsertAgent(
                      AgentProfile(id: id, name: 'Agent ${id.substring(0, 6)}', createdAt: DateTime.now().millisecondsSinceEpoch),
                    );
                    ref.invalidate(agentsProvider);
                  },
                  child: const Text('Add agent'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: sessionsAsync.when(
                    data: (sessions) => DropdownButtonFormField<String>(
                      value: selectedSession,
                      decoration: const InputDecoration(labelText: 'Session'),
                      items: sessions
                          .map((s) => DropdownMenuItem(value: s.id, child: Text('${s.id.substring(0, 8)} (${s.channelId})')))
                          .toList(),
                      onChanged: (value) => ref.read(selectedSessionIdProvider.notifier).state = value,
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (err, _) => Text('error: $err'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: selectedAgent == null
                      ? null
                      : () async {
                          final db = ref.read(databaseProvider);
                          final sessionId = 'session-${_uuid.v4()}';
                          await db.upsertSession(
                            Session(
                              id: sessionId,
                              agentId: selectedAgent,
                              channelId: 'mobile-chat',
                              createdAt: DateTime.now().millisecondsSinceEpoch,
                            ),
                          );
                          ref.invalidate(sessionsByAgentProvider);
                          ref.read(selectedSessionIdProvider.notifier).state = sessionId;
                        },
                  child: const Text('New session'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: timelineAsync.when(
                    data: (timeline) {
                      if (timeline.isEmpty) return const Text('No messages yet');
                      return ListView.builder(
                        itemCount: timeline.length,
                        itemBuilder: (context, index) {
                          final item = timeline[index];
                          final text = item.event.payload['text']?.toString() ?? item.event.payload.toString();
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(text),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        _stateChip(item.state),
                                        Text(item.event.type.name),
                                        if (item.state == QueueState.failed || item.state == QueueState.deadLetter)
                                          TextButton(
                                            onPressed: () async {
                                              await ref.read(runtimeProvider).retryEvent(item.event.id);
                                              ref.invalidate(timelineProvider);
                                              ref.invalidate(queueViewProvider);
                                            },
                                            child: const Text('Retry'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (err, _) => Text('error: $err'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    decoration: const InputDecoration(labelText: 'Message composer'),
                    onSubmitted: (_) => _sendMessage(selectedAgent, selectedSession),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _sendMessage(selectedAgent, selectedSession),
                  child: const Text('Send'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Process now is temporary for Milestone 5 due to no background worker loop yet; it will be replaced by scheduled/background processing in later milestones.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage(String? selectedAgent, String? selectedSession) async {
    if (selectedAgent == null || selectedSession == null || _composer.text.trim().isEmpty) return;
    final text = _composer.text.trim();
    _composer.clear();
    await ref.read(runtimeProvider).sendHumanMessage(
          agentId: selectedAgent,
          sessionId: selectedSession,
          channelId: 'mobile-chat',
          text: text,
        );
    ref.invalidate(timelineProvider);
    ref.invalidate(queueViewProvider);
  }

  Widget _stateChip(QueueState state) {
    Color color;
    switch (state) {
      case QueueState.queued:
        color = Colors.blue;
      case QueueState.processing:
        color = Colors.orange;
      case QueueState.completed:
        color = Colors.green;
      case QueueState.failed:
        color = Colors.red;
      case QueueState.deadLetter:
        color = Colors.purple;
    }
    return Chip(label: Text(queueStateLabel(state)), backgroundColor: color.withOpacity(0.2));
  }
}
