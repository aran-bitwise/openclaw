import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../lib/application/clock.dart';
import '../lib/application/tool_registry.dart';
import '../lib/application/tooling_service.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';
import '../lib/infrastructure/camera_gateway_client.dart';

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
    FlutterSecureStorage.setMockInitialValues({});
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

  test('tool.cameraList blocked when permission missing and allowed when granted', () async {
    await db.saveCameraGatewaySettings(baseUrl: 'http://10.0.2.2:8799', enabled: true, tokenSet: true);
    await SecretStore(const FlutterSecureStorage()).saveCameraGatewayToken('demo-token');

    final listEvent = Event(
      id: 'event-camera-list',
      sessionId: session.id,
      type: EventType.humanMessage,
      payload: {
        'toolRequest': {
          'toolId': 'tool.cameraList',
          'input': {'includeDisabled': true},
          'idempotencyKey': 'camera-list-key',
        },
      },
      idempotencyKey: 'evt-camera-list',
      createdAt: 1,
    );

    final blocked = await tooling.maybeInvokeFromEvent(listEvent, session);
    expect(blocked!.invocation.decisionAllowed, isFalse);

    tooling = ToolingService(
      db,
      DefaultToolRegistry(),
      _FakeClock(DateTime.utc(2025, 1, 1, 8)),
      cameraClientFactory: ({required baseUrl, required bearerToken}) => CameraGatewayClient(
        baseUrl: baseUrl,
        bearerToken: bearerToken,
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer demo-token');
          return http.Response('{"cameras":[{"cameraId":"cam-living","name":"Living","location":"Living","status":"online","enabled":true}]}', 200);
        }),
      ),
    );

    await tooling.setPermission(agentId: 'agent-a', toolId: 'tool.cameraList', granted: true);
    final allowed = await tooling.maybeInvokeFromEvent(
      listEvent.copyWithPayload({
        'toolRequest': {'toolId': 'tool.cameraList', 'input': {'includeDisabled': true}, 'idempotencyKey': 'camera-list-key-2'},
      }),
      session,
    );
    expect(allowed!.invocation.decisionAllowed, isTrue);
    expect(allowed.invocation.outcome, 'success');
  });



  test('tool.fallDetect returns deterministic verdict by fixture URL', () async {
    await tooling.setPermission(agentId: 'agent-a', toolId: 'tool.fallDetect', granted: true);

    Future<ToolExecutionResult?> run(String eventId, String url) {
      final e = Event(
        id: eventId,
        sessionId: session.id,
        type: EventType.humanMessage,
        payload: {
          'toolRequest': {
            'toolId': 'tool.fallDetect',
            'input': {'snapshotUrl': url, 'cameraId': 'cam-living', 'checksum': 'abcdef123456'},
            'idempotencyKey': 'idem-$eventId',
          },
        },
        idempotencyKey: 'evt-$eventId',
        createdAt: 1,
      );
      return tooling.maybeInvokeFromEvent(e, session, consentApproved: true);
    }

    final fall = await run('fall', 'http://10.0.2.2:8799/fixtures/fall.jpg');
    final uncertain = await run('uncertain', 'http://10.0.2.2:8799/fixtures/uncertain.jpg');
    final ok = await run('ok', 'http://10.0.2.2:8799/fixtures/ok.jpg');

    expect(fall!.invocation.outputRedacted, contains('fall_suspected'));
    expect(uncertain!.invocation.outputRedacted, contains('uncertain'));
    expect(ok!.invocation.outputRedacted, contains('"ok"'));
    expect(fall.invocation.inputRedacted, isNot(contains('abcdef123456')));
  });

  test('tool.cameraSnapshot requires consent and redacts token/query in audit', () async {
    await db.saveCameraGatewaySettings(baseUrl: 'http://10.0.2.2:8799', enabled: true, tokenSet: true);
    await SecretStore(const FlutterSecureStorage()).saveCameraGatewayToken('demo-token');
    await tooling.setPermission(agentId: 'agent-a', toolId: 'tool.cameraSnapshot', granted: true);

    tooling = ToolingService(
      db,
      DefaultToolRegistry(),
      _FakeClock(DateTime.utc(2025, 1, 1, 8)),
      cameraClientFactory: ({required baseUrl, required bearerToken}) => CameraGatewayClient(
        baseUrl: baseUrl,
        bearerToken: bearerToken,
        client: MockClient((_) async => http.Response(
          '{"cameraId":"cam-living","capturedAt":"2025-01-01T08:00:00Z","snapshotUrl":"http://10.0.2.2:8799/fixtures/fall.jpg?token=abc","checksum":"abcdef123456","quality":{"w":1280,"h":720,"format":"jpg"},"mode":"test_fall"}',
          200,
        )),
      ),
    );

    final cameraEvent = Event(
      id: 'event-camera-snapshot',
      sessionId: session.id,
      type: EventType.humanMessage,
      payload: {
        'toolRequest': {
          'toolId': 'tool.cameraSnapshot',
          'input': {'cameraId': 'cam-living', 'mode': 'test_fall', 'token': 'should-not-log'},
          'idempotencyKey': 'camera-snapshot-key',
        },
      },
      idempotencyKey: 'evt-camera-snapshot',
      createdAt: 1,
    );

    final denied = await tooling.maybeInvokeFromEvent(cameraEvent, session, consentApproved: false);
    expect(denied!.invocation.decisionAllowed, isFalse);
    expect(denied.invocation.consentOutcome, 'denied');

    final approved = await tooling.maybeInvokeFromEvent(
      cameraEvent.copyWithPayload({
        'toolRequest': {
          'toolId': 'tool.cameraSnapshot',
          'input': {'cameraId': 'cam-living', 'mode': 'test_fall', 'token': 'should-not-log'},
          'idempotencyKey': 'camera-snapshot-key-2',
        },
      }),
      session,
      consentApproved: true,
    );

    expect(approved!.invocation.decisionAllowed, isTrue);
    expect(approved.invocation.outputRedacted, isNot(contains('demo-token')));
    expect(approved.invocation.outputRedacted, isNot(contains('?token=')));
    expect(approved.invocation.inputRedacted, isNot(contains('should-not-log')));
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
