import '../domain/models.dart';

abstract class ToolRegistry {
  List<ToolRegistration> listTools();
  ToolRegistration? getTool(String toolId);
}

class DefaultToolRegistry implements ToolRegistry {
  @override
  List<ToolRegistration> listTools() => const [
    _echo,
    _httpGet,
    _openUrl,
  ];

  @override
  ToolRegistration? getTool(String toolId) {
    for (final tool in listTools()) {
      if (tool.toolId == toolId) return tool;
    }
    return null;
  }

  static const _echo = ToolRegistration(
    toolId: 'tool.echo',
    capabilityCategory: 'utility',
    requiredPermissions: ['tool.echo.execute'],
    riskLevel: ToolRiskLevel.low,
    inputSchema: {
      'type': 'object',
      'properties': {'message': {'type': 'string'}},
    },
    outputSchema: {
      'type': 'object',
      'properties': {'echo': {'type': 'string'}},
    },
  );

  static const _httpGet = ToolRegistration(
    toolId: 'tool.httpGet',
    capabilityCategory: 'network',
    requiredPermissions: ['tool.httpGet.network'],
    riskLevel: ToolRiskLevel.medium,
    inputSchema: {
      'type': 'object',
      'properties': {'url': {'type': 'string'}},
    },
    outputSchema: {
      'type': 'object',
      'properties': {'statusCode': {'type': 'number'}, 'body': {'type': 'string'}},
    },
  );

  static const _openUrl = ToolRegistration(
    toolId: 'tool.openUrl',
    capabilityCategory: 'system',
    requiredPermissions: ['tool.openUrl.external'],
    riskLevel: ToolRiskLevel.high,
    inputSchema: {
      'type': 'object',
      'properties': {'url': {'type': 'string'}},
    },
    outputSchema: {
      'type': 'object',
      'properties': {'deferred': {'type': 'boolean'}, 'reason': {'type': 'string'}},
    },
  );
}
