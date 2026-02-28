import 'dart:async';
import 'dart:convert';

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
        title: const Text('OpenClaw Chat (Milestone 11)'),
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
            tooltip: 'Sync relay now',
            onPressed: () async {
              await ref.read(relayIngestServiceProvider).syncPendingRelayEvents();
              _refreshViews();
            },
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Compact memory now',
            onPressed: () async {
              final selectedAgent = ref.read(selectedAgentIdProvider);
              final selectedSession = ref.read(selectedSessionIdProvider);
              final memory = ref.read(memoryServiceProvider);
              await memory.compactGlobalMemory();
              if (selectedAgent != null) {
                await memory.compactAgentMemory(selectedAgent);
              }
              if (selectedSession != null) {
                await memory.compactSessionMemory(selectedSession);
              }
              _refreshViews();
            },
            icon: const Icon(Icons.compress),
          ),
          IconButton(
            tooltip: 'Run Research -> Writer demo',
            onPressed: () async {
              final source = ref.read(selectedAgentIdProvider);
              final sessionId = ref.read(selectedSessionIdProvider);
              if (source == null || sessionId == null) return;
              final agents = await ref.read(databaseProvider).listAgents();
              final target = agents.where((a) => a.id != source).map((a) => a.id).firstOrNull;
              if (target == null) return;
              await ref.read(handoffServiceProvider).runDemoResearchToWriter(
                sourceAgentId: source,
                targetAgentId: target,
                sessionId: sessionId,
                channelId: 'mobile-chat',
                message: 'Research and draft summary',
              );
              await ref.read(queueProcessorProvider).tick();
              _refreshViews();
            },
            icon: const Icon(Icons.forward_to_inbox),
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
            _HandoffConfigCard(agentId: selectedAgent),
            const SizedBox(height: 8),
            _MemoryCard(agentId: selectedAgent, sessionId: selectedSession),
            const SizedBox(height: 8),
            _ToolingCard(agentId: selectedAgent, sessionId: selectedSession),
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
            const _TimelineFilters(),
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

                                    if (item.event.type == EventType.agentHandoff)
                                      Text(
                                        'Trace ${item.event.payload['handoffTraceId'] ?? 'n/a'} • from ${item.event.payload['fromAgentId'] ?? '?'} to ${item.event.payload['toAgentId'] ?? '?'} • decision ${item.event.payload['decision']?['allowed'] == true ? 'allowed' : 'denied'}',
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
                                        TextButton(
                                          onPressed: () => _openInspector(item.event.id),
                                          child: const Text('Inspect'),
                                        ),
                                      ],
                                    ),
                                    FutureBuilder<Map<String, List<MemoryEntry>>>(
                                      future: ref.read(databaseProvider).listMemoryAccessByEvent(item.event.id),
                                      builder: (context, snapshot) {
                                        final reads = snapshot.data?['read']?.length ?? 0;
                                        final writes = snapshot.data?['write']?.length ?? 0;
                                        if (reads == 0 && writes == 0) return const SizedBox.shrink();
                                        return Text(
                                          'Memory reads: $reads • writes: $writes',
                                          style: const TextStyle(fontSize: 11),
                                        );
                                      },
                                    ),
                                    FutureBuilder<List<ToolAuditRecord>>(
                                      future: ref.read(databaseProvider).listToolAuditLogs(sessionId: item.event.sessionId, limit: 20),
                                      builder: (context, snapshot) {
                                        final match = snapshot.data
                                                ?.where((a) => a.eventId == item.event.id)
                                                .toList() ??
                                            const <ToolAuditRecord>[];
                                        if (match.isEmpty) return const SizedBox.shrink();
                                        final latest = match.first;
                                        return Text(
                                          'Tool ${latest.toolId}: ${latest.decisionAllowed ? 'allowed' : 'blocked'} (${latest.decisionReason})',
                                          style: const TextStyle(fontSize: 11),
                                        );
                                      },
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
              'Process now remains fallback when OS background execution is constrained. Heartbeat + cron + relay sync + handoff orchestration run best-effort via timer/resume/manual checks.',
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
    await ref.read(relayIngestServiceProvider).syncPendingRelayEvents();
    _refreshViews();
  }

  void _refreshViews() {
    if (!mounted) return;

    if (toolId == 'tool.cameraSnapshot' && logs.isNotEmpty) {
      try {
        final parsed = jsonDecode(logs.first.outputRedacted);
        if (parsed is Map<String, dynamic>) {
          final checksum = parsed['checksum']?.toString() ?? '';
          final preview = checksum.length > 8 ? checksum.substring(0, 8) : checksum;
          setState(() {
            _lastSnapshotSummary =
                'Snapshot: url=${parsed['snapshotUrl'] ?? '-'} capturedAt=${parsed['capturedAt'] ?? '-'} checksum=$preview';
          });
        }
      } catch (_) {}
    }

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

  Future<void> _openInspector(String eventId) async {
    final inspector = ref.read(inspectorServiceProvider);
    final data = await inspector.inspectEvent(eventId);
    if (!mounted || data == null) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Event inspector: ${data.event.id.substring(0, 8)}'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Source: ${data.sourceLabel}'),
                Text('Agent: ${data.session.agentId}'),
                Text('Session: ${data.session.id}'),
                Text('Channel: ${data.session.channelId}'),
                Text('Idempotency: ${data.event.idempotencyKey}'),
                const SizedBox(height: 8),
                const Text('Queue/Lifecycle', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('State: ${data.queueItem?.state.name ?? 'n/a'}'),
                Text('Attempt count: ${data.queueItem?.attemptCount ?? 0} / ${data.queueItem?.maxAttempts ?? 0}'),
                Text('Queued at: ${_fmtTs(data.queueItem?.createdAt)}'),
                Text('Started at: ${_fmtTs(data.queueItem?.state == QueueState.processing ? data.queueItem?.updatedAt : null)}'),
                Text('Completed at: ${_fmtTs(data.runResults.isNotEmpty ? data.runResults.last.completedAt : null)}'),
                Text('Failed/Dead-letter at: ${_fmtTs((data.queueItem?.state == QueueState.failed || data.queueItem?.state == QueueState.deadLetter) ? data.queueItem?.updatedAt : null)}'),
                Text('Next attempt: ${_fmtTs(data.queueItem?.nextAttemptAt)}'),
                const SizedBox(height: 8),
                const Text('Why did this happen?', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(data.explanation),
                if (data.ancestryChain.isEmpty)
                  const Text('No ancestry metadata recorded')
                else
                  Text(data.ancestryChain.map((e) => e.id.substring(0, 8)).join(' -> ')),
                const SizedBox(height: 8),
                const Text('Execution trace', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final step in data.traceSteps) Text('• $step'),
                const SizedBox(height: 8),
                const Text('Run results', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final run in data.runResults) Text('${_fmtTs(run.completedAt)}: ${run.output}'),
                const SizedBox(height: 8),
                const Text('Memory reads', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final m in data.memoryReads)
                  Text('[${m.scope.name}] ${m.content} (source event ${m.sourceEventId ?? 'n/a'})'),
                const SizedBox(height: 8),
                const Text('Memory writes', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final m in data.memoryWrites)
                  Text('[${m.scope.name}] ${m.content} (source run ${m.sourceRunId ?? 'n/a'})'),
                const SizedBox(height: 8),
                const Text('Tool policy decisions', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final t in data.toolAudits)
                  Text('${t.toolId}: ${t.decisionAllowed ? 'allowed' : 'blocked'} (${t.decisionReason}), consent=${t.consentOutcome}, audit=${t.id.substring(0, 8)}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              final path = await inspector.exportDiagnosticsForEvent(eventId);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Diagnostics exported to $path')));
            },
            child: const Text('Export diagnostics'),
          ),
        ],
      ),
    );
  }

  String _fmtTs(int? millis) {
    if (millis == null || millis <= 0) return 'n/a';
    return DateTime.fromMillisecondsSinceEpoch(millis).toLocal().toIso8601String();
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
        return payload['workflow']?.toString() == 'safety_check' ? 'Safety Check Run' : 'cron';
      case EventType.webhook:
        final provider = payload['provider']?.toString() ?? 'webhook';
        return 'Webhook ($provider)';
      case EventType.agentHandoff:
        return payload['handoffReason']?.toString() == 'handoff_result' ? 'Handoff Result' : 'Agent Handoff';
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

class _TimelineFilters extends ConsumerWidget {
  const _TimelineFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeFilter = ref.watch(timelineEventTypeFilterProvider);
    final stateFilter = ref.watch(timelineStateFilterProvider);
    final traceFilter = ref.watch(timelineTraceFilterProvider);
    final descending = ref.watch(timelineSortDescendingProvider);
    final onlySession = ref.watch(timelineShowOnlySessionProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<EventType?>(
                value: typeFilter,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  const DropdownMenuItem<EventType?>(value: null, child: Text('All')),
                  ...EventType.values.map((e) => DropdownMenuItem<EventType?>(value: e, child: Text(e.name))),
                ],
                onChanged: (value) => ref.read(timelineEventTypeFilterProvider.notifier).state = value,
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<QueueState?>(
                value: stateFilter,
                decoration: const InputDecoration(labelText: 'Queue state'),
                items: [
                  const DropdownMenuItem<QueueState?>(value: null, child: Text('All')),
                  ...QueueState.values.map((e) => DropdownMenuItem<QueueState?>(value: e, child: Text(e.name))),
                ],
                onChanged: (value) => ref.read(timelineStateFilterProvider.notifier).state = value,
              ),
            ),
            SizedBox(
              width: 190,
              child: TextFormField(
                initialValue: traceFilter,
                decoration: const InputDecoration(labelText: 'Trace ID contains'),
                onChanged: (value) => ref.read(timelineTraceFilterProvider.notifier).state = value,
              ),
            ),
            FilterChip(
              selected: descending,
              label: const Text('Newest first'),
              onSelected: (value) => ref.read(timelineSortDescendingProvider.notifier).state = value,
            ),
            FilterChip(
              selected: onlySession,
              label: const Text('Show only this session'),
              onSelected: (value) => ref.read(timelineShowOnlySessionProvider.notifier).state = value,
            ),
          ],
        ),
      ),
    );
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

