import type { EventType } from "../flutter-m2/milestone2-reference.js";
import type { Milestone3ChannelSessionService } from "../flutter-m3/channel-session-service-reference.js";
import type { InboundChannelEnvelope } from "../flutter-m3/gateway-router-reference.js";

export type RelayWebhookRequest = {
  source: {
    provider: string;
    channelId: string;
    conversationId?: string;
    threadId?: string;
    accountId?: string;
  };
  target: {
    agentId: string;
    deviceId: string;
    sessionHint?: string;
  };
  eventType: EventType;
  payload: Record<string, unknown>;
  idempotencyKey: string;
  receivedAt: number;
};

export type RelayStoredEvent = {
  relayEventId: string;
  deviceId: string;
  status: "pending" | "delivered";
  request: RelayWebhookRequest;
  createdAt: number;
  deliveredAt?: number;
};

export type RelayFetchResult = {
  items: RelayStoredEvent[];
  nextCursor: number;
};

export class ApiRelayReference {
  private readonly events: RelayStoredEvent[] = [];
  private readonly idempotency = new Set<string>();
  private nextId = 1;

  ingestWebhook(params: {
    request: RelayWebhookRequest;
    validate?: (request: RelayWebhookRequest) => boolean;
  }): { accepted: boolean; reason?: "duplicate" | "unauthorized"; relayEventId?: string } {
    if (params.validate && !params.validate(params.request)) {
      return { accepted: false, reason: "unauthorized" };
    }

    const key = params.request.idempotencyKey.trim();
    if (this.idempotency.has(key)) {
      return { accepted: false, reason: "duplicate" };
    }

    const relayEventId = `relay-${this.nextId++}`;
    this.events.push({
      relayEventId,
      deviceId: params.request.target.deviceId,
      status: "pending",
      request: params.request,
      createdAt: params.request.receivedAt,
    });
    this.idempotency.add(key);

    return { accepted: true, relayEventId };
  }

  fetchPending(params: { deviceId: string; cursor?: number; limit?: number }): RelayFetchResult {
    const start = Math.max(0, params.cursor ?? 0);
    const limit = Math.max(1, params.limit ?? 50);
    const pending = this.events
      .filter((event) => event.deviceId === params.deviceId && event.status === "pending")
      .toSorted((a, b) => a.createdAt - b.createdAt);
    const items = pending.slice(start, start + limit).map((event) => ({ ...event }));
    return {
      items,
      nextCursor: start + items.length,
    };
  }

  ackDelivered(relayEventId: string, deliveredAt = Date.now()): boolean {
    const found = this.events.find((event) => event.relayEventId === relayEventId);
    if (!found || found.status !== "pending") {
      return false;
    }
    found.status = "delivered";
    found.deliveredAt = deliveredAt;
    return true;
  }

  async deliverToMobile(params: {
    deviceId: string;
    service: Milestone3ChannelSessionService;
    limit?: number;
  }): Promise<{ delivered: number; duplicates: number }> {
    const batch = this.fetchPending({ deviceId: params.deviceId, limit: params.limit });
    let delivered = 0;
    let duplicates = 0;

    for (const relayEvent of batch.items) {
      const req = relayEvent.request;
      const envelope: InboundChannelEnvelope = {
        source: {
          channelId: req.source.channelId,
          accountId: req.source.accountId,
          conversationId: req.source.conversationId,
          threadId: req.source.threadId,
        },
        target: {
          agentId: req.target.agentId,
          sessionHint: req.target.sessionHint,
        },
        eventType: req.eventType,
        payload: {
          ...req.payload,
          relayEventId: relayEvent.relayEventId,
          relayProvider: req.source.provider,
        },
        idempotencyKey: req.idempotencyKey,
        receivedAt: req.receivedAt,
      };

      const result = await params.service.ingestInboundEvent(envelope);
      if (result.accepted) {
        this.ackDelivered(relayEvent.relayEventId, Date.now());
        delivered += 1;
      } else {
        this.ackDelivered(relayEvent.relayEventId, Date.now());
        duplicates += 1;
      }
    }

    await params.service.waitForIdle();
    return { delivered, duplicates };
  }

  snapshot(): RelayStoredEvent[] {
    return this.events.map((event) => ({ ...event, request: { ...event.request } }));
  }
}
