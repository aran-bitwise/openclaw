---
summary: "Milestone 8 implementation plan: internal lifecycle hooks"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-12"
title: "Flutter OpenClaw Mobile - Milestone 8 Internal Hooks"
---

# Flutter OpenClaw Mobile - Milestone 8 Internal Hooks

## Scope

Milestone 8 introduces lifecycle-triggered hooks (startup, turn start/end, reset, memory flush) as
first-class event producers, with deterministic ordering and replay-safe semantics on mobile.

## Reference baseline from prior milestones

- Milestone 1 normalization model: `src/experiments/flutter-m1/runtime-reference.ts`
- Milestone 3 session routing and ordering:
  - `src/experiments/flutter-m3/gateway-router-reference.ts`
  - `src/experiments/flutter-m3/channel-session-service-reference.ts`
- Milestone 4 durable queue semantics: `docs/experiments/plans/flutter-openclaw-m4-durable-queue-loop.md`
- Milestone 7 schedule/idempotency discipline: `docs/experiments/plans/flutter-openclaw-m7-cron-jobs.md`
- User interaction map: `docs/experiments/plans/flutter-openclaw-user-interactions.md`

## Reference implementation targets in this repository

- `src/experiments/flutter-m8/internal-hooks-reference.ts`
- `src/experiments/flutter-m8/internal-hooks-reference.test.ts`

## 1) Hook types and trigger points

Required hook categories:

- `app.startup`
- `turn.start`
- `turn.end`
- `runtime.reset`
- `memory.flush`

Each hook emits a normalized internal event record with idempotency key and trace metadata.

## 2) Ordering and determinism

- hook events must serialize within the same target session queue
- hook-generated downstream events must preserve parent-child ancestry
- startup hooks should complete (or fail with explicit state) before first interactive turn

## 3) Safety model

- hooks are allowlist-based by default
- high-risk actions require explicit user confirmation gates
- hook runtime failures should not corrupt session state; they should emit failed events

## 4) UX and observability expectations

- diagnostics panel should show hook origin (`startup`, `turn.end`, and similar)
- users can inspect whether a hook emitted follow-up events
- optional v1 surface: read-only hooks list and enable or disable toggles

## 5) Test coverage required for Milestone 8

- deterministic order when multiple hooks fire near-simultaneously
- startup hook completion before first message processing
- failure propagation and retry behavior through Milestone 4 loop
- ancestry tracing from hook to child events in timeline/inspector

## 6) Exit criteria

- [ ] Startup hook can run and persist result before first user interaction.
- [ ] Hook events use same routing and queue path as other event types.
- [ ] Hook-triggered chains are traceable and deterministic.

## 7) Milestone 9 handoff

Milestone 9 should route external webhooks through relay to produce the same normalized internal
contracts already used by hooks and schedules.
