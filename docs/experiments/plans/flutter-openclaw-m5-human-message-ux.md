---
summary: "Milestone 5 implementation plan: human message UX on durable mobile runtime"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-10"
title: "Flutter OpenClaw Mobile — Milestone 5 Human Messages UX"
---

# Flutter OpenClaw Mobile — Milestone 5 Human Messages UX

## Scope

Milestone 5 delivers the first complete user-facing chat flow by connecting the message composer and
session timeline UI to the durable runtime from Milestones 1 to 4.

Primary goals:

- in-app human-to-agent messaging UX
- message events normalized through GatewayRouter/session routing
- durable queue-backed processing state and ordered rendering
- UX behavior that remains correct across app backgrounding/restart

## Reference baseline from prior milestones

### Milestone 1 references

- Input normalization and event shape baseline:
  - `src/experiments/flutter-m1/runtime-reference.ts`

### Milestone 2 references

- Core entities/persistence contracts (`Event`, `Session`, `RunResult`):
  - `src/experiments/flutter-m2/milestone2-reference.ts`

### Milestone 3 references

- Route/session mapping and timeline/inbox read models:
  - `src/experiments/flutter-m3/gateway-router-reference.ts`
  - `src/experiments/flutter-m3/channel-session-service-reference.ts`

### Milestone 4 references

- Durable queue + processing loop contract:
  - `docs/experiments/plans/flutter-openclaw-m4-durable-queue-loop.md`

### Relay references

- Internet-origin events and mobile fetch/ack lifecycle:
  - `docs/experiments/plans/flutter-openclaw-relay-architecture.md`

## Reference implementation links in this repository

Milestone 5 reference implementation targets:

- `src/experiments/flutter-m5/human-message-ux-reference.ts`
- `src/experiments/flutter-m5/human-message-ux-reference.test.ts`

Expected integration points:

- compose/send path calls Milestone 3 `ingestInboundEvent(...)`
- status/progress comes from Milestone 4 queue states
- timeline rendering reads persisted events in session order

## 1) UX behaviors

### Composer flow

1. User selects or creates a session.
2. User sends message from composer.
3. Message creates a `message` event with idempotency key.
4. Event is queued and visible immediately with `queued`/`processing` state.
5. Assistant reply appears in ordered timeline when processing completes.

### Timeline flow

- preserve strict per-session ordering
- display queue/runtime state chips (`queued`, `processing`, `completed`, `failed`)
- collapse duplicate user sends by idempotency when retries occur
- show failure state with retry action (delegates to Milestone 4 retry path)

## 2) Data contract details

User message event payload should include:

- `text`
- `messageId` (client-generated stable ID)
- `sentAt`
- optional media metadata (future-proofing)

Assistant response payload should include:

- `text`
- `runId`
- `completedAt`
- optional usage/token metadata

## 3) Message-to-runtime wiring

### Inbound user message path

`presentation composer -> application usecase -> Milestone3ChannelSessionService.ingestInboundEvent -> Milestone4 durable queue enqueue -> processing loop`

### Outbound render path

`processing loop result -> persisted event/run result -> timeline query -> presentation state`

## 4) Reliability and lifecycle expectations

- message send must be durable before UI marks “sent”
- app restart should restore pending sends and in-progress states
- no message loss when app backgrounds mid-processing
- duplicate submit attempts should not create duplicate runs

## 5) UI states and edge cases

Required states:

- idle
- queued
- processing
- completed
- failed (retryable)
- failed (dead-letter/manual intervention)

Edge cases:

- rapid consecutive sends in same session
- send while offline then reconnect
- send during stale processing recovery window
- simultaneous events from relay and local composer in one session

## 6) Test coverage required for Milestone 5

- composer send creates correctly normalized `message` events
- timeline ordering remains stable under rapid sends
- status transitions render correctly from durable queue states
- restart restores pending/in-progress message states
- duplicate sends with same idempotency key are deduped
- mixed relay + local message ingestion does not break ordering

## 7) Exit criteria (Milestone 5)

- [ ] User can send messages and receive ordered replies in-session.
- [ ] Queue/processing status is visible in chat timeline.
- [ ] Rapid sends maintain per-session ordering without interleaving.
- [ ] Restart/background does not lose in-flight message state.
- [ ] Retry flow for failed messages is available and test-covered.

## 8) Milestone 6 handoff

Milestone 6 (heartbeats) should reuse Milestone 5 message runtime path by injecting heartbeat
system messages into the same queue/timeline contract rather than creating a separate processing
pipeline.
