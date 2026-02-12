---
summary: "Milestone 6 implementation plan: heartbeat trigger ingestion on mobile"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-12"
title: "Flutter OpenClaw Mobile - Milestone 6 Heartbeats"
---

# Flutter OpenClaw Mobile - Milestone 6 Heartbeats

## Scope

Milestone 6 adds interval-driven heartbeat events as the second production input source while
reusing the same routing, queue, persistence, and timeline contracts established in Milestones 1 to 5.

Primary goals:

- configurable per-agent heartbeat schedules
- mobile-safe trigger execution on Android and iOS
- heartbeat event ingestion through the same runtime path as message events
- suppression controls that prevent noisy and redundant heartbeat runs

## Reference baseline from prior milestones

### Milestone 1 references

- Event ingress and normalization model:
  - `src/experiments/flutter-m1/runtime-reference.ts`

### Milestone 2 references

- Domain entities and persistence contracts:
  - `src/experiments/flutter-m2/milestone2-reference.ts`

### Milestone 3 references

- Session routing and per-session ordering contracts:
  - `src/experiments/flutter-m3/gateway-router-reference.ts`
  - `src/experiments/flutter-m3/channel-session-service-reference.ts`

### Milestone 4 references

- Durable queue state machine, retries, and recovery behavior:
  - `docs/experiments/plans/flutter-openclaw-m4-durable-queue-loop.md`

### Milestone 5 references

- Timeline and composer UX state conventions reused for heartbeat visibility:
  - `docs/experiments/plans/flutter-openclaw-m5-human-message-ux.md`

### Relay references

- Push/fetch integration model when heartbeats are coordinated with internet-origin events:
  - `docs/experiments/plans/flutter-openclaw-relay-architecture.md`

## Reference implementation targets in this repository

Milestone 6 reference implementation targets:

- `src/experiments/flutter-m6/heartbeat-reference.ts`
- `src/experiments/flutter-m6/heartbeat-reference.test.ts`

Expected integration points:

- schedule trigger generates an `eventType: "heartbeat"` envelope
- envelope enters Milestone 3 `ingestInboundEvent(...)`
- queue processing and status transitions follow Milestone 4 contract
- timeline rendering follows Milestone 5 status chip and ordering patterns

## 1) Heartbeat configuration contract

Per-agent heartbeat settings should support:

- `enabled`
- `intervalMinutes`
- `activeWindow` (start hour, end hour, timezone)
- `promptTemplate`
- optional `suppressionToken` list (for example `HEARTBEAT_OK`)
- optional `maxRunsPerDay`

The configuration should be persisted with the same schema versioning and migration rules from
Milestone 2.

## 2) Platform trigger model

### Android

- primary scheduling via WorkManager periodic jobs
- catch-up execution when app resumes after missed windows

### iOS

- primary scheduling via background task APIs within iOS constraints
- fallback catch-up when app foregrounds
- optional push-triggered fetch path when available

Both platforms should emit the same normalized heartbeat event shape and never bypass the queue.

## 3) Runtime ingestion flow

Heartbeat path:

`mobile scheduler -> heartbeat envelope builder -> Milestone3ChannelSessionService.ingestInboundEvent -> Milestone4 durable queue -> processing loop -> session timeline`

Required invariants:

- no special fast path for heartbeat events
- idempotency key required for each generated heartbeat event
- per-session FIFO/no-interleaving still applies

## 4) Suppression and noise control

Suppression flow:

1. Agent run processes heartbeat prompt.
2. Runtime checks output for suppression token signals.
3. Matching token can postpone the next heartbeat or reduce frequency.
4. Suppression decisions are logged as structured metadata for auditability.

Recommended safeguards:

- never suppress permanently without explicit config
- track suppression expiration timestamp
- store suppression decision alongside run result for explainability

## 5) UI and diagnostics expectations

Required UI behavior:

- heartbeat events are visible in the same timeline as human/relay events
- timeline item includes source badge (`heartbeat`)
- queue status chips match Milestone 5 conventions
- diagnostics inspector can trace triggering schedule configuration and last run decision

## 6) Test coverage required for Milestone 6

- heartbeat scheduler creates events only inside configured active windows
- duplicate scheduler firings with same idempotency key are deduped
- heartbeat events route to correct `(agentId, channelId, sessionKey)`
- queue retry and dead-letter behavior is consistent with Milestone 4
- suppression token behavior correctly postpones or reduces runs
- restart recovery preserves pending heartbeat events

## 7) Exit criteria

- [ ] At least one heartbeat schedule per agent can be configured and persisted.
- [ ] Heartbeats generate normalized events through the same ingestion path as messages.
- [ ] Heartbeat processing obeys per-session ordering and durable queue semantics.
- [ ] Suppression behavior is explicit, inspectable, and test-covered.
- [ ] Restart and background/foreground transitions do not lose heartbeat events.

## 8) Milestone 7 handoff

Milestone 7 (cron jobs) should build on Milestone 6 scheduler primitives by adding richer schedule
expressions and missed-run policies while continuing to reuse Milestone 3 routing, Milestone 4
queueing, and Milestone 5 timeline presentation patterns.
