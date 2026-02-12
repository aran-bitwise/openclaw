---
summary: "User interaction map for Flutter OpenClaw mobile features"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-12"
title: "Flutter OpenClaw Mobile User Interaction Flows"
---

# Flutter OpenClaw Mobile User Interaction Flows

This document outlines how a user interacts with the app to use major OpenClaw-style features,
with Mermaid diagrams that map user actions to relay, routing, queue, memory, and tooling runtime
contracts from Milestones 1 to 12.

## 1) First run and agent setup flow

User goals:

- install app and complete onboarding
- create first agent profile
- connect at least one channel and local session
- enable runtime inputs (message, heartbeat, schedules)

Associated milestones: 1, 2, 3, 5, 6, 7.

```mermaid
flowchart TD
    A[Open app] --> B[Onboarding welcome]
    B --> C[Create or import profile]
    C --> D[Create AgentProfile]
    D --> E[Choose channels]
    E --> F[Connect relay-enabled channel]
    E --> G[Enable in-app chat]
    F --> H[Validate credentials and permissions]
    G --> I[Create default session]
    H --> J[Save secure config]
    I --> J
    J --> K[Land on inbox and sessions]
```

## 2) Human message interaction flow

User goals:

- send a chat message
- see queued and processing states
- receive ordered response in the same session timeline

Associated milestones: 1, 3, 4, 5.

```mermaid
sequenceDiagram
    participant U as User
    participant UI as Mobile UI
    participant M3 as GatewayRouter and Session Service
    participant M4 as Durable Queue and Loop
    participant DB as Local Store

    U->>UI: Type message and tap Send
    UI->>M3: ingestInboundEvent(message envelope)
    M3->>DB: upsert session and append event
    M3->>M4: enqueue session event
    M4->>DB: set queued then processing
    M4->>DB: persist run result and completion
    DB-->>UI: timeline update with status chips
    UI-->>U: Ordered assistant response shown
```

## 3) Heartbeat and cron scheduler interactions

User goals:

- configure periodic and calendar-based agent check-ins
- ensure scheduled events use same processing path as messages
- avoid noise with suppression and missed-run policies

Associated milestones: 6, 7, 4, 5.

```mermaid
sequenceDiagram
    participant U as User
    participant CFG as Schedule Settings UI
    participant SCH as Mobile Scheduler
    participant M3 as GatewayRouter and Session Service
    participant M4 as Durable Queue and Loop
    participant UI as Timeline UI

    U->>CFG: Enable heartbeat and cron schedules
    CFG->>SCH: Register platform triggers
    SCH->>M3: ingestInboundEvent(heartbeat or cron envelope)
    M3->>M4: enqueue scheduled event
    M4->>M4: process and evaluate suppression or missed-run policy
    M4-->>UI: publish queued, processing, completed
    UI-->>U: Show scheduled item and source badge
```

## 4) Internal hook interactions

User goals:

- enable deterministic startup and lifecycle automation
- inspect hook-triggered events and downstream effects

Associated milestones: 8, 4, 5.

```mermaid
sequenceDiagram
    participant APP as Mobile App Runtime
    participant HK as Hook Engine
    participant M3 as GatewayRouter and Session Service
    participant M4 as Durable Queue and Loop
    participant U as User

    APP->>HK: app.startup
    HK->>M3: ingestInboundEvent(internal hook envelope)
    M3->>M4: enqueue startup hook event
    M4->>M4: process hook and create follow-up actions
    M4-->>U: Timeline and diagnostics show hook ancestry
```

## 5) Webhook and relay interaction flow

User goals:

- connect external providers that can reach internet endpoints
- have events delivered safely to mobile via relay
- see events merged in session timeline with source metadata

Associated milestones: relay architecture, 9, 3, 4, 5.

```mermaid
sequenceDiagram
    participant EXT as External Provider
    participant REL as Relay API
    participant APP as Mobile App
    participant M3 as GatewayRouter and Session Service
    participant UI as Timeline UI

    EXT->>REL: Send signed webhook
    REL->>REL: validate and dedupe idempotency
    APP->>REL: fetchPending(deviceId)
    REL-->>APP: return pending envelopes
    APP->>M3: ingestInboundEvent(webhook envelope)
    M3->>M3: resolve route and session key
    M3-->>UI: add event to timeline and inbox
    APP->>REL: ackDelivered(relayEventId)
```

## 6) Multi agent handoff interaction flow

User goals:

- run specialist agents for focused tasks
- keep memory and session boundaries clear
- inspect handoff lineage when results are produced

Associated milestones: 10, 11, 4.

### Practical mobile model

This can work on a phone if orchestration is asynchronous and queue-driven:

- handoffs are stored as normal events and processed by the same durable loop
- UI shows progress and can survive restarts
- allowlists bound fan-out and prevent runaway handoff loops
- heavy work can be deferred to relay-assisted or remote execution when needed

