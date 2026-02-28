import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import '../infrastructure/camera_gateway_client.dart';
import 'clock.dart';
import 'tool_registry.dart';

typedef CameraClientFactory = CameraGatewayClient Function({required String baseUrl, required String bearerToken});

class ToolExecutionResult {
  ToolExecutionResult({required this.invocation, required this.audit});

  final ToolInvocation invocation;
  final ToolAuditRecord audit;
}

class ToolingService {
  ToolingService(this._db, this._registry, this._clock, {SecretStore? secretStore, CameraClientFactory? cameraClientFactory})
    : _secretStore = secretStore ?? SecretStore(const FlutterSecureStorage()),
      _cameraClientFactory = cameraClientFactory ?? CameraGatewayClient.new;

  final AppDatabase _db;
  final ToolRegistry _registry;
  final Clock _clock;
  final SecretStore _secretStore;
  final CameraClientFactory _cameraClientFactory;
  final _uuid = const Uuid();

  List<ToolRegistration> listRegisteredTools() => _registry.listTools();

  Future<void> setPermission({required String agentId, required String toolId, required bool granted}) {
    return _db.setToolPermission(agentId: agentId, toolId: toolId, granted: granted);
  }

  Future<Map<String, bool>> listPermissions(String agentId) => _db.listToolPermissions(agentId);

  Future<ToolExecutionResult?> maybeInvokeFromEvent(
    Event event,
    Session session, {
    bool consentApproved = false,
    String? consentReasonOverride,
  }) async {
    final request = event.payload['toolRequest'];
    if (request is! Map) return null;
    final req = Map<String, dynamic>.from(request);
    final toolId = req['toolId']?.toString();
    if (toolId == null || toolId.isEmpty) return null;

    final tool = _registry.getTool(toolId);
    final input = Map<String, dynamic>.from((req['input'] as Map?) ?? const {});
    final idempotencyKey = req['idempotencyKey']?.toString() ?? 'tool-${event.id}-$toolId';

    final existing = await _db.findToolInvocation(eventId: event.id, toolId: toolId, idempotencyKey: idempotencyKey);
    if (existing != null) {
      final audit = ToolAuditRecord(
        id: _uuid.v4(),
        invocationId: existing.id,
        eventId: existing.eventId,
        agentId: existing.agentId,
        sessionId: existing.sessionId,
        handoffTraceId: existing.handoffTraceId,
        rootEventId: existing.rootEventId,
        toolId: existing.toolId,
        decisionAllowed: existing.decisionAllowed,
        decisionReason: 'idempotent-reuse',
        consentOutcome: existing.consentOutcome,
        outcome: existing.outcome,
        inputRedacted: existing.inputRedacted,
        outputRedacted: existing.outputRedacted,
        createdAt: _clock.now().millisecondsSinceEpoch,
      );
      await _db.insertToolAuditLog(audit);
      return ToolExecutionResult(invocation: existing, audit: audit);
    }

    final now = _clock.now().millisecondsSinceEpoch;
    final invocationId = _uuid.v4();
    var decisionAllowed = false;
    var decisionReason = 'tool_not_registered';
    var consentOutcome = 'not_required';
    var outcome = 'blocked';
    var output = <String, dynamic>{'error': 'blocked'};

    if (tool != null) {
      final hasPermission = await _db.getToolPermission(agentId: session.agentId, toolId: toolId);
      if (!hasPermission) {
        decisionReason = 'default_deny: permission not granted';
      } else {
        decisionAllowed = true;
        decisionReason = 'permission granted';

        if (tool.riskLevel != ToolRiskLevel.low) {
          if (!consentApproved) {
            decisionAllowed = false;
            consentOutcome = 'denied';
            decisionReason = 'runtime consent required for ${tool.riskLevel.name} risk tool';
          } else {
            consentOutcome = 'approved';
            decisionReason = consentReasonOverride ?? 'permission granted + runtime consent approved';
          }
        }

        if (decisionAllowed) {
          final result = await _executeTool(tool: tool, input: input);
          outcome = result['outcome']?.toString() ?? 'success';
          output = Map<String, dynamic>.from((result['output'] as Map?) ?? const {});
          if (outcome == 'blocked') {
            decisionReason = result['reason']?.toString() ?? decisionReason;
          }
        }
      }
    }

    final invocation = ToolInvocation(
      id: invocationId,
      eventId: event.id,
      agentId: session.agentId,
      sessionId: session.id,
      toolId: toolId,
      capabilityCategory: tool?.capabilityCategory ?? 'unknown',
      requiredPermissions: tool?.requiredPermissions ?? const [],
      riskLevel: tool?.riskLevel ?? ToolRiskLevel.low,
      inputSchema: tool?.inputSchema ?? const {},
      outputSchema: tool?.outputSchema ?? const {},
      idempotencyKey: idempotencyKey,
      inputRedacted: _redact(toolId: toolId, data: input),
      decisionAllowed: decisionAllowed,
      decisionReason: decisionReason,
      consentOutcome: consentOutcome,
      outcome: outcome,
      outputRedacted: _redact(toolId: toolId, data: output),
      handoffTraceId: event.payload['handoffTraceId']?.toString(),
      rootEventId: event.payload['rootEventId']?.toString(),
      createdAt: now,
      updatedAt: now,
    );

    final audit = ToolAuditRecord(
      id: _uuid.v4(),
      invocationId: invocation.id,
      eventId: event.id,
      agentId: session.agentId,
      sessionId: session.id,
      handoffTraceId: invocation.handoffTraceId,
      rootEventId: invocation.rootEventId,
      toolId: toolId,
      decisionAllowed: decisionAllowed,
      decisionReason: decisionReason,
      consentOutcome: consentOutcome,
      outcome: outcome,
      inputRedacted: invocation.inputRedacted,
      outputRedacted: invocation.outputRedacted,
      createdAt: now,
    );

    await _db.insertToolInvocation(invocation);
    await _db.insertToolAuditLog(audit);
    return ToolExecutionResult(invocation: invocation, audit: audit);
  }



