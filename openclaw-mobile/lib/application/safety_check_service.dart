import 'dart:convert';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'clock.dart';
import 'tooling_service.dart';

class SafetyCameraFinding {
  SafetyCameraFinding({
    required this.cameraId,
    required this.status,
    required this.verdict,
    required this.confidence,
    required this.capturedAt,
    required this.checksumPrefix,
    this.errorType,
    this.errorMessage,
  });

  final String cameraId;
  final String status; // ok|uncertain|fall_suspected|error
  final String verdict;
  final double confidence;
  final String capturedAt;
  final String checksumPrefix;
  final String? errorType;
  final String? errorMessage;

  Map<String, dynamic> toJson() => {
    'cameraId': cameraId,
    'status': status,
    'verdict': verdict,
    'confidence': confidence,
    'capturedAt': capturedAt,
    'checksumPrefix': checksumPrefix,
    'errorType': errorType,
    'errorMessage': errorMessage,
  };
}

class SafetyCheckOutcome {
  SafetyCheckOutcome({
    required this.checkId,
    required this.overallVerdict,
    required this.findings,
    required this.summary,
    this.blockedAwaitingConsent = false,
    this.blockedReason,
    this.autoConsentUsed = false,
  });

  final String checkId;
  final String overallVerdict;
  final List<SafetyCameraFinding> findings;
  final String summary;
  final bool blockedAwaitingConsent;
  final String? blockedReason;
  final bool autoConsentUsed;

  String toMemoryContent({required DateTime at, required String mode, required bool scheduled}) {
    return jsonEncode({
      'kind': 'safety-check',
      'checkId': checkId,
      'at': at.toIso8601String(),
      'scheduled': scheduled,
      'mode': mode,
      'autoConsentUsed': autoConsentUsed,
      'blockedAwaitingConsent': blockedAwaitingConsent,
      'blockedReason': blockedReason,
      'overallVerdict': overallVerdict,
      'findings': findings.map((f) => f.toJson()).toList(),
      'summary': summary,
    });
  }
}

class SafetyCheckService {
  SafetyCheckService(this._db, this._tooling, this._clock);

  final AppDatabase _db;
  final ToolingService _tooling;
  final Clock _clock;

