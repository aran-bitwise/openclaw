import { describe, expect, it } from "vitest";
import { buildSessionKey } from "../flutter-m2/milestone2-reference.js";
import { Milestone3GatewayRouter } from "./gateway-router-reference.js";

describe("milestone 3 gateway router reference", () => {
  it("applies route precedence sessionHint > threadId > conversationId > main", () => {
    const router = new Milestone3GatewayRouter("default-agent");

    const withHint = router.resolveRoute({
      source: { channelId: "Telegram", conversationId: "conv-1", threadId: "thread-1" },
      target: { agentId: "agent-a", sessionHint: "hint-1" },
      eventType: "message",
      payload: {},
      receivedAt: 1,
    });
    expect(withHint.sessionKey).toBe(
      buildSessionKey({ agentId: "agent-a", channelId: "telegram", sessionHint: "hint-1" }),
    );

    const withThread = router.resolveRoute({
      source: { channelId: "Telegram", conversationId: "conv-1", threadId: "thread-1" },
      eventType: "message",
      payload: {},
      receivedAt: 1,
    });
    expect(withThread.sessionKey).toBe(
      buildSessionKey({ agentId: "default-agent", channelId: "telegram", sessionHint: "thread-1" }),
    );

    const withConversation = router.resolveRoute({
      source: { channelId: "Telegram", conversationId: "conv-1" },
      eventType: "message",
      payload: {},
      receivedAt: 1,
    });
    expect(withConversation.sessionKey).toBe(
      buildSessionKey({ agentId: "default-agent", channelId: "telegram", sessionHint: "conv-1" }),
    );

    const fallback = router.resolveRoute({
      source: { channelId: "Telegram" },
      eventType: "message",
      payload: {},
      receivedAt: 1,
    });
    expect(fallback.sessionKey).toBe(
      buildSessionKey({ agentId: "default-agent", channelId: "telegram", sessionHint: "main" }),
    );
  });

  it("bridges to milestone 1 normalization using deterministic route identity", () => {
    const router = new Milestone3GatewayRouter("agent-x");
    const normalized = router.normalizeWithMilestone1({
      envelope: {
        source: {
          channelId: "Webhook",
          conversationId: "gh-42",
        },
        eventType: "internalHook",
        payload: { action: "startup" },
        idempotencyKey: "idemp-1",
        receivedAt: 1700,
      },
      makeId: () => "evt-1",
    });

    expect(normalized.id).toBe("evt-1");
    expect(normalized.inputType).toBe("internal-hook");
    expect(normalized.channelId).toBe("webhook");
    expect(normalized.agentId).toBe("agent-x");
    expect(normalized.sessionId).toBe("agent:agent-x:webhook:gh-42");
    expect(normalized.idempotencyKey).toBe("idemp-1");
  });
});
