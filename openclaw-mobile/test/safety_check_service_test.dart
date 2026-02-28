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
  test('safety check orchestration aggregates verdict, writes memory, and is idempotent', () async {
    final clock = _FakeClock(DateTime.utc(2025, 1, 1, 8, 0));
    final db = AppDatabase(executor: NativeDatabase.memory(), nowMs: () => clock.now().millisecondsSinceEpoch);
    await db.init();
    FlutterSecureStorage.setMockInitialValues({});

    await db.upsertAgent(AgentProfile(id: 'agent-a', name: 'Agent A', createdAt: clock.now().millisecondsSinceEpoch));
    final session = Session(id: 'session-a', agentId: 'agent-a', channelId: 'mobile-chat', createdAt: clock.now().millisecondsSinceEpoch);
    await db.upsertSession(session);

    await db.saveCameraGatewaySettings(baseUrl: 'http://10.0.2.2:8799', enabled: true, tokenSet: true);
    await SecretStore(const FlutterSecureStorage()).saveCameraGatewayToken('demo-token');

    final now = clock.now().millisecondsSinceEpoch;
    await db.upsertConfiguredCamera(
      ConfiguredCamera(
        cameraId: 'cam-living',
        name: 'Living Room',
        location: 'Living',
        enabled: true,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final tooling = ToolingService(
      db,
      DefaultToolRegistry(),
      clock,
      cameraClientFactory: ({required baseUrl, required bearerToken}) => CameraGatewayClient(
        baseUrl: baseUrl,
        bearerToken: bearerToken,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/cameras/cam-living/snapshot')) {
            return http.Response(
              '{"cameraId":"cam-living","capturedAt":"2025-01-01T08:00:00Z","snapshotUrl":"http://10.0.2.2:8799/fixtures/fall.jpg","checksum":"abcdef123456","quality":{"w":1280,"h":720,"format":"jpg"},"mode":"test_fall"}',
              200,
            );
          }
          return http.Response('{"error":"not found"}', 404);
        }),
      ),
    );

    await tooling.setPermission(agentId: 'agent-a', toolId: 'tool.cameraSnapshot', granted: true);
    await tooling.setPermission(agentId: 'agent-a', toolId: 'tool.fallDetect', granted: true);

    final service = SafetyCheckService(db, tooling, clock);
    final processor = QueueProcessor(
      db,
      clock,
      memoryService: MemoryService(db, clock),
      toolingService: tooling,
      safetyCheckService: service,
    );

    final event = Event(
      id: 'evt-safety-1',
      sessionId: session.id,
      type: EventType.cron,
      payload: {
        'workflow': 'safety_check',
        'modeOverride': 'test_fall',
        'toolConsentApproved': true,
      },
      idempotencyKey: 'safety-manual-session-a-test_fall-1',
      createdAt: now,
    );
    expect(await db.insertEvent(event), isTrue);
    expect(await db.insertEvent(event), isFalse, reason: 'idempotency key should prevent duplicate event');
    await db.enqueue(queueId: 'q1', eventId: event.id, sessionId: session.id);

    await processor.tick();

    final runs = await db.listRunResultsByEvent(event.id);
    expect(runs.single.output, contains('overall=fall_suspected'));

    final memory = await db.listMemoryAccessByEvent(event.id);
    expect(memory['write'], isNotEmpty);
    expect(memory['write']!.any((entry) => entry.content.contains('"kind":"safety-check"')), isTrue);

    final audits = await db.listToolAuditLogsForEvent(event.id);
    expect(audits.any((a) => a.toolId == 'tool.cameraSnapshot'), isTrue);
    expect(audits.any((a) => a.toolId == 'tool.fallDetect'), isTrue);
    expect(audits.map((a) => '${a.inputRedacted}${a.outputRedacted}').join('\n'), isNot(contains('demo-token')));

    await db.close();
  });
}
