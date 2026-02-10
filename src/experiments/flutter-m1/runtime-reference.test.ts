import { describe, expect, it } from "vitest";
import {
  Milestone1GatewayRouter,
  Milestone1Queue,
  normalizeMilestone1Event,
  runMilestone1ProcessingLoop,
  type Milestone1InputType,
} from "./runtime-reference.js";

const ALL_INPUT_TYPES: Milestone1InputType[] = [
  "message",
  "heartbeat",
  "cron",
  "internal-hook",
  "webhook",
];

describe("flutter milestone 1 runtime reference", () => {
  it("normalizes all five input types through routing into queued events", () => {
    const router = new Milestone1GatewayRouter();
    const queue = new Milestone1Queue();

    for (const inputType of ALL_INPUT_TYPES) {
      const normalized = normalizeMilestone1Event({
        envelope: {
          inputType,
          source: { channelId: "telegram", conversationId: "chat-1" },
          target: { agentId: "planner", sessionHint: inputType },
          payload: { text: `from:${inputType}` },
          idempotencyKey: `${inputType}-1`,
        },
        router,
        now: () => 1000,
        makeId: () => `event-${inputType}`,
      });

      const result = queue.enqueue(normalized);
      expect(result.accepted).toBe(true);
      expect(result.event?.status).toBe("queued");
      expect(result.event?.sessionId).toContain("agent:planner:telegram");
    }

    const snapshot = queue.snapshot();
    expect(snapshot).toHaveLength(5);
    expect(snapshot.map((event) => event.inputType)).toEqual(ALL_INPUT_TYPES);
  });

  it("rejects duplicates by idempotency key", () => {
    const router = new Milestone1GatewayRouter();
    const queue = new Milestone1Queue();

    const event = normalizeMilestone1Event({
      envelope: {
        inputType: "webhook",
        source: { channelId: "webhook", conversationId: "gh-123" },
        target: { agentId: "planner" },
        payload: { action: "push" },
        idempotencyKey: "dup-key",
      },
      router,
      now: () => 10,
      makeId: () => "evt-1",
    });

    expect(queue.enqueue(event).accepted).toBe(true);
    expect(queue.enqueue({ ...event, id: "evt-2" }).accepted).toBe(false);
    expect(queue.snapshot()).toHaveLength(1);
  });

  it("runs processing loop and marks success/failure states", async () => {
    const router = new Milestone1GatewayRouter();
    const queue = new Milestone1Queue();

    const okEvent = normalizeMilestone1Event({
      envelope: {
        inputType: "message",
        source: { channelId: "telegram", conversationId: "chat-a" },
        target: { agentId: "main" },
        payload: { text: "ok" },
      },
      router,
      now: () => 1,
      makeId: () => "ok-1",
    });

    const failEvent = normalizeMilestone1Event({
      envelope: {
        inputType: "cron",
        source: { channelId: "cron", conversationId: "job-a" },
        target: { agentId: "main" },
        payload: { text: "fail" },
      },
      router,
      now: () => 2,
      makeId: () => "fail-1",
    });

    queue.enqueue(okEvent);
    queue.enqueue(failEvent);

    const processed = await runMilestone1ProcessingLoop({
      queue,
      process: async (event) => {
        if (event.id === "fail-1") {
          throw new Error("simulated failure");
        }
      },
    });

    expect(processed).toBe(2);

    const byId = Object.fromEntries(queue.snapshot().map((event) => [event.id, event]));
    expect(byId["ok-1"]?.status).toBe("completed");
    expect(byId["fail-1"]?.status).toBe("failed");
    expect(byId["fail-1"]?.error).toBe("simulated failure");
  });
});
