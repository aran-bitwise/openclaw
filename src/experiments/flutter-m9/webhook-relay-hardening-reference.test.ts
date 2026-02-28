import { describe, expect, it } from "vitest";
import { ApiRelayReference } from "../flutter-relay/api-relay-reference.js";
import { WebhookRelayHardeningReference } from "./webhook-relay-hardening-reference.js";

describe("webhook relay hardening reference", () => {
  it("enforces validation and rate-limit policy before ingest", () => {
    const relay = new ApiRelayReference();
    const hardening = new WebhookRelayHardeningReference(relay, 1);

    const first = hardening.ingestWithPolicy({
      request: {
        source: { provider: "github", channelId: "webhook" },
        target: { agentId: "main", deviceId: "device-a" },
        eventType: "webhook",
        payload: { action: "opened" },
        idempotencyKey: "gh:1",
        receivedAt: 1,
      },
      validateSignature: () => true,
    });

    const second = hardening.ingestWithPolicy({
      request: {
        source: { provider: "github", channelId: "webhook" },
        target: { agentId: "main", deviceId: "device-a" },
        eventType: "webhook",
        payload: { action: "closed" },
        idempotencyKey: "gh:2",
        receivedAt: 2,
      },
      validateSignature: () => true,
    });

    expect(first.accepted).toBe(true);
    expect(second).toEqual({ accepted: false, reason: "rate-limited" });
  });
});