```mermaid
sequenceDiagram
    participant U as User
    participant A as Agent A
    participant Q as Durable Queue
    participant B as Agent B
    participant UI as Timeline and Inspector

    U->>A: Ask for research and draft
    A->>Q: enqueue handoff to Agent B
    Q->>B: deliver handoff when eligible
    B->>Q: enqueue response artifact
    Q-->>UI: append ancestry-linked events
    UI-->>U: show A->B chain and final output
```

## 7) Memory and context interaction flow

User goals:

- review what memory is stored
- understand why context was used in a run
- clear or pin important memory entries

Associated milestones: 11, 5, 10.

```mermaid
flowchart TD
    A[User opens Memory tab] --> B[View global and agent scopes]
    B --> C[Inspect source and recency metadata]
    C --> D[Pin or clear selected entries]
    D --> E[Next run uses updated memory state]
```

## 8) Tooling and capability sandbox interactions

User goals:

- grant and revoke tool permissions
- confirm high-risk actions explicitly
- understand why a tool was allowed or blocked

Associated milestones: 12, 9, 11.

```mermaid
sequenceDiagram
    participant U as User
    participant UI as Permissions UI
    participant POL as Policy Engine
    participant TOOL as Tool Registry
    participant LOG as Audit Log

    U->>UI: Trigger tool action
    UI->>POL: check permissions and risk
    POL->>TOOL: allow or block invocation
    TOOL->>LOG: write redacted audit record
    LOG-->>UI: show allowed or blocked reason
    UI-->>U: display confirmation or denial
```

## 9) User visible runtime controls

The app should expose clear controls for key runtime operations:

- pause or resume processing loop
- retry failed queue items
- inspect dead-letter items and reason
- replay relay fetch on demand
- view per-session event ancestry and source type

Associated milestones: 4, 5, 9, 10, 12.

```mermaid
stateDiagram-v2
    [*] --> Healthy
    Healthy --> Delayed: queue lag rises
    Delayed --> Recovering: user triggers retry or replay
    Recovering --> Healthy: backlog drained
    Delayed --> Intervention: dead-letter threshold reached
    Intervention --> Recovering: user resolves and retries
```

## 10) Feature map by user touchpoint and milestone

| Feature         | Primary user surface                      | Runtime components behind it                       | Main milestones |
| --------------- | ----------------------------------------- | -------------------------------------------------- | --------------- |
| Human chat      | Session timeline and composer             | Milestone 3 routing plus Milestone 4 queue         | 5, 3, 4         |
| Heartbeats      | Agent settings schedule panel             | Mobile scheduler plus shared ingestion path        | 6, 4, 5         |
| Cron schedules  | Schedule editor and diagnostics           | Trigger planner plus shared ingestion path         | 7, 4, 5         |
| Internal hooks  | Runtime automation settings and inspector | Hook engine plus queue and ancestry tracking       | 8, 4, 5         |
| Webhooks        | Integrations panel                        | Relay API plus Milestone 3 session routing         | 9, relay, 3     |
| Multi agent     | Agent workspace and handoff trace         | Routing allowlists plus queue-backed orchestration | 10, 4, 11       |
| Memory          | Memory inspector and controls             | Scoped storage plus compaction jobs                | 11              |
| Tooling sandbox | Permissions center and confirmations      | Policy engine plus tool registry and audit logs    | 12              |
| Diagnostics     | Inspector and status views                | Queue state, run results, relay delivery metadata  | 4, 9, 12        |

## 11) Cross milestone references

- Milestone 1 architecture mapping: `/experiments/plans/flutter-openclaw-m1-architecture-mapping`
- Milestone 2 domain model: `/experiments/plans/flutter-openclaw-m2-foundation-domain-model`
- Milestone 3 gateway and sessions: `/experiments/plans/flutter-openclaw-m3-gateway-router-sessions`
- Milestone 4 durable queue: `/experiments/plans/flutter-openclaw-m4-durable-queue-loop`
- Milestone 5 human message UX: `/experiments/plans/flutter-openclaw-m5-human-message-ux`
- Milestone 6 heartbeats: `/experiments/plans/flutter-openclaw-m6-heartbeats`
- Milestone 7 cron jobs: `/experiments/plans/flutter-openclaw-m7-cron-jobs`
- Milestone 8 internal hooks: `/experiments/plans/flutter-openclaw-m8-internal-hooks`
- Milestone 9 webhooks: `/experiments/plans/flutter-openclaw-m9-webhooks`
- Milestone 10 agent-to-agent messaging: `/experiments/plans/flutter-openclaw-m10-agent-to-agent`
- Milestone 11 memory and context: `/experiments/plans/flutter-openclaw-m11-memory-context`
- Milestone 12 tooling and capability sandbox: `/experiments/plans/flutter-openclaw-m12-tooling-sandbox`
- Relay architecture: `/experiments/plans/flutter-openclaw-relay-architecture`