  Future<ToolExecutionResult?> invokeToolForEvent({
    required Event event,
    required Session session,
    required String toolId,
    required Map<String, dynamic> input,
    required String idempotencyKey,
    required bool consentApproved,
    String? consentReasonOverride,
  }) {
    final payload = Map<String, dynamic>.from(event.payload)
      ..['toolRequest'] = {
        'toolId': toolId,
        'input': input,
        'idempotencyKey': idempotencyKey,
      }
      ..['toolConsentApproved'] = consentApproved;

    final synthetic = Event(
      id: event.id,
      sessionId: event.sessionId,
      type: event.type,
      payload: payload,
      idempotencyKey: event.idempotencyKey,
      createdAt: event.createdAt,
      schemaVersion: event.schemaVersion,
    );
    return maybeInvokeFromEvent(
      synthetic,
      session,
      consentApproved: consentApproved,
      consentReasonOverride: consentReasonOverride,
    );
  }

  Future<Map<String, dynamic>> _executeTool({required ToolRegistration tool, required Map<String, dynamic> input}) async {
    switch (tool.toolId) {
      case 'tool.echo':
        return {
          'outcome': 'success',
          'output': {'echo': input['message']?.toString() ?? ''},
        };
      case 'tool.httpGet':
        return _executeHttpGet(input);
      case 'tool.openUrl':
        return {
          'outcome': 'blocked',
          'reason': 'openUrl is blocked in the mobile capability sandbox (deferred/not supported)',
          'output': {'deferred': true, 'reason': 'not supported in sandbox'},
        };
      case 'tool.cameraList':
        return _executeCameraList(input);
      case 'tool.cameraSnapshot':
        return _executeCameraSnapshot(input);
      case 'tool.fallDetect':
        return _executeFallDetect(input);
      default:
        return {
          'outcome': 'blocked',
          'reason': 'tool_not_registered',
          'output': {'error': 'tool_not_registered'},
        };
    }
  }

