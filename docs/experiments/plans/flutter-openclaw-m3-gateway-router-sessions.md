---
summary: "Milestone 3 implementation plan: Gateway abstraction and channel session routing"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-10"
title: "Flutter OpenClaw Mobile — Milestone 3 Gateway Router and Channel Sessions"
---

# Flutter OpenClaw Mobile — Milestone 3 Gateway Router and Channel Sessions

## Scope

Milestone 3 builds directly on Milestone 1 architecture mapping and Milestone 2 domain/persistence
reference code.

Primary goals:

- introduce a `GatewayRouter` abstraction for inbound event normalization and route resolution
- map inbound channel events to `(agentId, channelId, sessionId/sessionKey)`
- enforce per-session FIFO behavior without interleaving turns
- provide inbox/timeline query models for presentation layer

## Reference baseline from prior milestones

### Milestone 1 references

- Runtime/event ingress model and five-input normalization:
  - `src/experiments/flutter-m1/runtime-reference.ts`
  - `src/experiments/flutter-m1/runtime-reference.test.ts`

Reuse from Milestone 1:

- event-source normalization pattern (`message`, `heartbeat`, `cron`, `internal-hook`, `webhook`)
- queue state thinking (`queued -> processing -> completed/failed`)
- route shape expectations (`agent/channel/session` identity)

### Milestone 2 references

- Domain entities, schema migration, and repository contract:
  - `src/experiments/flutter-m2/milestone2-reference.ts`
  - `src/experiments/flutter-m2/milestone2-reference.test.ts`

Reuse from Milestone 2:

- `Session`, `Event`, and `EventType` as persistent contract boundaries
- `buildSessionKey(...)` as canonical session identity builder
- repository methods (`createSession`, `appendEvent`, `listSessionsByAgent`) for storage integration
- idempotency handling at event insertion (`appendEvent(...)`)

## Reference implementation links in this repository

Milestone 3 now has an executable reference implementation in:

- `src/experiments/flutter-m3/gateway-router-reference.ts`
- `src/experiments/flutter-m3/channel-session-service-reference.ts`
- `src/experiments/flutter-m3/gateway-router-reference.test.ts`
- `src/experiments/flutter-m3/channel-session-service-reference.test.ts`

Integration points to prior milestones:

- **Milestone 1 integration**: `Milestone3GatewayRouter.normalizeWithMilestone1(...)` bridges incoming envelopes into the Milestone 1 normalized event model.
- **Milestone 2 integration**: `Milestone3ChannelSessionService` uses `Milestone2Repository` + `createSession(...)` + `createEvent(...)` to persist sessions/events and enforce idempotency constraints.
- **Shared session identity**: route resolution uses `buildSessionKey(...)` from the Milestone 2 reference as the canonical key builder.

## 1) Target architecture for Milestone 3

```text
presentation/
  state/channel_inbox_provider.dart
  state/session_timeline_provider.dart

application/
  services/gateway_router.dart
  services/channel_session_service.dart
  usecases/ingest_inbound_event_usecase.dart
  usecases/list_channel_inbox_usecase.dart
  usecases/list_session_timeline_usecase.dart

domain/
  entities/(reuse from Milestone 2)
  repositories/
    session_repository.dart
    event_repository.dart

infrastructure/
  adapters/channel_adapters/*.dart
  persistence/(reuse Milestone 2 backing store)
```

## 2) GatewayRouter contract

```ts
// Reference TypeScript shape for milestone design parity.
type InboundChannelEnvelope = {
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

type ResolvedRoute = {
  agentId: string;
  channelId: string;
  sessionKey: string;
};

interface GatewayRouter {
  resolveRoute(envelope: InboundChannelEnvelope): ResolvedRoute;
}
```

Milestone 3 routing rules:

1. Resolve `agentId` from explicit target first, otherwise default agent.
2. Resolve `channelId` from envelope source and normalize to lowercase.
3. Resolve `sessionKey` with stable composition:
   `agent:<agentId>:<channelId>:<scope>` where scope is chosen from:
   - explicit `sessionHint`
   - `threadId` (if provided)
   - `conversationId`
   - fallback `main`
4. Ensure deterministic outputs so duplicate inbound retries map to same session.

## 3) Channel session service behavior

`ChannelSessionService` responsibilities:

- ensure session exists for resolved route (`create-if-missing` pattern)
- persist inbound event via Milestone 2 repository contract
- dispatch to session queue without cross-session interleaving
- expose inbox/timeline read models for UI

Suggested service methods:

- `ingestInboundEvent(envelope)`
- `getOrCreateSession(route)`
- `enqueueSessionEvent(sessionId, eventId)`
- `listChannelInbox(channelId)`
- `listSessionTimeline(sessionId)`

## 4) FIFO and no-interleaving strategy

Per-session queue key:

- `queueKey = sessionKey`

Execution invariant:

- only one active processing turn per `queueKey` at a time
- events from different sessions may run concurrently
- events in the same session must preserve enqueue order

Reference algorithm:

1. enqueue event row with status `queued`
2. if session not currently draining, mark session as draining
3. process next queued event for that session in FIFO order
4. transition status to `processing`, then `completed`/`failed`
5. continue until queue empty, then clear draining flag

## 5) Data model additions to Milestone 2 baseline

Milestone 2 already stores `Session` and `Event`. Milestone 3 needs operational metadata:

- `Session.lastMessageAt` should update on each inbound message-like event
- optional `Session.unreadCount` (if UI requires badge counts)
- `Event.source` should include channel origin marker (`telegram`, `webhook`, etc.)
- optional lightweight in-memory map `sessionKey -> isDraining`

No schema break is required if these are optional fields or derived values.

## 6) UI outputs expected in this milestone

### Channel inbox list

For each channel + session row:

- channel identifier
- session title/key
- last activity timestamp
- last event preview
- queue depth (optional)

### Per-session timeline

For a selected session:

- ordered list of inbound/outbound/system events
- event type badges (`message`, `heartbeat`, `cron`, `internalHook`, `webhook`)
- status chip (`queued`, `processing`, `completed`, `failed`)

## 7) Milestone 3 reference implementation verification checklist

Expected test coverage:

- route resolution precedence (`sessionHint` > `threadId` > `conversationId` > `main`)
- deterministic session key generation across retries
- create-if-missing session behavior
- per-session FIFO ordering guarantees
- no interleaving within same session under concurrent ingest
- idempotency rejection for duplicate inbound events

## 8) Exit criteria (Milestone 3)

- [ ] `GatewayRouter` abstraction exists and is used by inbound ingestion.
- [ ] Inbound events from multiple channels resolve to deterministic route identities.
- [ ] Sessions are isolated by `sessionKey` and preserve per-session FIFO ordering.
- [ ] Same-session interleaving is prevented under concurrent event arrivals.
- [ ] Channel inbox and session timeline read models are available to UI state layer.
- [ ] Automated tests pass for routing, session isolation, and FIFO behavior.

## 9) Milestone 4 handoff

Milestone 4 should reuse Milestone 3 queue/session gating to implement a durable processing loop with:

- retry policy and dead-letter handling
- robust status transitions
- app restart recovery from persisted queued/processing states
