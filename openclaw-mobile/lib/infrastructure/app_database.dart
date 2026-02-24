import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/models.dart';

class AppDatabase extends GeneratedDatabase {
  AppDatabase({QueryExecutor? executor}) : super(executor ?? _openConnection());

  static QueryExecutor _openConnection() => driftDatabase(name: 'openclaw_mobile');

  @override
  int get schemaVersion => 1;

  Future<void> init() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS agents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        schema_version INTEGER NOT NULL
      )
    ''');
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
  }

  Future<void> upsertAgent(AgentProfile profile) async {
    await customStatement(
      'INSERT OR REPLACE INTO agents (id,name,created_at,schema_version) VALUES (?,?,?,?)',
      [profile.id, profile.name, profile.createdAt, profile.schemaVersion],
    );
  }

  Future<List<AgentProfile>> listAgents() async {
    final rows = await customSelect('SELECT * FROM agents ORDER BY created_at DESC').get();
    return rows
        .map(
          (row) => AgentProfile(
            id: row.read<String>('id'),
            name: row.read<String>('name'),
            createdAt: row.read<int>('created_at'),
            schemaVersion: row.read<int>('schema_version'),
          ),
        )
        .toList();
  }

  Future<void> upsertSession(Session session) async {
    await customStatement(
      'INSERT OR REPLACE INTO sessions (id,agent_id,channel_id,created_at,schema_version) VALUES (?,?,?,?,?)',
      [session.id, session.agentId, session.channelId, session.createdAt, session.schemaVersion],
    );
  }

  Future<List<Session>> listSessions() async {
    final rows = await customSelect('SELECT * FROM sessions ORDER BY created_at DESC').get();
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

  Future<List<Event>> listEventsBySession(String sessionId) async {
    final rows = await customSelect(
      'SELECT * FROM events WHERE session_id = ? ORDER BY created_at ASC',
      variables: [Variable.withString(sessionId)],
    ).get();
    return rows
        .map(
          (row) => Event(
            id: row.read<String>('id'),
            sessionId: row.read<String>('session_id'),
            type: EventType.values.byName(row.read<String>('type')),
            payload: Map<String, dynamic>.from(jsonDecode(row.read<String>('payload_json')) as Map),
            idempotencyKey: row.read<String>('idempotency_key'),
            createdAt: row.read<int>('created_at'),
            schemaVersion: row.read<int>('schema_version'),
          ),
        )
        .toList();
  }

  Future<void> enqueue({required String queueId, required String eventId, required String sessionId}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      'INSERT OR REPLACE INTO queue_items (id,event_id,session_id,state,attempt_count,max_attempts,next_attempt_at,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
      [queueId, eventId, sessionId, QueueState.queued.name, 0, 3, now, now, now],
    );
  }

  Future<QueueItem?> dequeueNextEligible() async {
    final now = DateTime.now().millisecondsSinceEpoch;
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
    final row = rows.first;
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

  Future<void> updateQueueState(String id, QueueState state, {int? nextAttemptAt}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      'UPDATE queue_items SET state = ?, next_attempt_at = ?, updated_at = ? WHERE id = ?',
      [state.name, nextAttemptAt ?? now, now, id],
    );
  }

  Future<void> markProcessing(String id) => updateQueueState(id, QueueState.processing);

  Future<void> markCompleted(String id) => updateQueueState(id, QueueState.completed);

  Future<void> markFailure(String id, int attemptCount, int maxAttempts) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dead = attemptCount >= maxAttempts;
    final state = dead ? QueueState.deadLetter : QueueState.failed;
    final nextAttempt = dead ? now : now + (1000 * (1 << attemptCount));
    await customStatement(
      'UPDATE queue_items SET state = ?, attempt_count = ?, next_attempt_at = ?, updated_at = ? WHERE id = ?',
      [state.name, attemptCount, nextAttempt, now, id],
    );
  }

  Future<void> insertRunResult(RunResult result) async {
    await customStatement(
      'INSERT OR REPLACE INTO run_results (id,event_id,output,completed_at,schema_version) VALUES (?,?,?,?,?)',
      [result.id, result.eventId, result.output, result.completedAt, result.schemaVersion],
    );
  }

  Future<List<Map<String, Object?>>> listQueueItems() async {
    final rows = await customSelect('SELECT * FROM queue_items ORDER BY created_at ASC').get();
    return rows.map((r) => r.data).toList();
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
