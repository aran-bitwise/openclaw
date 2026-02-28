import { describe, expect, it } from "vitest";
import { ToolRegistryReference } from "./tool-registry-reference.js";

describe("tool registry reference", () => {
  it("blocks invocation until permissions are granted", () => {
    const registry = new ToolRegistryReference();
    registry.registerTool({
      toolId: "calendar.create",
      riskLevel: "medium",
      requiredPermissions: ["calendar.write"],
    });

    expect(registry.canInvoke("calendar.create")).toEqual({
      allowed: false,
      reason: "missing-permission",
    });

    registry.grant("calendar.write");
    expect(registry.canInvoke("calendar.create")).toEqual({ allowed: true });
  });
});
