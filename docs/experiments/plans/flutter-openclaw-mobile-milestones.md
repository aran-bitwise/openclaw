---
summary: "Plan: Flutter mobile app milestones for an OpenClaw-style event-driven runtime"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-10"
title: "Flutter OpenClaw-Style Mobile App Milestones (Android + iOS)"
---

# Flutter OpenClaw-Style Mobile App Milestones (Android + iOS)

## 0) Scope, Principles, and Success Criteria

### Goals

Build a Flutter app that functionally emulates OpenClaw-style architecture and behavior for mobile
usage:

- Gateway-style input routing
- Event queue plus processing loop
- Five event inputs (messages, heartbeats, cron jobs, internal hooks, webhooks)
- Optional agent-to-agent messaging
- Persistent local memory
- Practical security controls

### Non-goals (initially)

- Perfect parity with every OpenClaw skill and integration
- Unrestricted device-level command execution (mobile sandbox differs from desktop)
- Autonomous background behavior that violates iOS and Android constraints

### Program-level definition of done

- Mobile app demonstrates all major input sources and the processing loop
- Users can define multiple agents, schedules, and channels
- State persists across sessions and app restarts
- Security controls are visible, default-on, and testable

## 1) Milestone Plan (bit-by-bit delivery)

### Milestone 1 — Discovery, repo intake, and architecture mapping (Week 1)

#### Deliverables

- Clone and inspect `openclaw/openclaw` _(already completed in this repository)_
- Milestone 1 architecture mapping document: [Flutter OpenClaw Mobile — Milestone 1 Architecture Mapping](/experiments/plans/flutter-openclaw-m1-architecture-mapping)
- Produce architecture mapping doc for:
  - Core runtime loop
  - Gateway responsibilities
  - Session model
  - Queue behavior
  - Event sources
  - Memory model
  - Tool and execution interfaces
- Produce Flutter/mobile constraints assessment for:
  - iOS background execution limits
  - Android WorkManager/background service limits
  - Notification, webhook, and local scheduling constraints

#### Codex prompts (examples)

- "Clone OpenClaw and summarize runtime modules, queue/event flow, and persistence contracts."
- "Map each OpenClaw concept to a Flutter-compatible implementation option and call out gaps."
- "Generate sequence diagrams for event ingestion to queue to agent turn to persistence."

#### Exit criteria

- Team can answer: where each input type enters the system, and how it is serialized and processed

### Milestone 2 — Flutter foundation and domain model (Week 1–2)

#### Deliverables

- Milestone 2 implementation document: [Flutter OpenClaw Mobile — Milestone 2 Foundation and Domain Model](/experiments/plans/flutter-openclaw-m2-foundation-domain-model)
- New Flutter app baseline with layers:
  - `presentation/`
  - `application/`
  - `domain/`
  - `infrastructure/`
- Core domain entities:
  - `AgentProfile`
  - `Event`
  - `EventType`
  - `Session`
  - `MemoryEntry`
  - `ToolInvocation`
  - `RunResult`
- JSON serialization contracts and local schema versioning

#### Recommended choices

- State management: Riverpod (or Bloc; choose one early)
- Persistence: Drift or Isar plus encrypted secure storage for secrets
- Logging: structured logs persisted locally plus export option

#### Exit criteria

- App runs on iOS and Android and can CRUD agents and sessions locally

### Milestone 3 — Gateway abstraction and channel sessions (Week 2)

#### Deliverables

- Milestone 3 implementation document: [Flutter OpenClaw Mobile — Milestone 3 Gateway Router and Channel Sessions](/experiments/plans/flutter-openclaw-m3-gateway-router-sessions)
- Implement `GatewayRouter` abstraction:
  - Accept inbound events from channels
  - Route to `(agentId, channelId, sessionId)`
- Session behavior:
  - Separate context per channel
  - Per-session FIFO ordering
  - No interleaving turns in the same session
- UI:
  - Channel inbox list
  - Per-session event timeline

#### Exit criteria

- Multiple channels can send messages while preserving isolated context and ordering

### Milestone 4 — Event queue and processing loop (Week 2–3)

#### Deliverables

- Durable queue service:
  - Event states: queued, processing, completed, failed
  - Retry policy plus dead-letter strategy
  - Idempotency keys for duplicate inbound events
- Agent processing loop:
  - Dequeue next eligible event
  - Load memory and session context
  - Run model/tool chain
  - Persist outputs and status

#### Exit criteria

- Queue state recovers correctly after app kill/restart during processing

### Milestone 5 — Input type #1: Human messages (Week 3)

#### Deliverables

- In-app chat UX for user-to-agent messaging
- Message events normalized through gateway and queue
- Typing/processing state and ordered response rendering

#### Exit criteria

- Rapid user messages are processed in order within a session

### Milestone 6 — Input type #2: Heartbeats (Week 3–4)

#### Deliverables

- Configurable heartbeat per agent:
  - Interval
  - Active hours
  - Prompt template
- Platform implementation:
  - Android WorkManager
  - iOS background task plus fallback on app open and push-trigger
- Suppression token behavior (for example `HEARTBEAT_OK`) to reduce noise

#### Exit criteria

- Heartbeat events follow the same queue path and behavior as chat messages

### Milestone 7 — Input type #3: Cron jobs (Week 4)

#### Deliverables

- Cron-like scheduler UI:
  - Daily
  - Weekly
  - Custom schedule
