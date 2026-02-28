import '../domain/models.dart';

class InboundEnvelope {
  InboundEnvelope({
    required this.channelId,
    required this.agentId,
    required this.sessionId,
    required this.eventType,
    required this.idempotencyKey,
    required this.payload,
  });

  final String channelId;
  final String agentId;
  final String sessionId;
  final EventType eventType;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
}

class GatewayRoute {
  GatewayRoute({required this.agentId, required this.channelId, required this.sessionId});

  final String agentId;
  final String channelId;
  final String sessionId;
}

class GatewayRouter {
  GatewayRoute resolve(InboundEnvelope envelope) {
    return GatewayRoute(
      agentId: envelope.agentId,
      channelId: envelope.channelId,
      sessionId: envelope.sessionId,
    );
  }
}
