import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'clock.dart';

class MemoryService {
  MemoryService(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;
  final _uuid = const Uuid();

  static const int retrievalLimit = 24;
  static const int retrievalCharBudget = 4000;
  static const int scopeCharBudget = 12000;

  Future<List<MemoryEntry>> readForRun({required Session session}) async {
    final entries = await _db.listMemoryForRetrieval(
      agentId: session.agentId,
      sessionId: session.id,
      limit: retrievalLimit,
      charBudget: retrievalCharBudget,
    );
    if (entries.isNotEmpty) {
      await _db.touchMemoryEntries(entries.map((e) => e.id).toList(), _clock.now().millisecondsSinceEpoch);
    }
    return entries;
  }

  List<MemoryEntry> buildWritesForRun({
    required Session session,
    required Event event,
    required RunResult runResult,
    required List<MemoryEntry> readEntries,
  }) {
    final now = _clock.now().millisecondsSinceEpoch;
    final writes = <MemoryEntry>[];

    writes.add(
      MemoryEntry(
        id: _uuid.v4(),
        scope: MemoryScope.session,
        scopeId: session.id,
        entryType: MemoryEntryType.fact,
        content: runResult.output.length > 600 ? '${runResult.output.substring(0, 600)}…' : runResult.output,
        sourceEventId: event.id,
        sourceRunId: runResult.id,
        sourceAgentId: session.agentId,
        sourceSessionId: session.id,
        sourceHandoffTraceId: event.payload['handoffTraceId']?.toString(),
        sourceRootEventId: event.payload['rootEventId']?.toString(),
        importance: event.type == EventType.agentHandoff ? 3 : 2,
        createdAt: now,
        updatedAt: now,
        lastAccessedAt: now,
      ),
    );

    if (event.type == EventType.humanMessage) {
      final text = event.payload['text']?.toString() ?? '';
      if (text.isNotEmpty) {
        writes.add(
          MemoryEntry(
            id: _uuid.v4(),
            scope: MemoryScope.agent,
            scopeId: session.agentId,
            content: 'User asked: $text',
            sourceEventId: event.id,
            sourceRunId: runResult.id,
            sourceAgentId: session.agentId,
            sourceSessionId: session.id,
            sourceHandoffTraceId: event.payload['handoffTraceId']?.toString(),
            sourceRootEventId: event.payload['rootEventId']?.toString(),
            importance: 2,
            createdAt: now,
            updatedAt: now,
            lastAccessedAt: now,
          ),
        );
      }
    }

    if (readEntries.isNotEmpty) {
      writes.add(
        MemoryEntry(
          id: _uuid.v4(),
          scope: MemoryScope.session,
          scopeId: session.id,
          entryType: MemoryEntryType.summary,
          content: 'Read ${readEntries.length} memory entries for run context.',
          sourceEventId: event.id,
          sourceRunId: runResult.id,
          sourceAgentId: session.agentId,
          sourceSessionId: session.id,
          sourceHandoffTraceId: event.payload['handoffTraceId']?.toString(),
          sourceRootEventId: event.payload['rootEventId']?.toString(),
          importance: 1,
          summaryOfEntryIds: readEntries.map((e) => e.id).toList(),
          createdAt: now,
          updatedAt: now,
          lastAccessedAt: now,
        ),
      );
    }

    return writes;
  }

  Future<void> compactSessionMemory(String sessionId) async {
    await _compactScope(MemoryScope.session, sessionId);
  }

  Future<void> compactAgentMemory(String agentId) async {
    await _compactScope(MemoryScope.agent, agentId);
  }

  Future<void> compactGlobalMemory() async {
    await _compactScope(MemoryScope.global, null);
  }

  Future<void> _compactScope(MemoryScope scope, String? scopeId) async {
    final entries = await _db.listMemoryByScope(scope, scopeId: scopeId);
    if (entries.isEmpty) return;

    final totalChars = entries.fold<int>(0, (sum, e) => sum + e.content.length);
    if (totalChars <= scopeCharBudget) return;

    final source = entries.where((e) => e.entryType == MemoryEntryType.fact).take(25).toList();
    if (source.length < 3) return;

    final now = _clock.now().millisecondsSinceEpoch;
    final summaryBody = source
        .map((e) => '- ${e.content.replaceAll('\n', ' ').trim()}')
        .join('\n');
    final content = summaryBody.length > 1800 ? '${summaryBody.substring(0, 1800)}…' : summaryBody;

    await _db.upsertMemoryEntry(
      MemoryEntry(
        id: _uuid.v4(),
        scope: scope,
        scopeId: scopeId,
        entryType: MemoryEntryType.summary,
        content: 'Compaction summary\n$content',
        importance: 2,
        summaryOfEntryIds: source.map((e) => e.id).toList(),
        createdAt: now,
        updatedAt: now,
        lastAccessedAt: now,
      ),
    );
  }
}
