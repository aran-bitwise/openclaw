import { describe, expect, it } from "vitest";
import { createAgentProfile, Milestone2Repository } from "../flutter-m2/milestone2-reference.js";
import { Milestone3ChannelSessionService } from "./channel-session-service-reference.js";

describe("milestone 3 channel session service reference", () => {
  it("creates sessions on demand, stores timelines, and dedupes by idempotency", async () => {
    const repo = new Milestone2Repository();
    repo.createAgent(createAgentProfile({ id: "main", name: "Main", now: 1 }));

    const service = new Milestone3ChannelSessionService(repo, {
      defaultAgentId: "main",
      processEvent: async () => {},
    });

    const first = await service.ingestInboundEvent({
      source: { channelId: "telegram", conversationId: "chat-1" },
      eventType: "message",
      payload: { text: "hello" },
      idempotencyKey: "tg-1",
      receivedAt: 100,
    });

    const duplicate = await service.ingestInboundEvent({
      source: { channelId: "telegram", conversationId: "chat-1" },
      eventType: "message",
      payload: { text: "hello again" },
      idempotencyKey: "tg-1",
      receivedAt: 101,
    });

    await service.waitForIdle();

    expect(first.accepted).toBe(true);
    expect(duplicate.accepted).toBe(false);

    if (first.accepted) {
      const timeline = service.listSessionTimeline(first.session.id);
      expect(timeline).toHaveLength(1);
      expect(timeline[0]?.type).toBe("message");
      expect(service.getEventRuntimeStatus(first.event.id)).toBe("completed");
    }
  });

  it("enforces no interleaving within a session while allowing cross-session progress", async () => {
    const repo = new Milestone2Repository();
    repo.createAgent(createAgentProfile({ id: "main", name: "Main", now: 1 }));

    const activeBySession = new Map<string, number>();
    const maxBySession = new Map<string, number>();
    const executionOrder: string[] = [];

    const service = new Milestone3ChannelSessionService(repo, {
      defaultAgentId: "main",
      processEvent: async (event) => {
        const sessionId = event.sessionId;
        const next = (activeBySession.get(sessionId) ?? 0) + 1;
        activeBySession.set(sessionId, next);
        maxBySession.set(sessionId, Math.max(maxBySession.get(sessionId) ?? 0, next));

        executionOrder.push(event.id);
        await new Promise((resolve) => setTimeout(resolve, 5));

        activeBySession.set(sessionId, (activeBySession.get(sessionId) ?? 1) - 1);
      },
    });

    const r1 = await service.ingestInboundEvent({
      source: { channelId: "telegram", conversationId: "chat-1" },
      eventType: "message",
      payload: { text: "A" },
      idempotencyKey: "a-1",
      receivedAt: 10,
    });
    const r2 = await service.ingestInboundEvent({
      source: { channelId: "telegram", conversationId: "chat-1" },
      eventType: "message",
      payload: { text: "B" },
      idempotencyKey: "a-2",
      receivedAt: 11,
    });
    const r3 = await service.ingestInboundEvent({
      source: { channelId: "telegram", conversationId: "chat-2" },
      eventType: "message",
      payload: { text: "C" },
      idempotencyKey: "b-1",
      receivedAt: 12,
    });

    await service.waitForIdle();

    expect(r1.accepted && r2.accepted && r3.accepted).toBe(true);

    if (r1.accepted && r2.accepted) {
      expect(r1.session.id).toBe(r2.session.id);
      expect(maxBySession.get(r1.session.id)).toBe(1);
    }

    if (r3.accepted) {
      const inbox = service.listChannelInbox("telegram");
      expect(inbox).toHaveLength(2);
      expect(inbox.map((row) => row.sessionId).toSorted()).toContain(r3.session.id);
    }

    expect(executionOrder).toHaveLength(3);
  });
});