  Future<SafetyCheckOutcome> runSafetyCheck({
    required Event event,
    required Session session,
  }) async {
    final cameras = (await _db.listConfiguredCameras()).where((c) => c.enabled).toList();
    final scheduled = event.payload['trigger']?.toString() != 'manual';
    final mode = event.payload['modeOverride']?.toString() ?? 'latest';
    final checkId = _resolveCheckId(event, mode: mode);
    final agent = await _db.getAgent(session.agentId);
    final autoConsentEnabled = agent?.safety.safetyCheckAutoConsentEnabled == true;
    final manualConsentApproved = event.payload['toolConsentApproved'] == true;
    final consentApproved = manualConsentApproved || (scheduled && autoConsentEnabled);

    if (scheduled && !autoConsentEnabled) {
      return SafetyCheckOutcome(
        checkId: checkId,
        overallVerdict: 'uncertain',
        findings: const [],
        blockedAwaitingConsent: true,
        blockedReason: 'BLOCKED_AWAITING_CONSENT: enable auto-consent or run manually with consent',
        summary: 'Safety Check Summary: BLOCKED_AWAITING_CONSENT (checkId=$checkId)',
      );
    }

    if (cameras.isEmpty) {
      return SafetyCheckOutcome(
        checkId: checkId,
        overallVerdict: 'uncertain',
        findings: const [],
        autoConsentUsed: scheduled && autoConsentEnabled,
        summary: 'Safety Check Summary: no enabled cameras configured (checkId=$checkId)',
      );
    }

    final findings = <SafetyCameraFinding>[];
    for (final camera in cameras) {
      final snapshotResult = await _tooling.invokeToolForEvent(
        event: event,
        session: session,
        toolId: 'tool.cameraSnapshot',
        input: {'cameraId': camera.cameraId, 'mode': mode},
        idempotencyKey: 'safety:$checkId:${camera.cameraId}:snapshot',
        consentApproved: consentApproved,
        consentReasonOverride: scheduled && autoConsentEnabled ? 'auto_approved_by_setting' : null,
      );

      if (snapshotResult == null || snapshotResult.invocation.outcome != 'success' || !snapshotResult.invocation.decisionAllowed) {
        findings.add(
          SafetyCameraFinding(
            cameraId: camera.cameraId,
            status: 'error',
            verdict: 'uncertain',
            confidence: 0,
            capturedAt: _clock.now().toIso8601String(),
            checksumPrefix: '',
            errorType: _errorTypeFromJson(snapshotResult?.invocation.outputRedacted),
            errorMessage: _safeErrorMessage(snapshotResult?.invocation.outputRedacted),
          ),
        );
        continue;
      }

      final snapshot = jsonDecode(snapshotResult.invocation.outputRedacted) as Map<String, dynamic>;
      final snapshotUrl = snapshot['snapshotUrl']?.toString() ?? '';
      final checksum = snapshot['checksum']?.toString() ?? '';

      final detectResult = await _tooling.invokeToolForEvent(
        event: event,
        session: session,
        toolId: 'tool.fallDetect',
        input: {'snapshotUrl': snapshotUrl, 'cameraId': camera.cameraId, if (checksum.isNotEmpty) 'checksum': checksum},
        idempotencyKey: 'safety:$checkId:${camera.cameraId}:detect',
        consentApproved: consentApproved,
        consentReasonOverride: scheduled && autoConsentEnabled ? 'auto_approved_by_setting' : null,
      );

      if (detectResult == null || detectResult.invocation.outcome != 'success' || !detectResult.invocation.decisionAllowed) {
        findings.add(
          SafetyCameraFinding(
            cameraId: camera.cameraId,
            status: 'error',
            verdict: 'uncertain',
            confidence: 0,
            capturedAt: snapshot['capturedAt']?.toString() ?? _clock.now().toIso8601String(),
            checksumPrefix: checksum.length > 8 ? checksum.substring(0, 8) : checksum,
            errorType: _errorTypeFromJson(detectResult?.invocation.outputRedacted),
            errorMessage: _safeErrorMessage(detectResult?.invocation.outputRedacted),
          ),
        );
        continue;
      }

      final detect = jsonDecode(detectResult.invocation.outputRedacted) as Map<String, dynamic>;
      final verdict = detect['verdict']?.toString() ?? 'uncertain';
      findings.add(
        SafetyCameraFinding(
          cameraId: camera.cameraId,
          status: verdict,
          verdict: verdict,
          confidence: (detect['confidence'] as num?)?.toDouble() ?? 0,
          capturedAt: snapshot['capturedAt']?.toString() ?? _clock.now().toIso8601String(),
          checksumPrefix: checksum.length > 8 ? checksum.substring(0, 8) : checksum,
        ),
      );
    }

    final hasFall = findings.any((f) => f.status == 'fall_suspected');
    final hasUncertain = findings.any((f) => f.status == 'uncertain');
    final hasErrors = findings.any((f) => f.status == 'error');
    final overall = hasFall
        ? 'fall_suspected'
        : (hasUncertain || hasErrors)
            ? 'uncertain'
            : 'ok';
    final errorSummary = findings.where((f) => f.status == 'error').map((f) => '${f.cameraId}:${f.errorType ?? 'unknown'}').join(', ');
    final summary = 'Safety Check Summary: overall=$overall, checkId=$checkId, cameras=${findings.map((f) => '${f.cameraId}:${f.status}').join(', ')}${errorSummary.isEmpty ? '' : ', errors=$errorSummary'}';

    return SafetyCheckOutcome(
      checkId: checkId,
      overallVerdict: overall,
      findings: findings,
      summary: summary,
      autoConsentUsed: scheduled && autoConsentEnabled,
    );
  }

  String _resolveCheckId(Event event, {required String mode}) {
    final existing = event.payload['checkId']?.toString();
    if (existing != null && existing.isNotEmpty) return existing;
    final scheduleId = event.payload['scheduleId']?.toString() ?? 'manual';
    final dueAt = int.tryParse(event.payload['dueAt']?.toString() ?? '') ?? event.createdAt;
    final bucket = dueAt ~/ 60000;
    return 'check:$scheduleId:$mode:$bucket';
  }

  String _errorTypeFromJson(String? outputRedacted) {
    if (outputRedacted == null || outputRedacted.isEmpty) return 'unknown';
    try {
      final map = Map<String, dynamic>.from(jsonDecode(outputRedacted) as Map);
      return map['code']?.toString() ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  String _safeErrorMessage(String? outputRedacted) {
    if (outputRedacted == null || outputRedacted.isEmpty) return 'operation failed';
    try {
      final map = Map<String, dynamic>.from(jsonDecode(outputRedacted) as Map);
      final message = map['error']?.toString() ?? 'operation failed';
      return message.length > 120 ? '${message.substring(0, 120)}…' : message;
    } catch (_) {
      return 'operation failed';
    }
  }
}