- Per-schedule prompt instructions
- Time zone handling and missed-run policy
- Notification/reporting for triggered outcomes

#### Exit criteria

- At least three schedules can be configured and reliably create events

### Milestone 8 — Input type #4: Internal hooks (Week 4–5)

#### Deliverables

- Hook system for lifecycle events:
  - App startup
  - Agent turn start/end
  - Reset/stop
  - Memory flush
- Hook rules UI (optional in v1; config-only is acceptable)
- Deterministic ordering when hooks emit downstream events

#### Exit criteria

- Startup hook can run setup instructions and persist results before first interaction

### Milestone 9 — Input type #5: Webhooks (Week 5)

#### Deliverables

- Minimal relay backend for external webhooks (GitHub, Slack, email providers)
- Authenticated webhook ingestion and signature verification
- Relay forwards normalized events via push plus fetch or secure polling

#### Exit criteria

- External webhook triggers an agent run and appears in the timeline with source metadata

### Milestone 10 — Agent-to-agent messaging (Week 5–6)

#### Deliverables

- Multi-agent orchestration:
  - Agent A sends task message to Agent B
  - Isolated memory/workspace by agent
  - Explicit routing rules and allowlist
- Visual trace for inter-agent handoffs

#### Exit criteria

- Demonstrated research-agent to writer-agent pipeline end-to-end

### Milestone 11 — Persistent local memory and context (Week 6)

#### Deliverables

- Markdown-like memory representation persisted locally (or equivalent structured storage with
  markdown export)
- Memory scopes:
  - Global user preferences
  - Per-agent memory
  - Per-session history
- Memory compaction and summarization jobs

#### Exit criteria

- Agent references prior-day context after restart with inspectable local memory artifacts

### Milestone 12 — Tooling layer and capability sandbox (Week 6–7)

#### Deliverables

- `ToolRegistry` abstraction with permissions for:
  - Browser/search APIs
  - Calendar/email integrations
  - Messaging connectors
- Explicit consent screens and runtime permission checks
- Dangerous actions blocked by default

#### Exit criteria

- Every tool call is logged, attributed, and policy-checked pre-execution

### Milestone 13 — Security hardening (Week 7)

#### Deliverables

- Threat model focused on:
  - Prompt injection
  - Malicious integrations/skills
  - Credential leakage
  - Unintended command/action execution
- Security controls:
  - Allowlist-only integrations
  - Signed plugin manifests
  - Secret vaulting
  - PII redaction in logs
  - High-risk confirmation gates
- Security test checklist and red-team scenarios

#### Exit criteria

- Security review passes checklist and high-risk operations require explicit confirmation

### Milestone 14 — UX, observability, and explainability (Week 7–8)

#### Deliverables

- Event inspector UI showing:
  - Source input type
  - Queue status
  - Execution trace
  - Memory reads/writes
  - Tool invocations
- "Why did this happen?" panel for event ancestry tracing
- Exportable diagnostics bundle

#### Exit criteria

- Any action can be traced to the triggering event and policy decisions

### Milestone 15 — Beta, validation, and launch readiness (Week 8+)

#### Deliverables

- Closed beta on TestFlight and Play Internal Testing
- Reliability tests for:
  - Queue durability
  - Scheduler drift
  - Offline/online sync
  - Duplicate webhook handling
- Launch docs:
  - Architecture
  - Security posture
  - Known platform limitations
  - Incident response workflow

#### Exit criteria

- Stable beta with documented limitations and rollback plan

## 2) Practical Codex-by-Codex work breakdown

For each milestone, use this sequence:

1. Ask Codex for implementation plan (files, classes, tests, risks)
2. Ask Codex for an incremental patch (small PR-sized change)
3. Run tests/lints/build locally
4. Ask Codex for threat/risk review of its patch
5. Commit and update changelog

Suggested prompt template:

> Implement Milestone X for the Flutter OpenClaw app. Keep changes under N files. Include unit
> tests and an architecture note.

## 3) Repository intake steps for OpenClaw (required early work)

- Create a separate workspace folder for upstream reference:
  - `third_party/openclaw/` (read-only mirror)
- Clone upstream:
  - `git clone https://github.com/openclaw/openclaw.git third_party/openclaw`
- Snapshot important artifacts:
  - Architecture docs
  - Runtime loop code
  - Event and queue models
  - Memory/persistence modules
  - Scheduler and webhook handling paths
- Produce a Concept Parity Matrix with columns:
  - OpenClaw concept
  - Upstream implementation path
  - Flutter implementation choice
  - Parity status (`full`, `partial`, `deferred`)
  - Platform caveats
- Revisit the matrix at each milestone review

## 4) Suggested backlog epics

- EPIC A: Runtime core (gateway, queue, loop)
- EPIC B: Input sources (message, heartbeat, cron, hooks, webhooks)
- EPIC C: Multi-agent orchestration
- EPIC D: Memory plus persistence
- EPIC E: Tooling plus integrations
- EPIC F: Security plus governance
- EPIC G: UX plus explainability
- EPIC H: Mobile release engineering

## 5) Key risks and mitigations

### iOS background execution limits

Mitigation: hybrid model using scheduled tasks, push-triggered fetch, and app-open catch-up.

### Webhook delivery to mobile devices

Mitigation: relay backend and signed event envelopes.

### Security drift while tools expand

Mitigation: default-deny permissions, scoped grants, and integration reviews.

### Autonomy expectation mismatch

Mitigation: explicit trace/explainability UI showing event-driven causality.
