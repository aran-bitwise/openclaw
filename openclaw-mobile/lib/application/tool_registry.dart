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
    _cameraList,
    _cameraSnapshot,
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

  static const _cameraList = ToolRegistration(
    toolId: 'tool.cameraList',
    capabilityCategory: 'camera',
    requiredPermissions: ['camera:list'],
    riskLevel: ToolRiskLevel.low,
    inputSchema: {
      'type': 'object',
      'properties': {'includeDisabled': {'type': 'boolean'}},
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'cameras': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'cameraId': {'type': 'string'},
              'name': {'type': 'string'},
              'location': {'type': 'string'},
              'status': {'type': 'string'},
              'enabled': {'type': 'boolean'},
            },
          },
        },
      },
    },
  );

  static const _cameraSnapshot = ToolRegistration(
    toolId: 'tool.cameraSnapshot',
    capabilityCategory: 'camera',
    requiredPermissions: ['camera:read'],
    riskLevel: ToolRiskLevel.medium,
    inputSchema: {
      'type': 'object',
      'properties': {
        'cameraId': {'type': 'string'},
        'mode': {
          'type': 'string',
          'enum': ['latest', 'test_ok', 'test_fall', 'test_uncertain'],
        },
      },
      'required': ['cameraId'],
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'cameraId': {'type': 'string'},
        'capturedAt': {'type': 'string'},
        'snapshotUrl': {'type': 'string'},
        'checksum': {'type': 'string'},
        'quality': {'type': 'object'},
        'mode': {'type': 'string'},
      },
    },
  );
}
