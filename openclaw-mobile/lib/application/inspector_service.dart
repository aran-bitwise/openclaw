import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'clock.dart';

class InspectorData {
  InspectorData({
    required this.event,
    required this.session,
    required this.queueItem,
    required this.runResults,
    required this.memoryReads,
    required this.memoryWrites,
    required this.toolAudits,
    required this.ancestryChain,
    required this.traceSteps,
    required this.explanation,
    required this.sourceLabel,
  });

  final Event event;
  final Session session;
  final QueueItem? queueItem;
  final List<RunResult> runResults;
  final List<MemoryEntry> memoryReads;
  final List<MemoryEntry> memoryWrites;
  final List<ToolAuditRecord> toolAudits;
  final List<Event> ancestryChain;
  final List<String> traceSteps;
  final String explanation;
  final String sourceLabel;
}

class InspectorService {
  InspectorService(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  Future<InspectorData?> inspectEvent(String eventId) async {
    final event = await _db.getEventById(eventId);
    if (event == null) return null;
    final session = await _db.getSessionById(event.sessionId);
    if (session == null) return null;

    final queue = await _db.getQueueItemByEventId(event.id);
    final runs = await _db.listRunResultsByEvent(event.id);
    final memory = await _db.listMemoryAccessByEvent(event.id);
    final audits = await _db.listToolAuditLogsForEvent(event.id);
    final ancestry = await _buildAncestryChain(event);

    return InspectorData(
      event: event,
      session: session,
      queueItem: queue,
      runResults: runs,
      memoryReads: memory['read'] ?? const [],
      memoryWrites: memory['write'] ?? const [],
      toolAudits: audits,
      ancestryChain: ancestry,
      traceSteps: _buildTraceSteps(event, queue, runs, memory['read'] ?? const [], memory['write'] ?? const [], audits),
      explanation: _buildExplanation(event),
      sourceLabel: _sourceLabel(event),
    );
  }

  Future<List<Event>> _buildAncestryChain(Event event) async {
    final chain = <Event>[];
    final rootId = event.payload['rootEventId']?.toString();
    final parentId = event.payload['parentEventId']?.toString();

    if (rootId != null && rootId.isNotEmpty) {
      final root = await _db.getEventById(rootId);
      if (root != null) chain.add(root);
    }

    final seen = <String>{event.id};
    var cursor = parentId;
    while (cursor != null && cursor.isNotEmpty && !seen.contains(cursor)) {
      seen.add(cursor);
      final parent = await _db.getEventById(cursor);
      if (parent == null) break;
      chain.add(parent);
      cursor = parent.payload['parentEventId']?.toString();
    }

    chain.add(event);
    final deduped = <String>{};
    return chain.where((e) => deduped.add(e.id)).toList();
  }

  String _buildExplanation(Event event) {
    if (event.type == EventType.webhook) {
      return 'Triggered by webhook delivery ${event.payload['relayEventId'] ?? event.id}';
    }
    if (event.type == EventType.internalHook) {
      return 'Created by ${event.payload['hookType'] ?? 'hook'} for event ${event.payload['parentEventId'] ?? 'n/a'}';
    }
    if (event.type == EventType.agentHandoff) {
      return 'Agent ${event.payload['fromAgentId'] ?? '?'} delegated to ${event.payload['toAgentId'] ?? '?'} (trace ${event.payload['handoffTraceId'] ?? 'n/a'})';
    }
    if (event.payload['parentEventId'] != null) {
      return 'Triggered by parent event ${event.payload['parentEventId']}';
    }
    return 'No ancestry metadata recorded';
  }

  String _sourceLabel(Event event) {
    switch (event.type) {
      case EventType.humanMessage:
        return 'Human Message';
      case EventType.heartbeat:
        return 'Heartbeat';
      case EventType.cron:
        return event.payload['workflow']?.toString() == 'safety_check' ? 'Safety Check Run' : 'Cron';
      case EventType.internalHook:
        return 'Internal Hook (${event.payload['hookType'] ?? 'unknown'})';
      case EventType.webhook:
        return 'Webhook (${event.payload['provider'] ?? 'generic'})';
      case EventType.agentHandoff:
        return 'Agent Handoff';
      case EventType.hook:
        return 'Hook';
    }
  }

  List<String> _buildTraceSteps(
    Event event,
    QueueItem? queue,
    List<RunResult> runs,
    List<MemoryEntry> reads,
    List<MemoryEntry> writes,
    List<ToolAuditRecord> audits,
  ) {
    final steps = <String>[
      'ingested at ${DateTime.fromMillisecondsSinceEpoch(event.createdAt).toIso8601String()}',
      if (queue != null) 'queued with state=${queue.state.name}, attempts=${queue.attemptCount}',
      if (queue?.state == QueueState.processing || queue?.state == QueueState.completed || queue?.state == QueueState.failed || queue?.state == QueueState.deadLetter)
        'processing state observed',
      for (final audit in audits)
        'tool ${audit.toolId}: ${audit.decisionAllowed ? 'allowed' : 'blocked'} (${audit.decisionReason})',
      if (reads.isNotEmpty) 'memory read count=${reads.length}',
      if (writes.isNotEmpty) 'memory write count=${writes.length}',
      if (runs.isNotEmpty) 'completed with ${runs.length} run result(s)',
    ];
    return steps;
  }

  Future<String> exportDiagnosticsForEvent(String eventId) async {
    final inspected = await inspectEvent(eventId);
    if (inspected == null) {
      throw StateError('Event $eventId not found');
    }

    final timestamp = _clock.now().millisecondsSinceEpoch;
    final dir = Directory('${Directory.systemTemp.path}/openclaw-diagnostics-$eventId-$timestamp');
    await dir.create(recursive: true);

    final meta = {
      'app': 'openclaw-mobile',
      'buildTimestamp': _clock.now().toIso8601String(),
      'device': 'mobile-device-placeholder',
      'scope': 'single-event',
      'eventId': eventId,
    };

    final handoffTraceId = inspected.event.payload['handoffTraceId']?.toString();
    final handoffTrace = handoffTraceId == null ? null : await _db.getHandoffTrace(handoffTraceId);

    await File('${dir.path}/metadata.json').writeAsString(_json(meta));
    await File('${dir.path}/event.json').writeAsString(_json(_scrub(inspected.event.toJson())));
    await File('${dir.path}/session.json').writeAsString(_json(_scrub(inspected.session.toJson())));
    await File('${dir.path}/queue.json').writeAsString(_json(_scrub(_queueToJson(inspected.queueItem))));
    await File('${dir.path}/run_results.json').writeAsString(_json(inspected.runResults.map((r) => _scrub(r.toJson())).toList()));
    await File('${dir.path}/memory_reads.json').writeAsString(_json(inspected.memoryReads.map((m) => _scrub(m.toJson())).toList()));
    await File('${dir.path}/memory_writes.json').writeAsString(_json(inspected.memoryWrites.map((m) => _scrub(m.toJson())).toList()));
    await File('${dir.path}/tool_audits.json').writeAsString(_json(inspected.toolAudits.map((a) => _scrub(_auditToJson(a))).toList()));
    await File('${dir.path}/ancestry.json').writeAsString(_json(inspected.ancestryChain.map((e) => _scrub(e.toJson())).toList()));
    if (handoffTrace != null) {
      await File('${dir.path}/handoff_trace.json').writeAsString(_json(_scrub(handoffTrace)));
    }
    await File('${dir.path}/README.md').writeAsString(_bundleReadme(inspected));

    return dir.path;
  }

  Map<String, dynamic> _queueToJson(QueueItem? queue) {
    if (queue == null) return {'present': false};
    return {
      'id': queue.id,
      'eventId': queue.eventId,
      'state': queue.state.name,
      'attemptCount': queue.attemptCount,
      'maxAttempts': queue.maxAttempts,
      'nextAttemptAt': queue.nextAttemptAt,
      'createdAt': queue.createdAt,
      'updatedAt': queue.updatedAt,
      'queuedAt': queue.createdAt,
      'lastStateUpdateAt': queue.updatedAt,
    };
  }

  Map<String, dynamic> _auditToJson(ToolAuditRecord audit) {
    return {
      'id': audit.id,
      'invocationId': audit.invocationId,
      'eventId': audit.eventId,
      'agentId': audit.agentId,
      'sessionId': audit.sessionId,
      'handoffTraceId': audit.handoffTraceId,
      'rootEventId': audit.rootEventId,
      'toolId': audit.toolId,
      'decisionAllowed': audit.decisionAllowed,
      'decisionReason': audit.decisionReason,
      'consentOutcome': audit.consentOutcome,
      'outcome': audit.outcome,
      'inputRedacted': audit.inputRedacted,
      'outputRedacted': audit.outputRedacted,
      'createdAt': audit.createdAt,
    };
  }

  String _bundleReadme(InspectorData data) {
    return '''# OpenClaw diagnostics bundle

- Event: ${data.event.id}
- Session: ${data.session.id}
- Agent: ${data.session.agentId}
- Source: ${data.sourceLabel}
- Explanation: ${data.explanation}

This bundle is redacted by default. Secrets and token-like fields are scrubbed.
''';
  }

  dynamic _scrub(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_isSecretKey(key)) {
          out[key] = '[REDACTED]';
        } else {
          out[key] = _scrub(entry.value);
        }
      }
      return out;
    }
    if (value is List) {
      return value.map(_scrub).toList();
    }
    if (value is String) {
      return value
          .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._-]+', caseSensitive: false), 'Bearer [REDACTED]')
          .replaceAll(RegExp(r'(token|secret|password)=([^\s&]+)', caseSensitive: false), r'$1=[REDACTED]');
    }
    return value;
  }

  bool _isSecretKey(String key) {
    final lower = key.toLowerCase();
    return lower.contains('token') ||
        lower.contains('secret') ||
        lower.contains('password') ||
        lower.contains('apikey') ||
        lower.contains('bearer');
  }

  String _json(Object? value) => const JsonEncoder.withIndent('  ').convert(value);
}
