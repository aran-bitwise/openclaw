import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../lib/application/clock.dart';
import '../lib/application/memory_service.dart';
import '../lib/application/queue_processor.dart';
import '../lib/application/safety_check_service.dart';
import '../lib/application/tool_registry.dart';
import '../lib/application/tooling_service.dart';
import '../lib/application/workflow_dispatcher.dart';
import '../lib/domain/models.dart';
import '../lib/infrastructure/app_database.dart';
import '../lib/infrastructure/camera_gateway_client.dart';

class _FakeClock implements Clock {
  _FakeClock(this._now);
  DateTime _now;

  @override
  DateTime now() => _now;
}

Future<ToolingService> _tooling(AppDatabase db, Clock clock, {required MockClient client}) async {
  return ToolingService(
    db,
    DefaultToolRegistry(),
    clock,
    cameraClientFactory: ({required baseUrl, required bearerToken}) => CameraGatewayClient(
      baseUrl: baseUrl,
      bearerToken: bearerToken,
      client: client,
    ),
  );
}

void main() {
  test('scheduled run with auto-consent disabled blocks awaiting consent and executes no tools', () async {
    final clock = _FakeClock(DateTime.utc(2025, 1, 1, 8));
    final db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    FlutterSecureStorage.setMockInitialValues({});

    await db.upsertAgent(AgentProfile(id: 'a1', name: 'Agent', createdAt: clock.now().millisecondsSinceEpoch));
    final session = Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch);
    await db.upsertSession(session);

    final now = clock.now().millisecondsSinceEpoch;
    await db.upsertConfiguredCamera(ConfiguredCamera(cameraId: 'cam-1', name: 'Cam', location: 'Living', enabled: true, createdAt: now, updatedAt: now));
    await db.saveCameraGatewaySettings(baseUrl: 'http://10.0.2.2:8799', enabled: true, tokenSet: true);
    await SecretStore(const FlutterSecureStorage()).saveCameraGatewayToken('demo-token');

    final tooling = await _tooling(db, clock, client: MockClient((_) async => http.Response('{}', 200)));
    await tooling.setPermission(agentId: 'a1', toolId: 'tool.cameraSnapshot', granted: true);
    await tooling.setPermission(agentId: 'a1', toolId: 'tool.fallDetect', granted: true);

    final safety = SafetyCheckService(db, tooling, clock);
    final dispatcher = WorkflowDispatcher(
      handlers: {'safety_check': (event, session) async => WorkflowDispatchResult(handled: true, output: await safety.runSafetyCheck(event: event, session: session))},
    );
    final processor = QueueProcessor(db, clock, memoryService: MemoryService(db, clock), toolingService: tooling, workflowDispatcher: dispatcher);

    final event = Event(
      id: 'e1',
      sessionId: session.id,
      type: EventType.cron,
      payload: {'workflow': 'safety_check', 'trigger': 'scheduled', 'checkId': 'check:s1', 'modeOverride': 'latest', 'toolConsentApproved': false},
      idempotencyKey: 'cron-safety-1',
      createdAt: now,
    );
    await db.insertEvent(event);
    await db.enqueue(queueId: 'q1', eventId: event.id, sessionId: session.id);
    await processor.tick();

    final runs = await db.listRunResultsByEvent(event.id);
    expect(runs.single.output, contains('BLOCKED_AWAITING_CONSENT'));
    final audits = await db.listToolAuditLogsForEvent(event.id);
    expect(audits, isEmpty);

    await db.close();
  });

  test('scheduled run with auto-consent enabled executes and records auto-approved reason', () async {
    final clock = _FakeClock(DateTime.utc(2025, 1, 1, 8));
    final db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    FlutterSecureStorage.setMockInitialValues({});

    await db.upsertAgent(
      AgentProfile(
        id: 'a1',
        name: 'Agent',
        createdAt: clock.now().millisecondsSinceEpoch,
        safety: const SafetySettings(safetyCheckAutoConsentEnabled: true),
      ),
    );
    final session = Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch);
    await db.upsertSession(session);

    final now = clock.now().millisecondsSinceEpoch;
    await db.upsertConfiguredCamera(ConfiguredCamera(cameraId: 'cam-1', name: 'Cam', location: 'Living', enabled: true, createdAt: now, updatedAt: now));
    await db.saveCameraGatewaySettings(baseUrl: 'http://10.0.2.2:8799', enabled: true, tokenSet: true);
    await SecretStore(const FlutterSecureStorage()).saveCameraGatewayToken('demo-token');

    final tooling = await _tooling(
      db,
      clock,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/snapshot')) {
          return http.Response('{"cameraId":"cam-1","capturedAt":"2025-01-01T08:00:00Z","snapshotUrl":"http://10.0.2.2:8799/fixtures/fall.jpg","checksum":"abcdef123456"}', 200);
        }
        return http.Response('{}', 404);
      }),
    );
    await tooling.setPermission(agentId: 'a1', toolId: 'tool.cameraSnapshot', granted: true);
    await tooling.setPermission(agentId: 'a1', toolId: 'tool.fallDetect', granted: true);

    final safety = SafetyCheckService(db, tooling, clock);
    final outcome = await safety.runSafetyCheck(
      event: Event(
        id: 'e2',
        sessionId: session.id,
        type: EventType.cron,
        payload: {'workflow': 'safety_check', 'trigger': 'scheduled', 'modeOverride': 'test_fall', 'checkId': 'check:2', 'toolConsentApproved': false},
        idempotencyKey: 'cron-safety-2',
        createdAt: now,
      ),
      session: session,
    );

    expect(outcome.overallVerdict, 'fall_suspected');
    final firstAudits = await db.listToolAuditLogsForEvent('e2');
    expect(firstAudits.where((a) => a.decisionReason.contains('auto_approved_by_setting')).isNotEmpty, isTrue);

    await safety.runSafetyCheck(
      event: Event(
        id: 'e2',
        sessionId: session.id,
        type: EventType.cron,
        payload: {'workflow': 'safety_check', 'trigger': 'scheduled', 'modeOverride': 'test_fall', 'checkId': 'check:2', 'toolConsentApproved': false},
        idempotencyKey: 'cron-safety-2',
        createdAt: now,
      ),
      session: session,
    );
    final secondAudits = await db.listToolAuditLogsForEvent('e2');
    expect(secondAudits.any((a) => a.decisionReason == 'idempotent-reuse'), isTrue);

    await db.close();
  });

  test('per-camera failures map to error and uncertain overall', () async {
    final clock = _FakeClock(DateTime.utc(2025, 1, 1, 8));
    final db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    FlutterSecureStorage.setMockInitialValues({});
    await db.upsertAgent(
      AgentProfile(id: 'a1', name: 'Agent', createdAt: clock.now().millisecondsSinceEpoch, safety: const SafetySettings(safetyCheckAutoConsentEnabled: true)),
    );
    final session = Session(id: 's1', agentId: 'a1', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch);
    await db.upsertSession(session);
    final now = clock.now().millisecondsSinceEpoch;
    await db.upsertConfiguredCamera(ConfiguredCamera(cameraId: 'cam-1', name: 'Cam', location: 'Living', enabled: true, createdAt: now, updatedAt: now));
    await db.saveCameraGatewaySettings(baseUrl: 'http://10.0.2.2:8799', enabled: true, tokenSet: true);
    await SecretStore(const FlutterSecureStorage()).saveCameraGatewayToken('demo-token');

    final tooling = await _tooling(db, clock, client: MockClient((_) async => http.Response('{"error":"network unavailable (offline fallback)","code":"offline"}', 503)));
    await tooling.setPermission(agentId: 'a1', toolId: 'tool.cameraSnapshot', granted: true);
    await tooling.setPermission(agentId: 'a1', toolId: 'tool.fallDetect', granted: true);

    final safety = SafetyCheckService(db, tooling, clock);
    final out = await safety.runSafetyCheck(
      event: Event(id: 'e3', sessionId: session.id, type: EventType.cron, payload: {'workflow': 'safety_check', 'trigger': 'scheduled', 'checkId': 'check:3'}, idempotencyKey: 'k3', createdAt: now),
      session: session,
    );

    expect(out.overallVerdict, 'uncertain');
    expect(out.findings.single.status, 'error');
    expect(out.findings.single.errorType, isNotEmpty);
    await db.close();
  });

  test('dispatcher routes workflow handler', () async {
    final event = Event(id: 'e', sessionId: 's', type: EventType.cron, payload: {'workflow': 'safety_check'}, idempotencyKey: 'k', createdAt: 1);
    final session = Session(id: 's', agentId: 'a', channelId: 'c', createdAt: 1);
    final dispatcher = WorkflowDispatcher(
      handlers: {'safety_check': (event, session) async => const WorkflowDispatchResult(handled: true, output: 'handled')},
    );

    final out = await dispatcher.dispatch(event, session);
    expect(out.handled, isTrue);
    expect(out.output, 'handled');
  });
}
