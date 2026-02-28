import 'dart:convert';

import '../domain/models.dart';
import '../infrastructure/app_database.dart';
import 'clock.dart';
import 'tooling_service.dart';

class SafetyCameraFinding {
  SafetyCameraFinding({
    required this.cameraId,
    required this.verdict,
    required this.confidence,
    required this.capturedAt,
    required this.checksumPrefix,
  });

  final String cameraId;
  final String verdict;
  final double confidence;
  final String capturedAt;
  final String checksumPrefix;

  Map<String, dynamic> toJson() => {
    'cameraId': cameraId,
    'verdict': verdict,
    'confidence': confidence,
    'capturedAt': capturedAt,
    'checksumPrefix': checksumPrefix,
  };
}

class SafetyCheckOutcome {
  SafetyCheckOutcome({required this.overallVerdict, required this.findings, required this.summary});

  final String overallVerdict;
  final List<SafetyCameraFinding> findings;
  final String summary;

  String toMemoryContent({required DateTime at}) {
    return jsonEncode({
      'kind': 'safety-check',
      'at': at.toIso8601String(),
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
    required bool consentApproved,
    String? modeOverride,
  }) async {
    final cameras = (await _db.listConfiguredCameras()).where((c) => c.enabled).toList();
    if (cameras.isEmpty) {
      return SafetyCheckOutcome(overallVerdict: 'uncertain', findings: const [], summary: 'Safety Check Summary: no enabled cameras configured');
    }

    final findings = <SafetyCameraFinding>[];
    final mode = modeOverride ?? event.payload['modeOverride']?.toString() ?? 'latest';
    for (final camera in cameras) {
      final snapshotResult = await _tooling.invokeToolForEvent(
        event: event,
        session: session,
        toolId: 'tool.cameraSnapshot',
        input: {'cameraId': camera.cameraId, 'mode': mode},
        idempotencyKey: 'safety-${event.id}-${camera.cameraId}-snapshot',
        consentApproved: consentApproved,
      );
      if (snapshotResult == null || !snapshotResult.invocation.decisionAllowed || snapshotResult.invocation.outcome != 'success') {
        findings.add(
          SafetyCameraFinding(
            cameraId: camera.cameraId,
            verdict: 'uncertain',
            confidence: 0.0,
            capturedAt: _clock.now().toIso8601String(),
            checksumPrefix: '',
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
        input: {
          'snapshotUrl': snapshotUrl,
          'cameraId': camera.cameraId,
          if (checksum.isNotEmpty) 'checksum': checksum,
        },
        idempotencyKey: 'safety-${event.id}-${camera.cameraId}-detect',
        consentApproved: consentApproved,
      );

      final detectOutput = detectResult == null
          ? <String, dynamic>{'verdict': 'uncertain', 'confidence': 0.0}
          : Map<String, dynamic>.from(jsonDecode(detectResult.invocation.outputRedacted) as Map);

      findings.add(
        SafetyCameraFinding(
          cameraId: camera.cameraId,
          verdict: detectOutput['verdict']?.toString() ?? 'uncertain',
          confidence: (detectOutput['confidence'] as num?)?.toDouble() ?? 0,
          capturedAt: snapshot['capturedAt']?.toString() ?? _clock.now().toIso8601String(),
          checksumPrefix: checksum.length > 8 ? checksum.substring(0, 8) : checksum,
        ),
      );
    }

    final hasFall = findings.any((f) => f.verdict == 'fall_suspected');
    final hasUncertain = findings.any((f) => f.verdict == 'uncertain');
    final overall = hasFall
        ? 'fall_suspected'
        : hasUncertain
            ? 'uncertain'
            : 'ok';
    final summary = 'Safety Check Summary: overall=$overall, cameras=${findings.map((f) => '${f.cameraId}:${f.verdict}').join(', ')}';
    return SafetyCheckOutcome(overallVerdict: overall, findings: findings, summary: summary);
  }
}
