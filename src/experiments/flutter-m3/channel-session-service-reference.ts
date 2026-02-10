import {
  createEvent,
  createSession,
  type Event,
  type EventStatus,
  type Milestone2Repository,
  type Session,
} from "../flutter-m2/milestone2-reference.js";
import {
  Milestone3GatewayRouter,
  type InboundChannelEnvelope,
} from "./gateway-router-reference.js";

export type IngestResult =
  | {
      accepted: true;
      route: { agentId: string; channelId: string; sessionKey: string };
      session: Session;
      event: Event;
    }
  | {
      accepted: false;
      reason: "duplicate";
      route: { agentId: string; channelId: string; sessionKey: string };
    };

export class Milestone3ChannelSessionService {
  private readonly router: Milestone3GatewayRouter;
  private readonly drainingSessions = new Set<string>();
  private readonly sessionQueues = new Map<string, string[]>();
  private readonly runtimeStatus = new Map<string, EventStatus>();

  constructor(
    private readonly repo: Milestone2Repository,
    params?: {
      defaultAgentId?: string;
      processEvent?: (event: Event) => Promise<void>;
    },
  ) {
    this.router = new Milestone3GatewayRouter(params?.defaultAgentId);
    this.processEvent = params?.processEvent ?? (async () => {});
  }

  private readonly processEvent: (event: Event) => Promise<void>;

  async ingestInboundEvent(envelope: InboundChannelEnvelope): Promise<IngestResult> {
    const route = this.router.resolveRoute(envelope);
    const m1Event = this.router.normalizeWithMilestone1({
      envelope,
      makeId: () => `m1-${envelope.receivedAt}-${Math.random().toString(36).slice(2, 7)}`,
    });

    const session = this.getOrCreateSession(route, envelope.receivedAt);

    let event: Event;
    try {
      event = this.repo.appendEvent(
        createEvent({
          id: `event-${m1Event.id}`,
          sessionId: session.id,
          type: envelope.eventType,
          source: route.channelId,
          payload: {
            ...envelope.payload,
            milestone1EventId: m1Event.id,
            milestone1InputType: m1Event.inputType,
          },
          idempotencyKey: envelope.idempotencyKey,
          now: envelope.receivedAt,
        }),
      );
    } catch (error) {
      if (error instanceof Error && error.message.includes("Duplicate idempotencyKey")) {
        return {
          accepted: false,
          reason: "duplicate",
          route,
        };
      }
      throw error;
    }

    this.runtimeStatus.set(event.id, "queued");
    this.enqueueSessionEvent(route.sessionKey, event.id);
    this.ensureSessionDrain(route.sessionKey).catch(() => {
      // Error is reflected in runtime status; service keeps draining other events.
    });

    return {
      accepted: true,
      route,
      session,
      event,
    };
  }

  private getOrCreateSession(
    route: { agentId: string; channelId: string; sessionKey: string },
    now: number,
  ): Session {
    const existing = this.repo
      .listSessionsByAgent(route.agentId)
      .find((session) => session.sessionKey === route.sessionKey);
    if (existing) {
      return existing;
    }

    return this.repo.createSession(
      createSession({
        id: `session-${route.sessionKey}`,
        agentId: route.agentId,
        channelId: route.channelId,
        sessionKey: route.sessionKey,
        now,
      }),
    );
  }

  private enqueueSessionEvent(sessionKey: string, eventId: string): void {
    const queue = this.sessionQueues.get(sessionKey) ?? [];
    queue.push(eventId);
    this.sessionQueues.set(sessionKey, queue);
  }

  private async ensureSessionDrain(sessionKey: string): Promise<void> {
    if (this.drainingSessions.has(sessionKey)) {
      return;
    }
    this.drainingSessions.add(sessionKey);

    try {
      while (true) {
        const queue = this.sessionQueues.get(sessionKey) ?? [];
        const eventId = queue.shift();
        this.sessionQueues.set(sessionKey, queue);
        if (!eventId) {
          break;
        }

        const event = this.repo.snapshot().events.find((item) => item.id === eventId);
        if (!event) {
          continue;
        }

        this.runtimeStatus.set(event.id, "processing");
        try {
          await this.processEvent(event);
          this.runtimeStatus.set(event.id, "completed");
        } catch {
          this.runtimeStatus.set(event.id, "failed");
        }
      }
    } finally {
      this.drainingSessions.delete(sessionKey);
    }
  }

  getEventRuntimeStatus(eventId: string): EventStatus | undefined {
    return this.runtimeStatus.get(eventId);
  }

  async waitForIdle(): Promise<void> {
    while (this.drainingSessions.size > 0) {
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
  }

  listSessionTimeline(sessionId: string): Event[] {
    return this.repo
      .snapshot()
      .events.filter((event) => event.sessionId === sessionId)
      .toSorted((a, b) => a.createdAt - b.createdAt);
  }

  listChannelInbox(channelId: string): Array<{
    sessionId: string;
    sessionKey: string;
    channelId: string;
    lastEventId?: string;
    lastEventType?: string;
    lastEventAt?: number;
    queueDepth: number;
  }> {
    const normalized = channelId.trim().toLowerCase();
    const snapshot = this.repo.snapshot();

    return snapshot.sessions
      .filter((session) => session.channelId.toLowerCase() === normalized)
      .map((session) => {
        const timeline = snapshot.events
          .filter((event) => event.sessionId === session.id)
          .toSorted((a, b) => b.createdAt - a.createdAt);
        const last = timeline[0];
        return {
          sessionId: session.id,
          sessionKey: session.sessionKey,
          channelId: session.channelId,
          lastEventId: last?.id,
          lastEventType: last?.type,
          lastEventAt: last?.createdAt,
          queueDepth: this.sessionQueues.get(session.sessionKey)?.length ?? 0,
        };
      })
      .toSorted((a, b) => (b.lastEventAt ?? 0) - (a.lastEventAt ?? 0));
  }
}
