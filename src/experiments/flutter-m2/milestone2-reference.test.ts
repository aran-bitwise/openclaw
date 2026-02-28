import { describe, expect, it } from "vitest";
import {
  Milestone2Repository,
  buildSessionKey,
  createAgentProfile,
  createEmptyStore,
  createEvent,
  createSession,
  deserializeStore,
  migrateStore,
  serializeStore,
  type Milestone2StoreV2,
} from "./milestone2-reference.js";

describe("flutter milestone 2 reference", () => {
  it("supports agent/session/event CRUD with session key alignment", () => {
    const repo = new Milestone2Repository();

    const agent = repo.createAgent(
      createAgentProfile({
        id: "agent-main",
        name: "Main Agent",
        defaultModel: "gpt-5",
        now: 100,
      }),
    );

    const session = repo.createSession(
      createSession({
        id: "session-1",
        agentId: agent.id,
        channelId: "telegram",
        sessionKey: buildSessionKey({
          agentId: agent.id,
          channelId: "telegram",
          sessionHint: "chat-123",
        }),
        now: 200,
      }),
    );

    const event = repo.appendEvent(
      createEvent({
        id: "event-1",
        sessionId: session.id,
        type: "message",
        source: "telegram",
        payload: { text: "hello" },
        idempotencyKey: "telegram:msg:1",
        now: 300,
      }),
    );

    expect(session.sessionKey).toBe("agent:agent-main:telegram:chat-123");
    expect(event.status).toBe("queued");
    expect(repo.listAgents()).toHaveLength(1);
    expect(repo.listSessionsByAgent(agent.id)).toHaveLength(1);
  });

  it("migrates schema v1 to v2 and preserves existing records", () => {
    const v1 = {
      schemaVersion: 1 as const,
      agents: [
        createAgentProfile({
          id: "agent-1",
          name: "Legacy",
          now: 10,
        }),
      ],
      sessions: [
        {
          id: "session-legacy",
          agentId: "agent-1",
          channelId: "webhook",
          sessionKey: "agent:agent-1:webhook:legacy",
          createdAt: 11,
          updatedAt: 11,
        },
      ],
      events: [],
      memoryEntries: [],
      toolInvocations: [],
      runResults: [],
    };

    const v2 = migrateStore(v1);
    expect(v2.schemaVersion).toBe(2);
    expect(v2.sessions[0]?.accountId).toBeUndefined();
    expect(v2.sessions[0]?.threadId).toBeUndefined();
    expect(v2.sessions[0]?.sessionKey).toBe("agent:agent-1:webhook:legacy");
  });

  it("round-trips export/import and rejects duplicate idempotency", () => {
    const repo = new Milestone2Repository();
    repo.createAgent(createAgentProfile({ id: "a", name: "A", now: 1 }));
    repo.createSession(
      createSession({
        id: "s",
        agentId: "a",
        channelId: "signal",
        sessionKey: "agent:a:signal:main",
        now: 2,
      }),
    );

    repo.appendEvent(
      createEvent({
        id: "e1",
        sessionId: "s",
        type: "heartbeat",
        source: "system",
        idempotencyKey: "heartbeat:1",
        now: 3,
      }),
    );

    expect(() =>
      repo.appendEvent(
        createEvent({
          id: "e2",
          sessionId: "s",
          type: "heartbeat",
          source: "system",
          idempotencyKey: "heartbeat:1",
          now: 4,
        }),
      ),
    ).toThrow(/Duplicate idempotencyKey/);

    const exported = repo.exportJson();
    const parsed = deserializeStore(exported);
    expect(parsed.schemaVersion).toBe(2);
    expect(parsed.events).toHaveLength(1);
  });

  it("loads from empty schema and keeps v2 shape", () => {
    const empty = createEmptyStore();
    const json = serializeStore(empty);
    const roundTripped: Milestone2StoreV2 = deserializeStore(json);
    expect(roundTripped).toEqual(empty);
  });
});