class _MemoryCard extends ConsumerWidget {
  const _MemoryCard({required this.agentId, required this.sessionId});

  final String? agentId;
  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Memory', style: TextStyle(fontWeight: FontWeight.bold)),
            _scopeSection(
              context,
              ref,
              title: 'Global preferences',
              scope: MemoryScope.global,
              scopeId: null,
            ),
            if (agentId != null)
              _scopeSection(
                context,
                ref,
                title: 'Agent memory',
                scope: MemoryScope.agent,
                scopeId: agentId,
              ),
            if (sessionId != null)
              _scopeSection(
                context,
                ref,
                title: 'Session memory',
                scope: MemoryScope.session,
                scopeId: sessionId,
              ),
          ],
        ),
      ),
    );
  }

  Widget _scopeSection(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required MemoryScope scope,
    required String? scopeId,
  }) {
    return FutureBuilder<List<MemoryEntry>>(
      future: ref.read(databaseProvider).listMemoryByScope(scope, scopeId: scopeId),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Add memory',
                  onPressed: () => _editEntry(context, ref, scope: scope, scopeId: scopeId),
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: 'Clear scope',
                  onPressed: () => _confirmClear(context, ref, scope: scope, scopeId: scopeId),
                  icon: const Icon(Icons.delete_sweep),
                ),
              ],
            ),
            for (final entry in entries.take(4))
              ListTile(
                dense: true,
                title: Text(entry.content, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  'src event=${entry.sourceEventId ?? 'n/a'} run=${entry.sourceRunId ?? 'n/a'} trace=${entry.sourceHandoffTraceId ?? 'n/a'}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: entry.pinned ? 'Unpin' : 'Pin',
                      onPressed: () async {
                        final now = ref.read(clockProvider).now().millisecondsSinceEpoch;
                        await ref
                            .read(databaseProvider)
                            .updateMemoryEntry(entry.copyWith(pinned: !entry.pinned, updatedAt: now));
                        ref.invalidate(agentsProvider);
                      },
                      icon: Icon(entry.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                    ),
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () => _editEntry(context, ref, existing: entry, scope: scope, scopeId: scopeId),
                      icon: const Icon(Icons.edit),
                    ),
                  ],
                ),
              ),
            if (entries.isEmpty) const Text('No memory entries.'),
          ],
        );
      },
    );
  }

  Future<void> _editEntry(
    BuildContext context,
    WidgetRef ref, {
    MemoryEntry? existing,
    required MemoryScope scope,
    required String? scopeId,
  }) async {
    final controller = TextEditingController(text: existing?.content ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add memory' : 'Edit memory'),
        content: TextField(controller: controller, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || controller.text.trim().isEmpty) return;
    final now = ref.read(clockProvider).now().millisecondsSinceEpoch;
    final db = ref.read(databaseProvider);
    await db.upsertMemoryEntry(
      existing?.copyWith(content: controller.text.trim(), updatedAt: now, lastAccessedAt: now) ??
          MemoryEntry(
            id: const Uuid().v4(),
            scope: scope,
            scopeId: scopeId,
            content: controller.text.trim(),
            createdAt: now,
            updatedAt: now,
            lastAccessedAt: now,
            importance: 2,
          ),
    );
    ref.invalidate(agentsProvider);
  }

  Future<void> _confirmClear(
    BuildContext context,
    WidgetRef ref, {
    required MemoryScope scope,
    required String? scopeId,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear memory scope?'),
        content: const Text('This removes memory entries in this scope.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(databaseProvider).clearMemoryByScope(scope, scopeId: scopeId);
    ref.invalidate(agentsProvider);
  }
}



class _ToolingCard extends ConsumerWidget {
  const _ToolingCard({required this.agentId, required this.sessionId});

  final String? agentId;
  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.read(toolRegistryProvider).listTools();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tools and capability sandbox', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
              'Default deny. Medium/high risk tools require runtime consent. openUrl remains blocked in mobile sandbox.',
              style: TextStyle(fontSize: 12),
            ),
            for (final tool in tools)
              FutureBuilder<bool>(
                future: agentId == null
                    ? Future.value(false)
                    : ref.read(databaseProvider).getToolPermission(agentId: agentId!, toolId: tool.toolId),
                builder: (context, snapshot) {
                  final granted = snapshot.data ?? false;
                  return ListTile(
                    dense: true,
                    title: Text('${tool.toolId} (${tool.riskLevel.name})'),
                    subtitle: Text('${tool.capabilityCategory} • perms: ${tool.requiredPermissions.join(', ')}'),
                    trailing: agentId == null
                        ? const SizedBox.shrink()
                        : Switch(
                            value: granted,
                            onChanged: (value) async {
                              await ref.read(toolingServiceProvider).setPermission(
                                    agentId: agentId!,
                                    toolId: tool.toolId,
                                    granted: value,
                                  );
                              ref.invalidate(agentsProvider);
                            },
                          ),
                  );
                },
              ),
            const SizedBox(height: 8),
            _CameraGatewaySettingsCard(agentId: agentId, sessionId: sessionId),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: (agentId == null || sessionId == null)
                      ? null
                      : () => _runToolDemo(
                            context,
                            ref,
                            toolId: 'tool.echo',
                            input: {'message': 'hello from tool.echo'},
                            consentNeeded: false,
                          ),
                  child: const Text('Run echo tool'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (agentId == null || sessionId == null)
                      ? null
                      : () => _runToolDemo(
                            context,
                            ref,
                            toolId: 'tool.httpGet',
                            input: {'url': 'https://example.com'},
                            consentNeeded: true,
                          ),
                  child: const Text('Run httpGet tool'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (agentId == null || sessionId == null)
                      ? null
                      : () => _runToolDemo(
                            context,
                            ref,
                            toolId: 'tool.openUrl',
                            input: {'url': 'https://example.com'},
                            consentNeeded: true,
                          ),
                  child: const Text('Run openUrl tool'),
                ),
              ],
            ),
            FutureBuilder<List<ToolAuditRecord>>(
              future: ref.read(databaseProvider).listToolAuditLogs(sessionId: sessionId, limit: 10),
              builder: (context, snapshot) {
                final logs = snapshot.data ?? [];
                if (logs.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('Recent tool audit logs', style: TextStyle(fontWeight: FontWeight.w600)),
                    for (final log in logs.take(5))
                      Text(
                        '${log.toolId} • ${log.decisionAllowed ? 'allowed' : 'blocked'} • ${log.decisionReason} • consent=${log.consentOutcome}',
                        style: const TextStyle(fontSize: 11),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runToolDemo(
    BuildContext context,
    WidgetRef ref, {
    required String toolId,
    required Map<String, dynamic> input,
    required bool consentNeeded,
  }) async {
    final agent = ref.read(selectedAgentIdProvider);
    final session = ref.read(selectedSessionIdProvider);
    if (agent == null || session == null) return;

    var consentApproved = false;
    if (consentNeeded) {
      final decision = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tool consent required'),
          content: Text('Approve running $toolId?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Deny')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
          ],
        ),
      );
      consentApproved = decision == true;
    }

    await ref.read(runtimeProvider).sendHumanMessage(
      agentId: agent,
      sessionId: session,
      channelId: 'mobile-chat',
      text: 'Invoke $toolId',
      extraPayload: {
        'toolRequest': {'toolId': toolId, 'input': input, 'idempotencyKey': '$toolId-demo'},
        'toolConsentApproved': consentApproved,
      },
    );
    await ref.read(queueProcessorProvider).tick();

    if (toolId == 'tool.cameraSnapshot' && logs.isNotEmpty) {
      try {
        final parsed = jsonDecode(logs.first.outputRedacted);
        if (parsed is Map<String, dynamic>) {
          final checksum = parsed['checksum']?.toString() ?? '';
          final preview = checksum.length > 8 ? checksum.substring(0, 8) : checksum;
          setState(() {
            _lastSnapshotSummary =
                'Snapshot: url=${parsed['snapshotUrl'] ?? '-'} capturedAt=${parsed['capturedAt'] ?? '-'} checksum=$preview';
          });
        }
      } catch (_) {}
    }

    ref.invalidate(timelineProvider);
    ref.invalidate(agentsProvider);
    ref.invalidate(configuredCamerasProvider);
  }
}

class _CameraGatewaySettingsCard extends ConsumerStatefulWidget {
  const _CameraGatewaySettingsCard({required this.agentId, required this.sessionId});

  final String? agentId;
  final String? sessionId;

  @override
  ConsumerState<_CameraGatewaySettingsCard> createState() => _CameraGatewaySettingsCardState();
}

class _CameraGatewaySettingsCardState extends ConsumerState<_CameraGatewaySettingsCard> {
  final _baseUrlController = TextEditingController();
  final _tokenController = TextEditingController();
  String _mode = 'latest';
  String? _lastSnapshotSummary;

  @override
  void dispose() {
    _baseUrlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(cameraGatewaySettingsProvider);
    final configuredAsync = ref.watch(configuredCamerasProvider);

    return settingsAsync.when(
      data: (settings) {
        if (_baseUrlController.text.isEmpty) {
          _baseUrlController.text = settings.baseUrl;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cameras', style: TextStyle(fontWeight: FontWeight.w600)),
            TextField(controller: _baseUrlController, decoration: const InputDecoration(labelText: 'Gateway base URL')),
            const SizedBox(height: 6),
            TextField(
              controller: _tokenController,
              decoration: InputDecoration(
                labelText: settings.tokenSet ? 'Gateway token (saved)' : 'Gateway token',
                hintText: settings.tokenSet ? '••••••••' : 'demo-token',
              ),
              obscureText: true,
            ),
            Row(
              children: [
                Switch(
                  value: settings.enabled,
                  onChanged: (value) async {
                    await ref.read(databaseProvider).saveCameraGatewaySettings(baseUrl: settings.baseUrl, enabled: value);
                    ref.invalidate(cameraGatewaySettingsProvider);
                  },
                ),
                const Text('Enabled'),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final token = _tokenController.text.trim();
                    if (token.isNotEmpty) {
                      await ref.read(secretStoreProvider).saveCameraGatewayToken(token);
                    }
                    await ref
                        .read(databaseProvider)
                        .saveCameraGatewaySettings(baseUrl: _baseUrlController.text.trim(), enabled: settings.enabled, tokenSet: token.isNotEmpty || settings.tokenSet);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Camera gateway settings saved')));
                    }
                    _tokenController.clear();
                    ref.invalidate(cameraGatewaySettingsProvider);
                  },
                  child: const Text('Save settings'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                ElevatedButton(
                  onPressed: (widget.agentId == null || widget.sessionId == null)
                      ? null
                      : () => _runCameraTool(
                            toolId: 'tool.cameraList',
                            input: const {'includeDisabled': false},
                            consentNeeded: false,
                          ),
                  child: const Text('Sync cameras'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (widget.agentId == null || widget.sessionId == null)
                      ? null
                      : () async {
                          await ref.read(cronServiceProvider).createSafetyCheckSchedule(
                                agentId: widget.agentId!,
                                sessionId: widget.sessionId!,
                                channelId: 'mobile-chat',
                              );
                          ref.invalidate(agentsProvider);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Safety check schedule created')));
                          }
                        },
                  child: const Text('Create safety check schedule'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (widget.agentId == null || widget.sessionId == null)
                      ? null
                      : () async {
                          await ref.read(cronServiceProvider).runSafetyCheckNow(
                                agentId: widget.agentId!,
                                sessionId: widget.sessionId!,
                                channelId: 'mobile-chat',
                                modeOverride: _mode,
                              );
                          ref.invalidate(timelineProvider);
                        },
                  child: const Text('Run safety check now'),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _mode,
                  items: const [
                    DropdownMenuItem(value: 'latest', child: Text('latest')),
                    DropdownMenuItem(value: 'test_ok', child: Text('test_ok')),
                    DropdownMenuItem(value: 'test_fall', child: Text('test_fall')),
                    DropdownMenuItem(value: 'test_uncertain', child: Text('test_uncertain')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _mode = value;
                      });
                    }
                  },
                ),
              ],
            ),
            if (_lastSnapshotSummary != null) Text(_lastSnapshotSummary!, style: const TextStyle(fontSize: 12)),
            configuredAsync.when(
              data: (configured) {
                if (configured.isEmpty) {
                  return const Text('No configured cameras yet. Run Sync cameras.', style: TextStyle(fontSize: 12));
                }
                return Column(
                  children: [
                    for (final camera in configured)
                      ListTile(
                        dense: true,
                        title: Text('${camera.name} (${camera.cameraId})'),
                        subtitle: Text('${camera.location} • enabled=${camera.enabled} • lastSeen=${camera.lastSeenAt ?? '-'}'),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            Switch(
                              value: camera.enabled,
                              onChanged: (value) async {
                                await ref.read(databaseProvider).setConfiguredCameraEnabled(cameraId: camera.cameraId, enabled: value);
                                ref.invalidate(configuredCamerasProvider);
                              },
                            ),
                            TextButton(
                              onPressed: (widget.agentId == null || widget.sessionId == null)
                                  ? null
                                  : () => _runCameraTool(
                                        toolId: 'tool.cameraSnapshot',
                                        input: {'cameraId': camera.cameraId, 'mode': _mode},
                                        consentNeeded: true,
                                      ),
                              child: const Text('Test snapshot'),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              onPressed: () async {
                                await ref.read(databaseProvider).deleteConfiguredCamera(camera.cameraId);
                                ref.invalidate(configuredCamerasProvider);
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
              error: (error, _) => Text('Camera list error: $error'),
            ),
          ],
        );
      },
      loading: () => const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
      error: (error, _) => Text('Camera settings error: $error'),
    );
  }

  Future<void> _runCameraTool({required String toolId, required Map<String, dynamic> input, required bool consentNeeded}) async {
    final agent = ref.read(selectedAgentIdProvider);
    final session = ref.read(selectedSessionIdProvider);
    if (agent == null || session == null) return;

    var consentApproved = false;
    if (consentNeeded) {
      final decision = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tool consent required'),
          content: Text('Approve running $toolId?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Deny')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
          ],
        ),
      );
      consentApproved = decision == true;
    }

    await ref.read(runtimeProvider).sendHumanMessage(
      agentId: agent,
      sessionId: session,
      channelId: 'mobile-chat',
      text: 'Invoke $toolId',
      extraPayload: {
        'toolRequest': {'toolId': toolId, 'input': input, 'idempotencyKey': '$toolId-${DateTime.now().millisecondsSinceEpoch}'},
        'toolConsentApproved': consentApproved,
      },
    );
    await ref.read(queueProcessorProvider).tick();

    final logs = await ref.read(databaseProvider).listToolAuditLogs(sessionId: session, limit: 1);
    if (toolId == 'tool.cameraList' && logs.isNotEmpty && logs.first.decisionAllowed) {
      final output = logs.first.outputRedacted;
      final parsed = jsonDecode(output.replaceAll('https://[redacted-url]', '"redacted-url"').replaceAll('…', ''));
      if (parsed is Map && parsed['cameras'] is List) {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final item in parsed['cameras']) {
          final cam = Map<String, dynamic>.from(item as Map);
          await ref.read(databaseProvider).upsertConfiguredCamera(
                ConfiguredCamera(
                  cameraId: cam['cameraId']?.toString() ?? '',
                  name: cam['name']?.toString() ?? '',
                  location: cam['location']?.toString() ?? '',
                  enabled: (cam['enabled'] as bool?) ?? true,
                  createdAt: now,
                  updatedAt: now,
                  lastSeenAt: now,
                ),
              );
        }
      }
    }


    if (toolId == 'tool.cameraSnapshot' && logs.isNotEmpty) {
      try {
        final parsed = jsonDecode(logs.first.outputRedacted);
        if (parsed is Map<String, dynamic>) {
          final checksum = parsed['checksum']?.toString() ?? '';
          final preview = checksum.length > 8 ? checksum.substring(0, 8) : checksum;
          setState(() {
            _lastSnapshotSummary =
                'Snapshot: url=${parsed['snapshotUrl'] ?? '-'} capturedAt=${parsed['capturedAt'] ?? '-'} checksum=$preview';
          });
        }
      } catch (_) {}
    }

    ref.invalidate(timelineProvider);
    ref.invalidate(agentsProvider);
    ref.invalidate(configuredCamerasProvider);
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
