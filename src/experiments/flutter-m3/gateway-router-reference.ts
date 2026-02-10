import {
  Milestone1GatewayRouter,
  normalizeMilestone1Event,
  type Milestone1InputType,
} from "../flutter-m1/runtime-reference.js";
import { buildSessionKey, type EventType } from "../flutter-m2/milestone2-reference.js";

export type InboundChannelEnvelope = {
  source: {
    channelId: string;
    accountId?: string;
    conversationId?: string;
    threadId?: string;
    senderId?: string;
  };
  target?: {
    agentId?: string;
    sessionHint?: string;
  };
  eventType: EventType;
  payload: Record<string, unknown>;
  idempotencyKey?: string;
  receivedAt: number;
};

export type ResolvedRoute = {
  agentId: string;
  channelId: string;
  sessionKey: string;
};

function toMilestone1InputType(type: EventType): Milestone1InputType {
  if (type === "internalHook") {
    return "internal-hook";
  }
  if (type === "agentMessage") {
    return "message";
  }
  return type;
}

export class Milestone3GatewayRouter {
  constructor(private readonly defaultAgentId = "main") {}

  resolveRoute(envelope: InboundChannelEnvelope): ResolvedRoute {
    const agentId = envelope.target?.agentId?.trim() || this.defaultAgentId;
    const channelId = envelope.source.channelId.trim().toLowerCase() || "unknown";
    const scope =
      envelope.target?.sessionHint?.trim() ||
      envelope.source.threadId?.trim() ||
      envelope.source.conversationId?.trim() ||
      "main";

    return {
      agentId,
      channelId,
      sessionKey: buildSessionKey({
        agentId,
        channelId,
        sessionHint: scope,
      }),
    };
  }

  /**
   * Integration bridge to the Milestone 1 normalization model.
   * This keeps input envelopes compatible across M1/M2/M3 references.
   */
  normalizeWithMilestone1(params: { envelope: InboundChannelEnvelope; makeId: () => string }) {
    const m1Router = new Milestone1GatewayRouter();
    return normalizeMilestone1Event({
      envelope: {
        inputType: toMilestone1InputType(params.envelope.eventType),
        source: {
          channelId: params.envelope.source.channelId,
          accountId: params.envelope.source.accountId,
          conversationId:
            params.envelope.target?.sessionHint ||
            params.envelope.source.threadId ||
            params.envelope.source.conversationId,
        },
        target: {
          agentId: params.envelope.target?.agentId || this.defaultAgentId,
          sessionHint:
            params.envelope.target?.sessionHint ||
            params.envelope.source.threadId ||
            params.envelope.source.conversationId,
        },
        payload: params.envelope.payload,
        idempotencyKey: params.envelope.idempotencyKey,
      },
      router: m1Router,
      now: () => params.envelope.receivedAt,
      makeId: params.makeId,
    });
  }
}
