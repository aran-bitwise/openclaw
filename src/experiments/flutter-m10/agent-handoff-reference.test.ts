import { describe, expect, it } from "vitest";
import { AgentHandoffReference } from "./agent-handoff-reference.js";

describe("agent handoff reference", () => {
  it("enforces allowlisted agent routes", () => {
    const handoff = new AgentHandoffReference();
    expect(
      handoff.createHandoff({
        fromAgentId: "research",
        toAgentId: "writer",
        taskPayload: { topic: "status" },
      }),
    ).toBeUndefined();

    handoff.allowRoute("research", "writer");

    expect(
      handoff.createHandoff({
        fromAgentId: "research",
        toAgentId: "writer",
        taskPayload: { topic: "status" },
        traceId: "trace-1",
      })?.traceId,
    ).toBe("trace-1");
  });
});
