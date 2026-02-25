import 'dart:io';

import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../lib/application/clock.dart';
import '../lib/application/inspector_service.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';

class _FakeClock implements Clock {
  _FakeClock(this.current);
  DateTime current;

  @override
  DateTime now() => current;
}

void main() {
  late AppDatabase db;
  late _FakeClock clock;
  late InspectorService inspector;

  setUp(() async {
    clock = _FakeClock(DateTime.utc(2025, 1, 1, 10));
    db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    inspector = InspectorService(db, clock);

    await db.upsertAgent(AgentProfile(id: 'a1', name: 'Agent 1', createdAt: clock.now().millisecondsSinceEpoch));
    await db.upsertSession(Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch));
  });

  tearDown(() async {
    await db.close();
  });

  test('ancestry chain is ordered Root -> Parent -> Current', () async {
    final root = _event('root', payload: {'text': 'root'});
    final parent = _event('parent', payload: {'text': 'parent', 'parentEventId': 'root', 'rootEventId': 'root'});
    final current = _event('current', payload: {'text': 'current', 'parentEventId': 'parent', 'rootEventId': 'root'});

    await db.insertEvent(root);
    await db.insertEvent(parent);
    await db.insertEvent(current);

    final data = await inspector.inspectEvent('current');
    expect(data, isNotNull);
    expect(data!.ancestryChain.map((e) => e.id).toList(), ['root', 'parent', 'current']);
  });

  test('inspector assembles human event with memory and tool audit', () async {
    final event = _event('event-human', payload: {'text': 'hello', 'toolRequest': {'toolId': 'tool.echo'}});
    await db.insertEvent(event);
    await db.enqueue(queueId: 'q1', eventId: event.id, sessionId: event.sessionId);

    final run = RunResult(id: 'r1', eventId: event.id, output: 'done', completedAt: clock.now().millisecondsSinceEpoch);
    final read = MemoryEntry(
      id: 'm-read',
      scope: MemoryScope.global,
      content: 'pref',
      createdAt: 1,
      updatedAt: 1,
      lastAccessedAt: 1,
    );
    final write = MemoryEntry(
      id: 'm-write',
      scope: MemoryScope.session,
      scopeId: 's1',
      content: 'result',
      sourceRunId: 'r1',
      createdAt: 1,
      updatedAt: 1,
      lastAccessedAt: 1,
    );
    await db.upsertMemoryEntry(read);
    await db.insertRunResultWithMemory(runResult: run, eventId: event.id, readEntries: [read], writeEntries: [write]);

    await db.insertToolAuditLog(
      ToolAuditRecord(
        id: 'audit1',
        invocationId: 'inv1',
        eventId: event.id,
        agentId: 'a1',
        sessionId: 's1',
        toolId: 'tool.echo',
        decisionAllowed: true,
        decisionReason: 'permission granted',
        consentOutcome: 'not_required',
        outcome: 'success',
        inputRedacted: '{"message":"hi"}',
        outputRedacted: '{"echo":"hi"}',
        createdAt: clock.now().millisecondsSinceEpoch,
      ),
    );

    final data = await inspector.inspectEvent(event.id);
    expect(data, isNotNull);
    expect(data!.memoryReads.length, 1);
    expect(data.memoryWrites.length, 1);
    expect(data.toolAudits.single.toolId, 'tool.echo');
  });

  test('inspector explanations for webhook/hook/handoff are specific', () async {
    final webhook = _event('webhook', type: EventType.webhook, payload: {'relayEventId': 'relay-1', 'provider': 'generic'});
    final hook = _event('hook', type: EventType.internalHook, payload: {'hookType': 'turnStart', 'parentEventId': 'webhook'});
    final handoff = _event(
      'handoff',
      type: EventType.agentHandoff,
      payload: {'fromAgentId': 'a1', 'toAgentId': 'a2', 'handoffTraceId': 'trace-1'},
    );
    await db.insertEvent(webhook);
    await db.insertEvent(hook);
    await db.insertEvent(handoff);

    final webhookData = await inspector.inspectEvent('webhook');
    final hookData = await inspector.inspectEvent('hook');
    final handoffData = await inspector.inspectEvent('handoff');

    expect(webhookData!.explanation, contains('webhook delivery'));
    expect(hookData!.explanation, contains('Created by'));
    expect(handoffData!.explanation, contains('delegated'));
  });

  test('diagnostics export writes required files and redacts secrets', () async {
    final event = _event('event-export', payload: {'text': 'x', 'relayToken': 'abc123', 'authorization': 'Bearer token123'});
    await db.insertEvent(event);
    await db.enqueue(queueId: 'q-exp', eventId: event.id, sessionId: event.sessionId);

    final path = await inspector.exportDiagnosticsForEvent(event.id);
    final dir = Directory(path);
    expect(await dir.exists(), isTrue);
    expect(await File('$path/metadata.json').exists(), isTrue);
    expect(await File('$path/event.json').exists(), isTrue);
    expect(await File('$path/queue.json').exists(), isTrue);

    final eventJson = await File('$path/event.json').readAsString();
    expect(eventJson, isNot(contains('abc123')));
    expect(eventJson, isNot(contains('token123')));
  });
}

Event _event(String id, {EventType type = EventType.humanMessage, Map<String, dynamic>? payload}) {
  return Event(
    id: id,
    sessionId: 's1',
    type: type,
    payload: payload ?? {'text': id},
    idempotencyKey: 'idem-$id',
    createdAt: 1,
  );
}