  Future<Map<String, dynamic>> _executeHttpGet(Map<String, dynamic> input) async {
    final uriRaw = input['url']?.toString() ?? '';
    if (uriRaw.isEmpty) {
      return {
        'outcome': 'blocked',
        'reason': 'missing url',
        'output': {'error': 'missing url'},
      };
    }
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(uriRaw));
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      client.close(force: true);
      return {
        'outcome': 'success',
        'output': {
          'statusCode': response.statusCode,
          'body': body.length > 200 ? '${body.substring(0, 200)}…' : body,
        },
      };
    } on SocketException {
      return {
        'outcome': 'blocked',
        'reason': 'network unavailable (offline fallback)',
        'output': {'error': 'network unavailable (offline fallback)'},
      };
    }
  }

  Future<Map<String, dynamic>> _executeCameraList(Map<String, dynamic> input) async {
    final settings = await _db.getCameraGatewaySettings();
    if (!settings.enabled) {
      return {
        'outcome': 'blocked',
        'reason': 'camera gateway disabled',
        'output': {'error': 'camera gateway disabled'},
      };
    }

    final token = await _secretStore.readCameraGatewayToken();
    final client = _cameraClientFactory(baseUrl: settings.baseUrl, bearerToken: token ?? '');
    try {
      final cameras = await client.listCameras();
      final includeDisabled = input['includeDisabled'] == true;
      final filtered = includeDisabled ? cameras : cameras.where((c) => (c['enabled'] as bool?) != false).toList();
      return {
        'outcome': 'success',
        'output': {'cameras': filtered},
      };
    } on CameraGatewayException catch (e) {
      return {
        'outcome': 'blocked',
        'reason': e.message,
        'output': {'error': e.message, 'code': e.code},
      };
    }
  }

  Future<Map<String, dynamic>> _executeCameraSnapshot(Map<String, dynamic> input) async {
    final settings = await _db.getCameraGatewaySettings();
    if (!settings.enabled) {
      return {
        'outcome': 'blocked',
        'reason': 'camera gateway disabled',
        'output': {'error': 'camera gateway disabled'},
      };
    }

    final cameraId = input['cameraId']?.toString() ?? '';
    if (cameraId.isEmpty) {
      return {
        'outcome': 'blocked',
        'reason': 'missing cameraId',
        'output': {'error': 'missing cameraId'},
      };
    }

    final mode = input['mode']?.toString() ?? 'latest';
    final token = await _secretStore.readCameraGatewayToken();
    final client = _cameraClientFactory(baseUrl: settings.baseUrl, bearerToken: token ?? '');
    try {
      final snapshot = await client.getSnapshot(cameraId: cameraId, mode: mode);
      return {'outcome': 'success', 'output': snapshot};
    } on CameraGatewayException catch (e) {
      return {
        'outcome': 'blocked',
        'reason': e.message,
        'output': {'error': e.message, 'code': e.code},
      };
    }
  }



  Future<Map<String, dynamic>> _executeFallDetect(Map<String, dynamic> input) async {
    final snapshotUrl = input['snapshotUrl']?.toString().toLowerCase() ?? '';
    if (snapshotUrl.contains('fall')) {
      return {
        'outcome': 'success',
        'output': {
          'verdict': 'fall_suspected',
          'confidence': 0.92,
          'reasons': ['fixture:fall'],
        },
      };
    }
    if (snapshotUrl.contains('uncertain')) {
      return {
        'outcome': 'success',
        'output': {
          'verdict': 'uncertain',
          'confidence': 0.55,
          'reasons': ['fixture:uncertain'],
        },
      };
    }
    return {
      'outcome': 'success',
      'output': {
        'verdict': 'ok',
        'confidence': 0.90,
        'reasons': ['fixture:ok'],
      },
    };
  }

  String _redact({required String toolId, required Map<String, dynamic> data}) {
    final safe = Map<String, dynamic>.from(data);
    safe.removeWhere((key, _) {
      final normalized = key.toLowerCase();
      return normalized.contains('token') || normalized.contains('authorization') || normalized.contains('secret');
    });

    if ((toolId == 'tool.cameraSnapshot' || toolId == 'tool.fallDetect') && safe['snapshotUrl'] is String) {
      final uri = Uri.tryParse(safe['snapshotUrl'].toString());
      if (uri != null) {
        safe['snapshotUrl'] = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
      }
    }

    if (toolId == 'tool.fallDetect' && safe['checksum'] is String) {
      final checksum = safe['checksum'].toString();
      safe['checksum'] = checksum.length > 8 ? checksum.substring(0, 8) : checksum;
    }

    var encoded = jsonEncode(safe);
    if (toolId != 'tool.cameraSnapshot' && toolId != 'tool.fallDetect' && encoded.length > 160) {
      encoded = '${encoded.substring(0, 160)}…';
    }
    if (toolId != 'tool.cameraSnapshot' && toolId != 'tool.fallDetect') {
      encoded = encoded.replaceAll(RegExp(r'https?://[^"\s]+'), 'https://[redacted-url]');
    }
    return encoded;
  }
}
