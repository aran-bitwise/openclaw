export type ToolRisk = "low" | "medium" | "high";

export type ToolDefinition = {
  toolId: string;
  riskLevel: ToolRisk;
  requiredPermissions: string[];
};

export class ToolRegistryReference {
  private readonly tools = new Map<string, ToolDefinition>();
  private readonly grants = new Set<string>();

  registerTool(def: ToolDefinition): void {
    this.tools.set(def.toolId, {
      ...def,
      requiredPermissions: [...def.requiredPermissions],
    });
  }

  grant(permission: string): void {
    this.grants.add(permission);
  }

  canInvoke(toolId: string): {
    allowed: boolean;
    reason?: "missing-tool" | "missing-permission";
  } {
    const tool = this.tools.get(toolId);
    if (!tool) {
      return { allowed: false, reason: "missing-tool" };
    }

    const missing = tool.requiredPermissions.find((perm) => !this.grants.has(perm));
    if (missing) {
      return { allowed: false, reason: "missing-permission" };
    }

    return { allowed: true };
  }
}
