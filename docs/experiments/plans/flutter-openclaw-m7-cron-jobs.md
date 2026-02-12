---
summary: "Milestone 7 implementation plan: cron-like schedules on mobile"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-12"
title: "Flutter OpenClaw Mobile - Milestone 7 Cron Jobs"
---

# Flutter OpenClaw Mobile - Milestone 7 Cron Jobs

## Scope

Milestone 7 extends Milestone 6 heartbeat scheduling into richer user-defined cron-like schedules
(daily, weekly, custom windows) while reusing the same ingest, queue, and timeline behavior.

Primary goals:

- support multiple schedules per agent
- deterministic time zone handling and missed-run policy
- preserve idempotent enqueue semantics for scheduled events
- surface scheduled runs in user timeline and diagnostics

## Reference baseline from prior milestones

- Milestone 2 persistence and migrations: `src/experiments/flutter-m2/milestone2-reference.ts`
- Milestone 3 route and session contract:
  - `src/experiments/flutter-m3/gateway-router-reference.ts`
  - `src/experiments/flutter-m3/channel-session-service-reference.ts`
- Milestone 4 queue and retry loop: `docs/experiments/plans/flutter-openclaw-m4-durable-queue-loop.md`
- Milestone 6 heartbeat scheduling patterns: `docs/experiments/plans/flutter-openclaw-m6-heartbeats.md`
- User interaction map: `docs/experiments/plans/flutter-openclaw-user-interactions.md`

## Reference implementation targets in this repository

- `src/experiments/flutter-m7/cron-scheduler-reference.ts`
- `src/experiments/flutter-m7/cron-scheduler-reference.test.ts`

Expected integration points:

- cron trigger builds normalized envelope (`eventType: "cron"`)
- envelope enters Milestone 3 `ingestInboundEvent(...)`
- run lifecycle follows Milestone 4 queue states

## 1) Scheduler contract

Each schedule should define:

- `scheduleId`
- `agentId`
- `name`
- `ruleType` (`daily` | `weekly` | `custom`)
- `timezone`
- `promptTemplate`
- `missedRunPolicy` (`skip` | `catch-up-limited`)
- `enabled`

## 2) Mobile execution model

- Android: WorkManager + app-open reconciliation
- iOS: background task APIs + app-open reconciliation
- Optional relay-assisted wake patterns can trigger reconciliation, but event generation remains local
  and deterministic.

## 3) Missed run and idempotency rules

- Schedules should materialize deterministic run windows.
- A generated run must carry a stable idempotency key derived from schedule ID + window start.
- Catch-up should cap backlog creation to protect battery and queue health.

## 4) UX expectations

- User can create, edit, pause, and resume schedules.
- Timeline entries should include schedule source metadata.
- Diagnostics should show next run, last run, and missed-run disposition.

## 5) Test coverage required for Milestone 7

- timezone conversion and daylight-saving transitions
- deterministic idempotency keys per run window
- missed-run policy behavior on cold start and long background periods
- queue ordering and no interleaving invariants under rapid schedule fire

## 6) Exit criteria

- [ ] Three schedules can run reliably for one agent.
- [ ] Schedule events follow the same queue path as messages/heartbeats.
- [ ] Missed-run behavior is visible and test-covered.

## 7) Milestone 8 handoff

Milestone 8 should treat internal hooks as another event producer that reuses the same scheduling
metadata and queue ingestion discipline defined here.
