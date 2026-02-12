---
summary: "Milestone 11 implementation plan: persistent memory and context"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-12"
title: "Flutter OpenClaw Mobile - Milestone 11 Memory and Context"
---

# Flutter OpenClaw Mobile - Milestone 11 Memory and Context

## Scope

Milestone 11 provides durable, inspectable memory across user, agent, and session scopes so mobile
runs can reference prior context after restart and over multi-day usage.

## Reference baseline from prior milestones

- Milestone 2 persistence primitives and migration approach: `src/experiments/flutter-m2/milestone2-reference.ts`
- Milestone 4 queue lifecycle and recovery contracts: `docs/experiments/plans/flutter-openclaw-m4-durable-queue-loop.md`
- Milestone 10 handoff trace model: `docs/experiments/plans/flutter-openclaw-m10-agent-to-agent.md`
- User interactions (timeline and diagnostics): `docs/experiments/plans/flutter-openclaw-user-interactions.md`

## Reference implementation targets in this repository

- `src/experiments/flutter-m11/memory-context-reference.ts`
- `src/experiments/flutter-m11/memory-context-reference.test.ts`

## 1) Memory scopes

Required scopes:

- global user preferences
- per-agent memory
- per-session history and summaries

Each entry must carry source metadata and recency markers for ranking and explainability.

## 2) Compaction and summarization

- run periodic compaction jobs to control store size
- preserve provenance links when summarizing
- enforce token and size budgets appropriate for mobile storage

## 3) Recovery and durability

- memory writes should be atomic with run result persistence when feasible
- restart must restore memory indices without full recomputation
- failed compaction should not lose raw source entries

## 4) UX expectations

- users can inspect memory artifacts and origin
- users can pin, edit, or clear selected memory scopes
- diagnostics can explain memory reads and writes per run

## 5) Test coverage required for Milestone 11

- write/read behavior per scope
- compaction preserving critical context links
- restart recovery of indices and summaries
- manual memory clear and consent flows

## 6) Exit criteria

- [ ] Agent references prior-day context after restart.
- [ ] Memory artifacts are inspectable by scope.
- [ ] Compaction reduces footprint without losing key provenance.

## 7) Milestone 12 handoff

Milestone 12 should apply explicit tool permission policies to memory-consuming and memory-writing
operations.
