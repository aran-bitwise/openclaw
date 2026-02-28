export type Milestone1InputType = "message" | "heartbeat" | "cron" | "internal-hook" | "webhook";

export type Milestone1EventStatus = "queued" | "processing" | "completed" | "failed";

export type Milestone1InboundEvent = {
  id: string;
  inputType: Milestone1InputType;
  agentId: string;
  channelId: string;
  sessionId: string;
  idempotencyKey?: string;
  payload: Record<string, unknown>;
  createdAt: number;
};

export type Milestone1QueuedEvent = Milestone1InboundEvent & {
  status: Milestone1EventStatus;
  attempts: number;
  updatedAt: number;
  error?: string;
};

export type Milestone1Route = {
  agentId: string;
  channelId: string;
  sessionId: string;
};

export type Milestone1InputEnvelope = {
  inputType: Milestone1InputType;
  source: {
    channelId: string;
    accountId?: string;
    conversationId?: string;
  };
  target: {
    agentId: string;
    sessionHint?: string;
  };
  payload: Record<string, unknown>;
  idempotencyKey?: string;
};

export class Milestone1GatewayRouter {
  resolve(envelope: Milestone1InputEnvelope): Milestone1Route {
    const channelId = envelope.source.channelId.trim().toLowerCase() || "unknown";
    const agentId = envelope.target.agentId.trim() || "main";
    const base = envelope.target.sessionHint?.trim() || envelope.source.conversationId?.trim();
    const normalized = (base || "main").toLowerCase();
    return {
      agentId,
      channelId,
      sessionId: `agent:${agentId}:${channelId}:${normalized}`,
    };
  }
}

export class Milestone1Queue {
  private readonly events: Milestone1QueuedEvent[] = [];
  private readonly idempotency = new Set<string>();

  enqueue(event: Milestone1InboundEvent): {
    accepted: boolean;
    event: Milestone1QueuedEvent | null;
  } {
    const key = event.idempotencyKey?.trim();
    if (key && this.idempotency.has(key)) {
      return { accepted: false, event: null };
    }

    const queued: Milestone1QueuedEvent = {
      ...event,
      status: "queued",
      attempts: 0,
      updatedAt: Date.now(),
    };
    this.events.push(queued);

    if (key) {
      this.idempotency.add(key);
    }

    return { accepted: true, event: queued };
  }

  dequeueNext(sessionId?: string): Milestone1QueuedEvent | null {
    const idx = this.events.findIndex(
      (item) => item.status === "queued" && (!sessionId || item.sessionId === sessionId),
    );
    if (idx < 0) {
      return null;
    }
    const next = this.events[idx];
    next.status = "processing";
    next.attempts += 1;
    next.updatedAt = Date.now();
    return next;
  }

  complete(id: string): void {
    const event = this.events.find((item) => item.id === id);
    if (!event) {
      return;
    }
    event.status = "completed";
    event.updatedAt = Date.now();
    event.error = undefined;
  }

  fail(id: string, error: string): void {
    const event = this.events.find((item) => item.id === id);
    if (!event) {
      return;
    }
    event.status = "failed";
    event.updatedAt = Date.now();
    event.error = error;
  }

  snapshot(): Milestone1QueuedEvent[] {
    return this.events.map((item) => ({ ...item }));
  }
}

export function normalizeMilestone1Event(params: {
  envelope: Milestone1InputEnvelope;
  router: Milestone1GatewayRouter;
  now?: () => number;
  makeId?: () => string;
}): Milestone1InboundEvent {
  const route = params.router.resolve(params.envelope);
  const now = params.now ?? Date.now;
  const id = params.makeId?.() ?? `evt-${now()}-${Math.random().toString(36).slice(2, 8)}`;

  return {
    id,
    inputType: params.envelope.inputType,
    agentId: route.agentId,
    channelId: route.channelId,
    sessionId: route.sessionId,
    idempotencyKey: params.envelope.idempotencyKey,
    payload: params.envelope.payload,
    createdAt: now(),
  };
}

export async function runMilestone1ProcessingLoop(params: {
  queue: Milestone1Queue;
  process: (event: Milestone1QueuedEvent) => Promise<void>;
  maxRuns?: number;
}): Promise<number> {
  const limit = params.maxRuns ?? Number.POSITIVE_INFINITY;
  let runs = 0;

  // Simple baseline loop for milestone validation.
  while (runs < limit) {
    const next = params.queue.dequeueNext();
    if (!next) {
      break;
    }
    try {
      await params.process(next);
      params.queue.complete(next.id);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      params.queue.fail(next.id, message);
    }
    runs += 1;
  }

  return runs;
}
