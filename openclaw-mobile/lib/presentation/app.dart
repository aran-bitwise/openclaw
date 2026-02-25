import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/status_mapper.dart';
import '../domain/models.dart';
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

class _ChatWorkbenchScreenState extends ConsumerState<ChatWorkbenchScreen> with WidgetsBindingObserver {
  final _uuid = const Uuid();
  final _composer = TextEditingController();
  Timer? _refreshTimer;
  Timer? _schedulerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>(() async {
      final db = ref.read(databaseProvider);
      await db.init();
      await db.upsertAgent(
        AgentProfile(id: 'default-agent', name: 'Default Agent', createdAt: DateTime.now().millisecondsSinceEpoch),
      );
      ref.read(selectedAgentIdProvider.notifier).state = 'default-agent';
      await ref.read(hookServiceProvider).emitStartupHookOnce(ref.read(clockProvider).now().millisecondsSinceEpoch.toString());
      await _runSchedulersTick();
      _refreshViews();
    });

    _refreshTimer = Timer.periodic(const Duration(milliseconds: 600), (_) => _refreshViews());

    // Best-effort scheduler until native Android WorkManager / iOS BGTask hooks land.
    _schedulerTimer = Timer.periodic(const Duration(minutes: 1), (_) => _runSchedulersTick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runSchedulersTick();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _schedulerTimer?.cancel();
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
        title: const Text('OpenClaw Chat (Milestone 8)'),
        actions: [
          IconButton(
            tooltip: 'Process now',
            onPressed: () async {
              await ref.read(queueProcessorProvider).tick();
              _refreshViews();
            },
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'Run heartbeat now',
            onPressed: _runSchedulersTick,
            icon: const Icon(Icons.favorite),
          ),
          IconButton(
            tooltip: 'Run cron check now',
            onPressed: _runSchedulersTick,
            icon: const Icon(Icons.schedule),
          ),
          IconButton(
            tooltip: 'Reset hook',
            onPressed: () async {
              final sid = ref.read(selectedSessionIdProvider);
              if (sid == null) return;
              final session = await ref.read(databaseProvider).getSessionById(sid);
              if (session == null) return;
              await ref.read(hookServiceProvider).emitManualHook(session: session, type: HookType.reset);
              _refreshViews();
            },
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: 'Memory flush hook',
            onPressed: () async {
              final sid = ref.read(selectedSessionIdProvider);
              if (sid == null) return;
              final session = await ref.read(databaseProvider).getSessionById(sid);
              if (session == null) return;
              await ref.read(hookServiceProvider).emitManualHook(session: session, type: HookType.memoryFlush);
              _refreshViews();
            },
            icon: const Icon(Icons.cleaning_services),
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
                      items: agents.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
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
                    _refreshViews();
                  },
                  child: const Text('Add agent'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _HeartbeatConfigCard(agentId: selectedAgent),
            const SizedBox(height: 8),
            _CronSchedulesCard(agentId: selectedAgent, selectedSessionId: selectedSession),
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
                          ref.read(selectedSessionIdProvider.notifier).state = sessionId;
                          _refreshViews();
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
                                    if (item.event.type == EventType.internalHook)
                                      Text(
                                        'Triggered by ${item.event.payload['parentEventId'] ?? 'n/a'} (root ${item.event.payload['rootEventId'] ?? 'n/a'}, depth ${item.event.payload['depth'] ?? '?'})',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        _stateChip(item.state),
                                        Text(_sourceLabel(item.event.type, item.event.payload)),
                                        if (item.state == QueueState.failed || item.state == QueueState.deadLetter)
                                          TextButton(
                                            onPressed: () async {
                                              await ref.read(runtimeProvider).retryEvent(item.event.id);
                                              _refreshViews();
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
                ElevatedButton(onPressed: () => _sendMessage(selectedAgent, selectedSession), child: const Text('Send')),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Process now remains fallback when OS background execution is constrained. Heartbeat + cron schedulers run best-effort via timer/resume/manual checks.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runSchedulersTick() async {
    await ref.read(heartbeatServiceProvider).triggerDueHeartbeats();
    await ref.read(cronServiceProvider).triggerDueSchedules();
    _refreshViews();
  }

  void _refreshViews() {
    if (!mounted) return;
    ref.invalidate(timelineProvider);
    ref.invalidate(queueViewProvider);
    ref.invalidate(sessionsByAgentProvider);
    ref.invalidate(agentsProvider);
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
    _refreshViews();
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

  String _sourceLabel(EventType type, Map<String, dynamic> payload) {
    switch (type) {
      case EventType.humanMessage:
        return 'human';
      case EventType.heartbeat:
        return 'heartbeat';
      case EventType.cron:
        return 'cron';
      case EventType.internalHook:
        final hook = payload['hookType']?.toString() ?? 'internal';
        switch (hook) {
          case 'startup':
            return 'Startup Hook';
          case 'turnStart':
            return 'Turn Start Hook';
          case 'turnEnd':
            return 'Turn End Hook';
          case 'reset':
            return 'Reset Hook';
          case 'memoryFlush':
            return 'Memory Flush Hook';
          default:
            return 'Internal Hook';
        }
      default:
        return type.name;
    }
  }
}

class _HeartbeatConfigCard extends ConsumerWidget {
  const _HeartbeatConfigCard({required this.agentId});

  final String? agentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (agentId == null) return const SizedBox.shrink();

    return FutureBuilder<AgentProfile?>(
      future: ref.read(databaseProvider).getAgent(agentId!),
      builder: (context, snapshot) {
        final agent = snapshot.data;
        if (agent == null) return const SizedBox.shrink();
        final hb = agent.heartbeat;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Heartbeat settings', style: TextStyle(fontWeight: FontWeight.bold)),
                SwitchListTile(
                  title: const Text('Enabled'),
                  value: hb.enabled,
                  onChanged: (value) => _update(ref, agent, hb.copyWith(enabled: value)),
                ),
                Row(
                  children: [
                    const Text('Interval (min): '),
                    DropdownButton<int>(
                      value: hb.intervalMinutes,
                      items: const [5, 10, 15, 30, 60]
                          .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) _update(ref, agent, hb.copyWith(intervalMinutes: value));
                      },
                    ),
                    const SizedBox(width: 16),
                    Text('Active ${_formatMinutes(hb.activeHours.startMinuteOfDay)}-${_formatMinutes(hb.activeHours.endMinuteOfDay)}'),
                  ],
                ),
                TextFormField(
                  initialValue: hb.promptTemplate,
                  decoration: const InputDecoration(labelText: 'Prompt template'),
                  onFieldSubmitted: (value) => _update(ref, agent, hb.copyWith(promptTemplate: value.trim())),
                ),
                if (hb.suppressedUntil != null)
                  Text(
                    'Suppressed until: ${DateTime.fromMillisecondsSinceEpoch(hb.suppressedUntil!).toLocal()}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _update(WidgetRef ref, AgentProfile agent, HeartbeatSettings settings) async {
    final bounded = settings.copyWith(intervalMinutes: settings.intervalMinutes.clamp(5, 240).toInt());
    await ref.read(runtimeProvider).updateHeartbeatSettings(agent.id, bounded);
    ref.invalidate(agentsProvider);
  }

  String _formatMinutes(int value) {
    final hour = (value ~/ 60).toString().padLeft(2, '0');
    final minute = (value % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _CronSchedulesCard extends ConsumerWidget {
  const _CronSchedulesCard({required this.agentId, required this.selectedSessionId});

  final String? agentId;
  final String? selectedSessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (agentId == null) return const SizedBox.shrink();

    return FutureBuilder<List<CronSchedule>>(
      future: ref.read(databaseProvider).listCronSchedulesByAgent(agentId!),
      builder: (context, snapshot) {
        final schedules = snapshot.data ?? [];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Cron schedules', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Create schedule',
                      onPressed: selectedSessionId == null
                          ? null
                          : () async {
                              await ref.read(cronServiceProvider).createDefaultSchedule(
                                agentId: agentId!,
                                sessionId: selectedSessionId!,
                                channelId: 'mobile-chat',
                              );
                              ref.invalidate(agentsProvider);
                            },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                for (final schedule in schedules)
                  ListTile(
                    dense: true,
                    title: Text(_title(schedule)),
                    subtitle: Text('${schedule.missedRunPolicy.name} • next: ${_next(schedule)}'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        Switch(
                          value: schedule.enabled,
                          onChanged: (value) async {
                            await ref.read(databaseProvider).upsertCronSchedule(schedule.copyWith(enabled: value));
                            ref.invalidate(agentsProvider);
                          },
                        ),
                        IconButton(
                          tooltip: 'Run now',
                          onPressed: () => ref.read(cronServiceProvider).runScheduleNow(schedule.scheduleId),
                          icon: const Icon(Icons.play_circle),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: () async {
                            await ref.read(databaseProvider).deleteCronSchedule(schedule.scheduleId);
                            ref.invalidate(agentsProvider);
                          },
                          icon: const Icon(Icons.delete),
                        ),
                      ],
                    ),
                  ),
                if (schedules.isEmpty)
                  const Text('No schedules yet. Select a session and add one to test daily/weekly/custom cron flows.'),
              ],
            ),
          ),
        );
      },
    );
  }

  String _title(CronSchedule schedule) {
    switch (schedule.rule.type) {
      case CronScheduleType.daily:
        return 'Daily @ ${_formatMinute(schedule.rule.timeOfDayMinute ?? 0)}';
      case CronScheduleType.weekly:
        return 'Weekly d${schedule.rule.weekday ?? 1} @ ${_formatMinute(schedule.rule.timeOfDayMinute ?? 0)}';
      case CronScheduleType.custom:
        return 'Custom every ${schedule.rule.everyNMinutes ?? 60}m';
    }
  }

  String _next(CronSchedule schedule) {
    if (schedule.nextRunAt == null) return 'n/a';
    return DateTime.fromMillisecondsSinceEpoch(schedule.nextRunAt!).toLocal().toString();
  }

  String _formatMinute(int value) {
    final hour = (value ~/ 60).toString().padLeft(2, '0');
    final minute = (value % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
