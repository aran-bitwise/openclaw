import { describe, expect, it } from "vitest";
import { createAgentProfile, Milestone2Repository } from "../flutter-m2/milestone2-reference.js";
import { Milestone3ChannelSessionService } from "../flutter-m3/channel-session-service-reference.js";
import { ApiRelayReference } from "./api-relay-reference.js";

describe("api relay reference", () => {
  it("accepts validated webhook events and rejects duplicates", () => {
    const relay = new ApiRelayReference();

    const first = relay.ingestWebhook({
      request: {
        source: { provider: "github", channelId: "webhook", conversationId: "repo-1" },
        target: { agentId: "main", deviceId: "device-a" },
        eventType: "webhook",
        payload: { action: "push" },
        idempotencyKey: "gh:1",
        receivedAt: 100,
      },
      validate: () => true,
    });
    const dup = relay.ingestWebhook({
      request: {
        source: { provider: "github", channelId: "webhook", conversationId: "repo-1" },
        target: { agentId: "main", deviceId: "device-a" },
        eventType: "webhook",
        payload: { action: "push" },
        idempotencyKey: "gh:1",
        receivedAt: 101,
      },
      validate: () => true,
    });

    expect(first.accepted).toBe(true);
    expect(dup).toEqual({ accepted: false, reason: "duplicate" });
    expect(relay.snapshot()).toHaveLength(1);
  });

  it("queues by device and delivers to mobile through milestone 3 service", async () => {
    const repo = new Milestone2Repository();
    repo.createAgent(createAgentProfile({ id: "main", name: "Main", now: 1 }));

    const service = new Milestone3ChannelSessionService(repo, {
      defaultAgentId: "main",
      processEvent: async () => {},
    });
    const relay = new ApiRelayReference();

    relay.ingestWebhook({
      request: {
        source: {
          provider: "github",
          channelId: "webhook",
          conversationId: "repo-1",
        },
        target: { agentId: "main", deviceId: "device-a", sessionHint: "repo-1" },
        eventType: "webhook",
        payload: { action: "opened" },
        idempotencyKey: "gh:2",
        receivedAt: 200,
      },
    });

    relay.ingestWebhook({
      request: {
        source: {
          provider: "slack",
          channelId: "slack",
          conversationId: "C123",
        },
        target: { agentId: "main", deviceId: "device-b" },
        eventType: "message",
        payload: { text: "ping" },
        idempotencyKey: "slack:1",
        receivedAt: 201,
      },
    });

    const delivered = await relay.deliverToMobile({
      deviceId: "device-a",
      service,
    });

    expect(delivered.delivered).toBe(1);
    expect(delivered.duplicates).toBe(0);

    const sessions = repo.listSessionsByAgent("main");
    expect(sessions).toHaveLength(1);
    const sessionId = sessions[0]?.id;
    expect(sessionId).toBeDefined();

    const timeline = service.listSessionTimeline(sessionId!);
    expect(timeline).toHaveLength(1);
    expect(timeline[0]?.type).toBe("webhook");
    expect(timeline[0]?.payload["relayProvider"]).toBe("github");

    const pendingB = relay.fetchPending({ deviceId: "device-b" });
    expect(pendingB.items).toHaveLength(1);
    expect(pendingB.items[0]?.status).toBe("pending");
  });
});
