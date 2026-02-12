---
summary: "Prompt catalog for AI coding agents to execute Flutter OpenClaw work packages"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-12"
title: "Flutter OpenClaw Mobile Agent Prompt Catalog"
---

# Flutter OpenClaw Mobile Agent Prompt Catalog

Use these prompts to execute each work package as scoped AI coding-agent tasks.

## Prompt conventions

Each prompt assumes:

- keep changes small and reviewable
- include tests for changed behavior
- include architecture note updates
- run formatting and targeted test commands
- summarize risks and follow-up tasks

## Work package prompts

### Work package 1 prompt (discovery and architecture mapping)

> Implement work package 1 for Flutter OpenClaw mobile. Use this repository as the OpenClaw
> runtime baseline and produce an architecture mapping update that identifies ingress points,
> routing/session contracts, queue lifecycle, persistence boundaries, and mobile constraints. Include
> Mermaid sequence diagrams and a parity matrix update.

### Work package 2 prompt (foundation and domain model)

> Implement work package 2 for Flutter OpenClaw mobile. Create or refine domain entities and
> serialization contracts for `AgentProfile`, `Event`, `EventType`, `Session`, `MemoryEntry`,
> `ToolInvocation`, and `RunResult`. Add migration-safe persistence helpers and unit tests for schema
> upgrade and serialization round-trip behavior.

### Work package 3 prompt (gateway and sessions)

> Implement work package 3 for Flutter OpenClaw mobile. Build gateway/session routing that resolves
> `(agentId, channelId, sessionKey)` deterministically, enforces per-session FIFO/no-interleaving,
> and updates inbox/timeline read models. Add tests for routing precedence, session creation,
> idempotency, and ordering guarantees.

### Work package 4 prompt (durable queue and processing loop)

> Implement work package 4 for Flutter OpenClaw mobile. Add durable queue records with
> `queued/processing/completed/failed/dead-letter` states, retry policy, and restart recovery. Add
> processing-loop tests for normal completion, retry, dead-letter transitions, and stale lease
> recovery.

### Work package 5 prompt (human messages)

> Implement work package 5 for Flutter OpenClaw mobile. Wire message composer and timeline to the
> same gateway and queue path, including status chips and rapid-send ordering guarantees. Add tests
> for duplicate send dedupe, status transitions, and restart recovery of in-flight message events.

### Work package 6 prompt (heartbeats)

> Implement work package 6 for Flutter OpenClaw mobile. Add heartbeat scheduling config, envelope
> generation, suppression token handling, and ingestion through the shared queue pipeline. Add tests
> for active-window checks, idempotency keys, and suppression behavior.

### Work package 7 prompt (cron schedules)

> Implement work package 7 for Flutter OpenClaw mobile. Extend scheduling to support daily/weekly/
> custom schedules, timezone-safe run window generation, and missed-run policy (`skip` and
> `catch-up-limited`). Add tests for DST/timezone edge cases and deterministic idempotency keys.

### Work package 8 prompt (internal hooks)

> Implement work package 8 for Flutter OpenClaw mobile. Add internal hook event producers
> (`app.startup`, `turn.start`, `turn.end`, `runtime.reset`, `memory.flush`) with deterministic
> queue ordering and ancestry metadata. Add tests for startup-before-first-turn guarantees and
> hook-chain traceability.

### Work package 9 prompt (webhooks and relay)

> Implement work package 9 for Flutter OpenClaw mobile. Harden relay ingestion with signature
> validation, replay/idempotency protection, per-device fetch/ack lifecycle, and delivery
> observability. Add tests for unauthorized rejection, duplicate handling, partial delivery retries,
> and cross-device isolation.

### Work package 10 prompt (agent-to-agent messaging)

> Implement work package 10 for Flutter OpenClaw mobile. Add allowlist-gated agent handoff
> envelopes, anti-loop controls, and timeline ancestry for multi-agent chains. Ensure the model is
> asynchronous and queue-driven for mobile constraints. Add tests for route allowlist enforcement,
> loop prevention, and restart recovery.

### Work package 11 prompt (memory and context)

> Implement work package 11 for Flutter OpenClaw mobile. Add scoped memory storage (global,
> per-agent, per-session), provenance metadata, and compaction/summarization jobs with durable
> recovery. Add tests for scope reads/writes, compaction correctness, and inspectable provenance.

### Work package 12 prompt (tooling sandbox)

> Implement work package 12 for Flutter OpenClaw mobile. Build a policy-driven tool registry with
> permission checks, risk-based confirmations, and redacted audit logs. Add tests for allow/deny
> paths, high-risk confirmation, and audit integrity.

### Work package 13 prompt (security hardening)

> Implement work package 13 for Flutter OpenClaw mobile. Add threat-model-driven controls for
> prompt injection, credential leakage, and risky automation paths. Enforce default-deny integration
> policies and explicit confirmation gates. Add security test scenarios and checklist validation.

### Work package 14 prompt (observability and explainability)

> Implement work package 14 for Flutter OpenClaw mobile. Build event inspector and "why did this
> happen" ancestry tracing across queue states, memory reads/writes, relay metadata, and tool
> invocation decisions. Add tests for ancestry completeness and diagnostics export consistency.

### Work package 15 prompt (beta and launch readiness)

> Implement work package 15 for Flutter OpenClaw mobile. Prepare release readiness artifacts,
> reliability test suite expansions, and rollout controls (beta gating, rollback workflow, incident
> playbooks). Add automation for launch checklist validation and required evidence collection.

## Mermaid reference diagram

```mermaid
flowchart LR
    P1[Prompt 1] --> P2[Prompt 2]
    P2 --> P3[Prompt 3]
    P3 --> P4[Prompt 4]
    P4 --> P5[Prompt 5]
    P5 --> P6[Prompt 6]
    P6 --> P7[Prompt 7]
    P7 --> P8[Prompt 8]
    P8 --> P9[Prompt 9]
    P9 --> P10[Prompt 10]
    P10 --> P11[Prompt 11]
    P11 --> P12[Prompt 12]
    P12 --> P13[Prompt 13]
    P13 --> P14[Prompt 14]
    P14 --> P15[Prompt 15]
```
