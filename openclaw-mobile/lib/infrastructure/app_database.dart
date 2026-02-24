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
  int get schemaVersion => 3;

  Future<void> init() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS agents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        heartbeat_json TEXT,
        schema_version INTEGER NOT NULL
      )
    ''');
    if (!await _hasColumn('agents', 'heartbeat_json')) {
      await customStatement('ALTER TABLE agents ADD COLUMN heartbeat_json TEXT');
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
  }

  Future<bool> _hasColumn(String tableName, String columnName) async {
    final rows = await customSelect('PRAGMA table_info($tableName)').get();
    return rows.any((row) => row.read<String>('name') == columnName);
  }

  Future<void> upsertAgent(AgentProfile profile) async {
    await customStatement(
      'INSERT OR REPLACE INTO agents (id,name,created_at,heartbeat_json,schema_version) VALUES (?,?,?,?,?)',
      [
        profile.id,
        profile.name,
        profile.createdAt,
        jsonEncode(profile.heartbeat.toJson()),
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

    return AgentProfile(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      createdAt: row.read<int>('created_at'),
      heartbeat: heartbeat,
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
