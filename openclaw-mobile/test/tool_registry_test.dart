import 'package:test/test.dart';

import '../lib/application/tool_registry.dart';
import '../lib/domain/models.dart';

void main() {
  test('registers camera tools with expected permissions and risks', () {
    final registry = DefaultToolRegistry();
    final listTool = registry.getTool('tool.cameraList');
    final snapshotTool = registry.getTool('tool.cameraSnapshot');

    expect(listTool, isNotNull);
    expect(listTool!.riskLevel, ToolRiskLevel.low);
    expect(listTool.requiredPermissions, ['camera:list']);

    expect(snapshotTool, isNotNull);
    expect(snapshotTool!.riskLevel, ToolRiskLevel.medium);
    expect(snapshotTool.requiredPermissions, ['camera:read']);
  });
}
