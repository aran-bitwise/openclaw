import 'dart:convert';

import 'package:http/http.dart' as http;

class RelayEventEnvelope {
  RelayEventEnvelope({
    required this.relayEventId,
    required this.receivedAt,
    required this.source,
    required this.idempotencyKey,
    required this.agentId,
    required this.channelId,
    required this.sessionId,
    required this.payload,
  });

  final String relayEventId;
  final int receivedAt;
  final String source;
  final String idempotencyKey;
  final String agentId;
  final String channelId;
  final String sessionId;
  final Map<String, dynamic> payload;

  factory RelayEventEnvelope.fromJson(Map<String, dynamic> json) => RelayEventEnvelope(
    relayEventId: json['relayEventId'] as String,
    receivedAt: json['receivedAt'] as int,
    source: json['source'] as String,
    idempotencyKey: json['idempotencyKey'] as String,
    agentId: json['agentId'] as String,
    channelId: json['channelId'] as String,
    sessionId: json['sessionId'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
  );
}

abstract class RelayClient {
  Future<List<RelayEventEnvelope>> fetchPendingEvents({required int sinceMs, int limit = 50});
  Future<void> ackEvent(String relayEventId);
}

class HttpRelayClient implements RelayClient {
  HttpRelayClient({required this.baseUrl, required this.bearerToken, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final String bearerToken;
  final http.Client _client;

  Map<String, String> get _headers => {
    'authorization': 'Bearer $bearerToken',
    'content-type': 'application/json',
  };

  @override
  Future<List<RelayEventEnvelope>> fetchPendingEvents({required int sinceMs, int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/events/pending?since=$sinceMs&limit=$limit');
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw StateError('relay pending fetch failed: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final events = List<Map<String, dynamic>>.from(body['events'] as List? ?? const []);
    return events.map(RelayEventEnvelope.fromJson).toList();
  }

  @override
  Future<void> ackEvent(String relayEventId) async {
    final uri = Uri.parse('$baseUrl/events/$relayEventId/ack');
    final response = await _client.post(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw StateError('relay ack failed: ${response.statusCode}');
    }
  }
}
