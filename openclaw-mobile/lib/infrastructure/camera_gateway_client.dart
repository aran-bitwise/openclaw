import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class CameraGatewayException implements Exception {
  CameraGatewayException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CameraGatewayException($code): $message';
}

class CameraGatewayClient {
  CameraGatewayClient({required this.baseUrl, required this.bearerToken, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final String bearerToken;
  final http.Client _client;

  Future<List<Map<String, dynamic>>> listCameras() async {
    final json = await _getJson('/cameras');
    final cameras = json['cameras'];
    if (cameras is! List) return const [];
    return cameras.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getSnapshot({required String cameraId, String mode = 'latest'}) {
    return _getJson('/cameras/$cameraId/snapshot?mode=$mode');
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    if (bearerToken.trim().isEmpty) {
      throw CameraGatewayException('unauthorized', 'unauthorized / check token');
    }

    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await _client
          .get(uri, headers: {'Authorization': 'Bearer $bearerToken'})
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 401) {
        throw CameraGatewayException('unauthorized', 'unauthorized / check token');
      }
      if (response.statusCode >= 400) {
        throw CameraGatewayException('http_error', 'gateway returned ${response.statusCode}');
      }
      final body = jsonDecode(response.body);
      if (body is! Map) {
        throw CameraGatewayException('invalid_response', 'gateway returned non-object response');
      }
      return Map<String, dynamic>.from(body);
    } on CameraGatewayException {
      rethrow;
    } on TimeoutException {
      throw CameraGatewayException('timeout', 'gateway request timed out');
    } on SocketException {
      throw CameraGatewayException('offline', 'network unavailable (offline fallback)');
    } on http.ClientException {
      throw CameraGatewayException('offline', 'network unavailable (offline fallback)');
    }
  }
}
