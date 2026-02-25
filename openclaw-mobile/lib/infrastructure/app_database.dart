import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/models.dart';

class AppDatabase extends GeneratedDatabase {
  AppDatabase({QueryExecutor? executor, int Function()? nowMs})
    : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
      super(executor ?? _openConnection());

  final int Function() _nowMs;

  static QueryExecutor _openConnection() => driftDatabase(name: 'openclaw_mobile');

  @override
  int get schemaVersion => 6;

  Future<void> init() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS agents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        heartbeat_json TEXT,
        hook_json TEXT,
        handoff_json TEXT,
        schema_version INTEGER NOT NULL
      )
    ''');
    if (!await _hasColumn('agents', 'heartbeat_json')) {
      await customStatement('ALTER TABLE agents ADD COLUMN heartbeat_json TEXT');
    }
    if (!await _hasColumn('agents', 'hook_json')) {
      await customStatement('ALTER TABLE agents ADD COLUMN hook_json TEXT');
    }
    if (!await _hasColumn('agents', 'handoff_json')) {
      await customStatement('ALTER TABLE agents ADD COLUMN handoff_json TEXT');
    }

    await customStatement('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        agent_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        schema_version INTEGER NOT NULL
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        schema_version INTEGER NOT NULL,
        UNIQUE(session_id, idempotency_key)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS queue_items (
        id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        state TEXT NOT NULL,
        attempt_count INTEGER NOT NULL,
        max_attempts INTEGER NOT NULL,
        next_attempt_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS run_results (
        id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL,
        output TEXT NOT NULL,
        completed_at INTEGER NOT NULL,
        schema_version INTEGER NOT NULL
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS handoff_traces (
        trace_id TEXT PRIMARY KEY,
        root_event_id TEXT NOT NULL,
        source_agent_id TEXT NOT NULL,
        current_agent_id TEXT NOT NULL,
        paused INTEGER NOT NULL,
        depth INTEGER NOT NULL,
        visited_agents_json TEXT NOT NULL,
        active INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS cron_schedules (
        schedule_id TEXT PRIMARY KEY,
        agent_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        enabled INTEGER NOT NULL,
        rule_json TEXT NOT NULL,
        timezone_id TEXT NOT NULL,
        missed_run_policy TEXT NOT NULL,
        prompt_template TEXT NOT NULL,
        last_run_at INTEGER,
        next_run_at INTEGER,
        schema_version INTEGER NOT NULL
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS memory_entries (
        id TEXT PRIMARY KEY,
        scope TEXT NOT NULL,
        scope_id TEXT,
        entry_type TEXT NOT NULL,
        content TEXT NOT NULL,
        source_event_id TEXT,
        source_run_id TEXT,
        source_agent_id TEXT,
        source_session_id TEXT,
        source_handoff_trace_id TEXT,
        source_root_event_id TEXT,
        importance INTEGER NOT NULL,
        pinned INTEGER NOT NULL,
        summary_of_ids_json TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_accessed_at INTEGER NOT NULL,
        schema_version INTEGER NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_memory_scope ON memory_entries(scope, scope_id, pinned, importance, last_accessed_at)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS run_memory_accesses (
        run_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        access_type TEXT NOT NULL,
        entry_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY(run_id, access_type, entry_id)
      )
    ''');
  }

  Future<bool> _hasColumn(String tableName, String columnName) async {
    final rows = await customSelect('PRAGMA table_info($tableName)').get();
    return rows.any((row) => row.read<String>('name') == columnName);
  }

  Future<void> upsertAgent(AgentProfile profile) async {
    await customStatement(
      'INSERT OR REPLACE INTO agents (id,name,created_at,heartbeat_json,hook_json,handoff_json,schema_version) VALUES (?,?,?,?,?,?,?)',
      [
        profile.id,
        profile.name,
        profile.createdAt,
        jsonEncode(profile.heartbeat.toJson()),
        jsonEncode(profile.hooks.toJson()),
        jsonEncode(profile.handoff.toJson()),
        profile.schemaVersion,
      ],
    );
  }

  Future<AgentProfile?> getAgent(String agentId) async {
    final rows = await customSelect(
      'SELECT * FROM agents WHERE id = ? LIMIT 1',
      variables: [Variable.withString(agentId)],
    ).get();
    if (rows.isEmpty) return null;
    return _agentFromRow(rows.first);
  }

  Future<List<AgentProfile>> listAgents() async {
    final rows = await customSelect('SELECT * FROM agents ORDER BY created_at DESC').get();
    return rows.map(_agentFromRow).toList();
  }

  AgentProfile _agentFromRow(QueryRow row) {
    final rawHeartbeat = row.read<String?>('heartbeat_json');
    final heartbeat = rawHeartbeat == null
        ? HeartbeatSettings.disabled()
        : HeartbeatSettings.fromJson(Map<String, dynamic>.from(jsonDecode(rawHeartbeat) as Map));
    final rawHooks = row.read<String?>('hook_json');
    final hooks = rawHooks == null
        ? HookSettings.defaults()
        : HookSettings.fromJson(Map<String, dynamic>.from(jsonDecode(rawHooks) as Map));
    final rawHandoff = row.read<String?>('handoff_json');
    final handoff = rawHandoff == null
        ? HandoffSettings.defaults()
        : HandoffSettings.fromJson(Map<String, dynamic>.from(jsonDecode(rawHandoff) as Map));

    return AgentProfile(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      createdAt: row.read<int>('created_at'),
      heartbeat: heartbeat,
      hooks: hooks,
      handoff: handoff,
      schemaVersion: row.read<int>('schema_version'),
    );
  }

  Future<void> upsertSession(Session session) async {
    await customStatement(
      'INSERT OR REPLACE INTO sessions (id,agent_id,channel_id,created_at,schema_version) VALUES (?,?,?,?,?)',
      [session.id, session.agentId, session.channelId, session.createdAt, session.schemaVersion],
    );
  }

  Future<Session?> latestSessionForAgent(String agentId) async {
    final rows = await customSelect(
      'SELECT * FROM sessions WHERE agent_id = ? ORDER BY created_at DESC LIMIT 1',
      variables: [Variable.withString(agentId)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return Session(
      id: row.read<String>('id'),
      agentId: row.read<String>('agent_id'),
      channelId: row.read<String>('channel_id'),
      createdAt: row.read<int>('created_at'),
      schemaVersion: row.read<int>('schema_version'),
    );
  }


  Future<Session?> getSessionById(String sessionId) async {
    final rows = await customSelect(
      'SELECT * FROM sessions WHERE id = ? LIMIT 1',
      variables: [Variable.withString(sessionId)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return Session(
      id: row.read<String>('id'),
      agentId: row.read<String>('agent_id'),
      channelId: row.read<String>('channel_id'),
      createdAt: row.read<int>('created_at'),
      schemaVersion: row.read<int>('schema_version'),
    );
  }

  Future<List<Session>> listSessionsByAgent(String agentId) async {
    final rows = await customSelect(
      'SELECT * FROM sessions WHERE agent_id = ? ORDER BY created_at DESC',
      variables: [Variable.withString(agentId)],
    ).get();
    return rows
        .map(
          (row) => Session(
            id: row.read<String>('id'),
            agentId: row.read<String>('agent_id'),
            channelId: row.read<String>('channel_id'),
            createdAt: row.read<int>('created_at'),
            schemaVersion: row.read<int>('schema_version'),
          ),
        )
        .toList();
  }

  Future<bool> insertEvent(Event event) async {
    try {
      await customStatement(
        'INSERT INTO events (id,session_id,type,payload_json,idempotency_key,created_at,schema_version) VALUES (?,?,?,?,?,?,?)',
        [
          event.id,
          event.sessionId,
          event.type.name,
          jsonEncode(event.payload),
          event.idempotencyKey,
          event.createdAt,
          event.schemaVersion,
        ],
      );
      return true;
    } on SqliteException {
      return false;
    }
  }


  Future<Event?> getEventById(String eventId) async {
    final rows = await customSelect(
      'SELECT * FROM events WHERE id = ? LIMIT 1',
      variables: [Variable.withString(eventId)],
    ).get();
    if (rows.isEmpty) return null;
    return _eventFromRow(rows.first);
  }

  Future<List<TimelineItem>> listTimelineBySession(String sessionId) async {
    final rows = await customSelect('''
      SELECT e.*, q.state AS queue_state
      FROM events e
      LEFT JOIN queue_items q ON q.event_id = e.id
      WHERE e.session_id = ?
      ORDER BY e.created_at ASC
    ''', variables: [Variable.withString(sessionId)]).get();

    return rows
        .map(
          (row) => TimelineItem(
            event: _eventFromRow(row),
            state: QueueState.values.byName((row.read<String?>('queue_state') ?? 'queued')),
          ),
        )
        .toList();
  }

  Event _eventFromRow(QueryRow row) {
    final rawType = row.read<String>('type');
    final normalized = rawType == 'message' ? 'humanMessage' : rawType;
    return Event(
      id: row.read<String>('id'),
      sessionId: row.read<String>('session_id'),
      type: EventType.values.byName(normalized),
      payload: Map<String, dynamic>.from(jsonDecode(row.read<String>('payload_json')) as Map),
      idempotencyKey: row.read<String>('idempotency_key'),
      createdAt: row.read<int>('created_at'),
      schemaVersion: row.read<int>('schema_version'),
    );
  }


  Future<int> countHookEventsForRoot(String rootEventId) async {
    final rows = await customSelect(
      "SELECT COUNT(*) as count FROM events WHERE type = 'internalHook' AND payload_json LIKE ?",
      variables: [Variable.withString('%"rootEventId":"$rootEventId"%')],
    ).get();
    if (rows.isEmpty) return 0;
    return rows.first.read<int>('count');
  }

  Future<void> enqueue({required String queueId, required String eventId, required String sessionId}) async {
    final now = _nowMs();
    await customStatement(
      'INSERT OR REPLACE INTO queue_items (id,event_id,session_id,state,attempt_count,max_attempts,next_attempt_at,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
      [queueId, eventId, sessionId, QueueState.queued.name, 0, 3, now, now, now],
    );
  }

  Future<QueueItem?> dequeueNextEligible() async {
    final now = _nowMs();
    final rows = await customSelect('''
      SELECT q.* FROM queue_items q
      WHERE q.state IN ('queued','failed')
        AND q.next_attempt_at <= ?
        AND NOT EXISTS (
          SELECT 1 FROM queue_items p
          WHERE p.session_id = q.session_id AND p.state = 'processing'
        )
      ORDER BY q.created_at ASC
      LIMIT 1
    ''', variables: [Variable.withInt(now)]).get();

    if (rows.isEmpty) return null;
    return _queueItemFromRow(rows.first);
  }

  Future<void> updateQueueState(String id, QueueState state, {int? nextAttemptAt}) async {
    final now = _nowMs();
    await customStatement(
      'UPDATE queue_items SET state = ?, next_attempt_at = ?, updated_at = ? WHERE id = ?',
      [state.name, nextAttemptAt ?? now, now, id],
    );
  }

  Future<void> markProcessing(String id) => updateQueueState(id, QueueState.processing);

  Future<void> markCompleted(String id) => updateQueueState(id, QueueState.completed);

  Future<void> markFailure(String id, int attemptCount, int maxAttempts) async {
    final now = _nowMs();
    final dead = attemptCount >= maxAttempts;
    final state = dead ? QueueState.deadLetter : QueueState.failed;
    final nextAttempt = dead ? now : now + (1000 * (1 << attemptCount));
    await customStatement(
      'UPDATE queue_items SET state = ?, attempt_count = ?, next_attempt_at = ?, updated_at = ? WHERE id = ?',
      [state.name, attemptCount, nextAttempt, now, id],
    );
  }

  Future<bool> retryEvent(String eventId) async {
    final rows = await customSelect(
      'SELECT * FROM queue_items WHERE event_id = ? LIMIT 1',
      variables: [Variable.withString(eventId)],
    ).get();
    if (rows.isEmpty) return false;
    final item = _queueItemFromRow(rows.first);
    final now = _nowMs();
    await customStatement(
      'UPDATE queue_items SET state = ?, attempt_count = 0, next_attempt_at = ?, updated_at = ? WHERE id = ?',
      [QueueState.queued.name, now, now, item.id],
    );
    return true;
  }



  Future<void> upsertHandoffTrace({
    required String traceId,
    required String rootEventId,
    required String sourceAgentId,
    required String currentAgentId,
    required bool paused,
    required int depth,
    required List<String> visitedAgents,
    required bool active,
  }) async {
    final now = _nowMs();
    final existing = await getHandoffTrace(traceId);
    final createdAt = (existing?['created_at'] as int?) ?? now;
    await customStatement(
      'INSERT OR REPLACE INTO handoff_traces (trace_id,root_event_id,source_agent_id,current_agent_id,paused,depth,visited_agents_json,active,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        traceId,
        rootEventId,
        sourceAgentId,
        currentAgentId,
        paused ? 1 : 0,
        depth,
        jsonEncode(visitedAgents),
        active ? 1 : 0,
        createdAt,
        now,
      ],
    );
  }

  Future<Map<String, dynamic>?> getHandoffTrace(String traceId) async {
    final rows = await customSelect(
      'SELECT * FROM handoff_traces WHERE trace_id = ? LIMIT 1',
      variables: [Variable.withString(traceId)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<List<Map<String, dynamic>>> listHandoffTracesByAgent(String agentId) async {
    final rows = await customSelect(
      'SELECT * FROM handoff_traces WHERE source_agent_id = ? OR current_agent_id = ? ORDER BY updated_at DESC',
      variables: [Variable.withString(agentId), Variable.withString(agentId)],
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<int> countActiveHandoffTraces() async {
    final rows = await customSelect('SELECT COUNT(*) as count FROM handoff_traces WHERE active = 1 AND paused = 0').get();
    if (rows.isEmpty) return 0;
    return rows.first.read<int>('count');
  }

  Future<void> setHandoffTracePaused(String traceId, bool paused) async {
    await customStatement(
      'UPDATE handoff_traces SET paused = ?, updated_at = ? WHERE trace_id = ?',
      [paused ? 1 : 0, _nowMs(), traceId],
    );
  }

  Future<void> upsertCronSchedule(CronSchedule schedule) async {
    await customStatement(
      'INSERT OR REPLACE INTO cron_schedules (schedule_id,agent_id,channel_id,session_id,enabled,rule_json,timezone_id,missed_run_policy,prompt_template,last_run_at,next_run_at,schema_version) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        schedule.scheduleId,
        schedule.agentId,
        schedule.channelId,
        schedule.sessionId,
        schedule.enabled ? 1 : 0,
        jsonEncode(schedule.rule.toJson()),
        schedule.timezoneId,
        schedule.missedRunPolicy.name,
        schedule.promptTemplate,
        schedule.lastRunAt,
        schedule.nextRunAt,
        schedule.schemaVersion,
      ],
    );
  }

  Future<void> deleteCronSchedule(String scheduleId) async {
    await customStatement('DELETE FROM cron_schedules WHERE schedule_id = ?', [scheduleId]);
  }

  Future<CronSchedule?> getCronSchedule(String scheduleId) async {
    final rows = await customSelect(
      'SELECT * FROM cron_schedules WHERE schedule_id = ? LIMIT 1',
      variables: [Variable.withString(scheduleId)],
    ).get();
    if (rows.isEmpty) return null;
    return _cronScheduleFromRow(rows.first);
  }

  Future<List<CronSchedule>> listCronSchedulesByAgent(String agentId) async {
    final rows = await customSelect(
      'SELECT * FROM cron_schedules WHERE agent_id = ? ORDER BY schedule_id ASC',
      variables: [Variable.withString(agentId)],
    ).get();
    return rows.map(_cronScheduleFromRow).toList();
  }

  Future<List<CronSchedule>> listCronSchedules() async {
    final rows = await customSelect('SELECT * FROM cron_schedules ORDER BY schedule_id ASC').get();
    return rows.map(_cronScheduleFromRow).toList();
  }

  CronSchedule _cronScheduleFromRow(QueryRow row) {
    return CronSchedule(
      scheduleId: row.read<String>('schedule_id'),
      agentId: row.read<String>('agent_id'),
      channelId: row.read<String>('channel_id'),
      sessionId: row.read<String>('session_id'),
      enabled: row.read<int>('enabled') == 1,
      rule: CronScheduleRule.fromJson(
        Map<String, dynamic>.from(jsonDecode(row.read<String>('rule_json')) as Map),
      ),
      timezoneId: row.read<String>('timezone_id'),
      missedRunPolicy: MissedRunPolicy.values.byName(row.read<String>('missed_run_policy')),
      promptTemplate: row.read<String>('prompt_template'),
      lastRunAt: row.read<int?>('last_run_at'),
      nextRunAt: row.read<int?>('next_run_at'),
      schemaVersion: row.read<int>('schema_version'),
    );
  }

  Future<void> insertRunResult(RunResult result) async {
    await customStatement(
      'INSERT OR REPLACE INTO run_results (id,event_id,output,completed_at,schema_version) VALUES (?,?,?,?,?)',
      [result.id, result.eventId, result.output, result.completedAt, result.schemaVersion],
    );
  }

  Future<List<RunResult>> listRunResultsByEvent(String eventId) async {
    final rows = await customSelect(
      'SELECT * FROM run_results WHERE event_id = ? ORDER BY completed_at ASC',
      variables: [Variable.withString(eventId)],
    ).get();
    return rows
        .map(
          (row) => RunResult(
            id: row.read<String>('id'),
            eventId: row.read<String>('event_id'),
            output: row.read<String>('output'),
            completedAt: row.read<int>('completed_at'),
            schemaVersion: row.read<int>('schema_version'),
          ),
        )
        .toList();
  }

  Future<void> insertRunResultWithMemory({
    required RunResult runResult,
    required String eventId,
    required List<MemoryEntry> readEntries,
    required List<MemoryEntry> writeEntries,
  }) async {
    final now = _nowMs();
    await transaction(() async {
      await insertRunResult(runResult);
      for (final entry in writeEntries) {
        await upsertMemoryEntry(entry);
      }
      for (final entry in readEntries) {
        await customStatement(
          'INSERT OR REPLACE INTO run_memory_accesses (run_id,event_id,access_type,entry_id,created_at) VALUES (?,?,?,?,?)',
          [runResult.id, eventId, 'read', entry.id, now],
        );
      }
      for (final entry in writeEntries) {
        await customStatement(
          'INSERT OR REPLACE INTO run_memory_accesses (run_id,event_id,access_type,entry_id,created_at) VALUES (?,?,?,?,?)',
          [runResult.id, eventId, 'write', entry.id, now],
        );
      }
    });
  }

  Future<void> upsertMemoryEntry(MemoryEntry entry) async {
    await customStatement(
      'INSERT OR REPLACE INTO memory_entries (id,scope,scope_id,entry_type,content,source_event_id,source_run_id,source_agent_id,source_session_id,source_handoff_trace_id,source_root_event_id,importance,pinned,summary_of_ids_json,created_at,updated_at,last_accessed_at,schema_version) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        entry.id,
        entry.scope.name,
        entry.scopeId,
        entry.entryType.name,
        entry.content,
        entry.sourceEventId,
        entry.sourceRunId,
        entry.sourceAgentId,
        entry.sourceSessionId,
        entry.sourceHandoffTraceId,
        entry.sourceRootEventId,
        entry.importance,
        entry.pinned ? 1 : 0,
        jsonEncode(entry.summaryOfEntryIds),
        entry.createdAt,
        entry.updatedAt,
        entry.lastAccessedAt,
        entry.schemaVersion,
      ],
    );
  }

  Future<List<MemoryEntry>> listMemoryByScope(MemoryScope scope, {String? scopeId}) async {
    final rows = scopeId == null
        ? await customSelect(
            'SELECT * FROM memory_entries WHERE scope = ? ORDER BY pinned DESC, importance DESC, updated_at DESC',
            variables: [Variable.withString(scope.name)],
          ).get()
        : await customSelect(
            'SELECT * FROM memory_entries WHERE scope = ? AND scope_id = ? ORDER BY pinned DESC, importance DESC, updated_at DESC',
            variables: [Variable.withString(scope.name), Variable.withString(scopeId)],
          ).get();
    return rows.map(_memoryFromRow).toList();
  }

  Future<List<MemoryEntry>> listMemoryForRetrieval({
    required String agentId,
    required String sessionId,
    required int limit,
    required int charBudget,
  }) async {
    final rows = await customSelect(
      '''
      SELECT * FROM memory_entries
      WHERE (scope = 'global')
         OR (scope = 'agent' AND scope_id = ?)
         OR (scope = 'session' AND scope_id = ?)
      ORDER BY pinned DESC, importance DESC, last_accessed_at DESC, updated_at DESC
      ''',
      variables: [Variable.withString(agentId), Variable.withString(sessionId)],
    ).get();

    final selected = <MemoryEntry>[];
    var budget = 0;
    for (final row in rows) {
      if (selected.length >= limit) break;
      final entry = _memoryFromRow(row);
      budget += entry.content.length;
      if (budget > charBudget) break;
      selected.add(entry);
    }
    return selected;
  }

  Future<void> touchMemoryEntries(List<String> ids, int timestamp) async {
    for (final id in ids) {
      await customStatement('UPDATE memory_entries SET last_accessed_at = ?, updated_at = ? WHERE id = ?', [timestamp, timestamp, id]);
    }
  }

  Future<void> updateMemoryEntry(MemoryEntry entry) => upsertMemoryEntry(entry);

  Future<void> clearMemoryByScope(MemoryScope scope, {String? scopeId}) async {
    if (scopeId == null) {
      await customStatement('DELETE FROM memory_entries WHERE scope = ?', [scope.name]);
      return;
    }
    await customStatement('DELETE FROM memory_entries WHERE scope = ? AND scope_id = ?', [scope.name, scopeId]);
  }

  Future<Map<String, List<MemoryEntry>>> listMemoryAccessByEvent(String eventId) async {
    final rows = await customSelect(
      '''
      SELECT r.access_type AS access_type, m.*
      FROM run_memory_accesses r
      JOIN memory_entries m ON m.id = r.entry_id
      WHERE r.event_id = ?
      ORDER BY r.created_at ASC
      ''',
      variables: [Variable.withString(eventId)],
    ).get();
    final read = <MemoryEntry>[];
    final write = <MemoryEntry>[];
    for (final row in rows) {
      final entry = _memoryFromRow(row);
      if (row.read<String>('access_type') == 'read') {
        read.add(entry);
      } else {
        write.add(entry);
      }
    }
    return {'read': read, 'write': write};
  }

  MemoryEntry _memoryFromRow(QueryRow row) {
    return MemoryEntry(
      id: row.read<String>('id'),
      scope: MemoryScope.values.byName(row.read<String>('scope')),
      scopeId: row.read<String?>('scope_id'),
      entryType: MemoryEntryType.values.byName(row.read<String>('entry_type')),
      content: row.read<String>('content'),
      sourceEventId: row.read<String?>('source_event_id'),
      sourceRunId: row.read<String?>('source_run_id'),
      sourceAgentId: row.read<String?>('source_agent_id'),
      sourceSessionId: row.read<String?>('source_session_id'),
      sourceHandoffTraceId: row.read<String?>('source_handoff_trace_id'),
      sourceRootEventId: row.read<String?>('source_root_event_id'),
      importance: row.read<int>('importance'),
      pinned: row.read<int>('pinned') == 1,
      summaryOfEntryIds: List<String>.from(
        jsonDecode(row.read<String?>('summary_of_ids_json') ?? '[]') as List,
      ),
      createdAt: row.read<int>('created_at'),
      updatedAt: row.read<int>('updated_at'),
      lastAccessedAt: row.read<int>('last_accessed_at'),
      schemaVersion: row.read<int>('schema_version'),
    );
  }

  Future<List<Map<String, Object?>>> listQueueItems() async {
    final rows = await customSelect('SELECT * FROM queue_items ORDER BY created_at ASC').get();
    return rows.map((r) => r.data).toList();
  }

  QueueItem _queueItemFromRow(QueryRow row) {
    return QueueItem(
      id: row.read<String>('id'),
      eventId: row.read<String>('event_id'),
      sessionId: row.read<String>('session_id'),
      state: QueueState.values.byName(row.read<String>('state')),
      attemptCount: row.read<int>('attempt_count'),
      maxAttempts: row.read<int>('max_attempts'),
      nextAttemptAt: row.read<int>('next_attempt_at'),
      createdAt: row.read<int>('created_at'),
      updatedAt: row.read<int>('updated_at'),
    );
  }
}

class QueueItem {
  QueueItem({
    required this.id,
    required this.eventId,
    required this.sessionId,
    required this.state,
    required this.attemptCount,
    required this.maxAttempts,
    required this.nextAttemptAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String eventId;
  final String sessionId;
  final QueueState state;
  final int attemptCount;
  final int maxAttempts;
  final int nextAttemptAt;
  final int createdAt;
  final int updatedAt;
}

class SecretStore {
  SecretStore(this._storage);
  final FlutterSecureStorage _storage;

  Future<void> saveProviderKey(String provider, String key) async {
    await _storage.write(key: 'provider:$provider', value: key);
  }

  Future<String?> readProviderKey(String provider) async {
    return _storage.read(key: 'provider:$provider');
  }
}
