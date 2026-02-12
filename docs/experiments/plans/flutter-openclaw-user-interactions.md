---
summary: "User interaction map for Flutter OpenClaw mobile features"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-12"
title: "Flutter OpenClaw Mobile User Interaction Flows"
---

# Flutter OpenClaw Mobile User Interaction Flows

This document outlines how a user interacts with the app to use major OpenClaw-style features,
with Mermaid diagrams that map user actions to the relay, routing, queue, and timeline runtime
contracts from Milestones 1 to 6.

## 1) First run and agent setup flow

User goals:

- install app and complete onboarding
- create first agent profile
- connect at least one channel and local session
- enable runtime inputs (message, heartbeat, schedules)

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

## 3) Heartbeat interaction flow

User goals:

- configure periodic agent check-ins
- ensure heartbeats use same processing path as messages
- avoid noise with suppression behavior

```mermaid
sequenceDiagram
    participant U as User
    participant CFG as Heartbeat Settings UI
    participant SCH as Mobile Scheduler
    participant M3 as GatewayRouter and Session Service
    participant M4 as Durable Queue and Loop
    participant UI as Timeline UI

    U->>CFG: Enable heartbeat and set interval
    CFG->>SCH: Register platform schedule
    SCH->>M3: ingestInboundEvent(heartbeat envelope)
    M3->>M4: enqueue heartbeat event
    M4->>M4: process and evaluate suppression token
    M4-->>UI: publish queued, processing, completed
    UI-->>U: Show heartbeat item and source badge
```

## 4) Webhook and relay interaction flow

User goals:

- connect external providers that can reach internet endpoints
- have events delivered safely to mobile via relay
- see events merged in session timeline with source metadata

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

## 5) Multi agent handoff interaction flow

User goals:

- run specialist agents for focused tasks
- keep memory and session boundaries clear
- inspect handoff lineage when results are produced

```mermaid
flowchart LR
    U[User request] --> A[Agent A Research]
    A --> H[Handoff message with route allowlist]
    H --> B[Agent B Writer]
    B --> T[Session timeline with ancestry]
    T --> U2[User reviews output]
```

## 6) User visible runtime controls

The app should expose clear controls for key runtime operations:

- pause or resume processing loop
- retry failed queue items
- inspect dead-letter items and reason
- replay relay fetch on demand
- view per-session event ancestry and source type

```mermaid
stateDiagram-v2
    [*] --> Healthy
    Healthy --> Delayed: queue lag rises
    Delayed --> Recovering: user triggers retry or replay
    Recovering --> Healthy: backlog drained
    Delayed --> Intervention: dead-letter threshold reached
    Intervention --> Recovering: user resolves and retries
```

## 7) Feature map by user touchpoint

| Feature     | Primary user surface              | Runtime components behind it                           |
| ----------- | --------------------------------- | ------------------------------------------------------ |
| Human chat  | Session timeline and composer     | Milestone 3 routing plus Milestone 4 queue             |
| Heartbeats  | Agent settings schedule panel     | Mobile scheduler plus Milestone 3 and 4 ingestion path |
| Webhooks    | Integrations panel                | Relay API plus Milestone 3 session routing             |
| Multi agent | Agent workspace and handoff trace | Routing allowlists plus memory scopes                  |
| Diagnostics | Inspector and status views        | Queue state, run results, relay delivery metadata      |

## 8) Cross milestone references

- Milestone 1 architecture mapping: `/experiments/plans/flutter-openclaw-m1-architecture-mapping`
- Milestone 2 domain model: `/experiments/plans/flutter-openclaw-m2-foundation-domain-model`
- Milestone 3 gateway and sessions: `/experiments/plans/flutter-openclaw-m3-gateway-router-sessions`
- Milestone 4 durable queue: `/experiments/plans/flutter-openclaw-m4-durable-queue-loop`
- Milestone 5 human message UX: `/experiments/plans/flutter-openclaw-m5-human-message-ux`
- Milestone 6 heartbeats: `/experiments/plans/flutter-openclaw-m6-heartbeats`
- Relay architecture: `/experiments/plans/flutter-openclaw-relay-architecture`
