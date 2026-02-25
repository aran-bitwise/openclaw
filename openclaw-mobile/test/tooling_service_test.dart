import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../lib/application/clock.dart';
import '../lib/application/tool_registry.dart';
import '../lib/application/tooling_service.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';

class _FakeClock implements Clock {
  _FakeClock(this._now);
  DateTime _now;

  @override
  DateTime now() => _now;
}

void main() {
  late AppDatabase db;
  late ToolingService tooling;
  late Session session;
  late Event event;

  setUp(() async {
    final clock = _FakeClock(DateTime.utc(2025, 1, 1, 8));
    db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    tooling = ToolingService(db, DefaultToolRegistry(), clock);

    await db.upsertAgent(AgentProfile(id: 'agent-a', name: 'Agent A', createdAt: clock.now().millisecondsSinceEpoch));
    session = Session(id: 'session-a', agentId: 'agent-a', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch);
    await db.upsertSession(session);

    event = Event(
      id: 'event-a',
      sessionId: session.id,
      type: EventType.humanMessage,
      payload: {
        'toolRequest': {
          'toolId': 'tool.echo',
          'input': {'message': 'hello secret token'},
          'idempotencyKey': 'same-key',
        },
      },
      idempotencyKey: 'evt-key',
      createdAt: clock.now().millisecondsSinceEpoch,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('permission grant and revoke affects policy', () async {
    expect(await db.getToolPermission(agentId: 'agent-a', toolId: 'tool.echo'), isFalse);
    await tooling.setPermission(agentId: 'agent-a', toolId: 'tool.echo', granted: true);
    expect(await db.getToolPermission(agentId: 'agent-a', toolId: 'tool.echo'), isTrue);
    await tooling.setPermission(agentId: 'agent-a', toolId: 'tool.echo', granted: false);
    expect(await db.getToolPermission(agentId: 'agent-a', toolId: 'tool.echo'), isFalse);
  });

  test('blocked when permission not granted', () async {
    final result = await tooling.maybeInvokeFromEvent(event, session);
    expect(result, isNotNull);
    expect(result!.invocation.decisionAllowed, isFalse);
    expect(result.invocation.decisionReason, contains('default_deny'));
  });

  test('high risk tool requires explicit runtime consent', () async {
    await tooling.setPermission(agentId: 'agent-a', toolId: 'tool.openUrl', granted: true);
    final riskyEvent = Event(
      id: 'event-risk',
      sessionId: session.id,
      type: EventType.humanMessage,
      payload: {
        'toolRequest': {
          'toolId': 'tool.openUrl',
          'input': {'url': 'https://example.com'},
          'idempotencyKey': 'risk-key',
        },
      },
      idempotencyKey: 'evt-risk',
      createdAt: 1,
    );

    final denied = await tooling.maybeInvokeFromEvent(riskyEvent, session, consentApproved: false);
    expect(denied!.invocation.decisionAllowed, isFalse);
    expect(denied.invocation.consentOutcome, 'denied');

    final approved = await tooling.maybeInvokeFromEvent(
      riskyEvent.copyWithPayload({'toolRequest': {'toolId': 'tool.openUrl', 'input': {'url': 'https://example.com'}, 'idempotencyKey': 'risk-key-2'}}),
      session,
      consentApproved: true,
    );
    expect(approved!.invocation.consentOutcome, 'approved');
    expect(approved.invocation.outcome, 'blocked');
    expect(approved.invocation.decisionReason, contains('sandbox'));
  });

  test('audit record keeps redacted payload fragments', () async {
    await tooling.setPermission(agentId: 'agent-a', toolId: 'tool.echo', granted: true);
    final result = await tooling.maybeInvokeFromEvent(event, session);
    final logs = await db.listToolAuditLogs(sessionId: session.id);
    expect(result, isNotNull);
    expect(logs, isNotEmpty);
    expect(logs.first.inputRedacted, contains('message'));
    expect(logs.first.inputRedacted.length, lessThan(200));
  });

  test('idempotent invocation executes only once for same key', () async {
    await tooling.setPermission(agentId: 'agent-a', toolId: 'tool.echo', granted: true);
    final first = await tooling.maybeInvokeFromEvent(event, session);
    final second = await tooling.maybeInvokeFromEvent(event, session);

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(second!.invocation.id, first!.invocation.id);

    final logs = await db.listToolAuditLogs(sessionId: session.id);
    expect(logs.length, 2);
    expect(logs.first.decisionReason, anyOf(contains('idempotent'), contains('permission')));
  });
}

extension on Event {
  Event copyWithPayload(Map<String, dynamic> payload) {
    return Event(
      id: id,
      sessionId: sessionId,
      type: type,
      payload: payload,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
      schemaVersion: schemaVersion,
    );
  }
}
