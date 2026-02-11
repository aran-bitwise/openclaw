---
summary: "Production relay architecture for internet-to-mobile event delivery"
owner: "openclaw"
status: "draft"
last_updated: "2026-02-10"
title: "Flutter OpenClaw Mobile — Relay API Architecture"
---

# Flutter OpenClaw Mobile — Relay API Architecture

## Why a relay is required

For production mobile behavior, the app cannot reliably expose public inbound webhook endpoints.
Instead, internet sources deliver to a relay API, and mobile devices fetch pending events when
awake.

Constraints addressed:

- iOS background execution is opportunistic.
- Android background jobs are deferred under OS power policies.
- NAT/mobile networks make inbound device webhooks unreliable.

## Control-plane flow

1. External provider sends event to Relay API.
2. Relay validates signature/auth and normalizes payload.
3. Relay stores pending event with idempotency key and target device/agent.
4. Relay triggers APNs/FCM or waits for client poll.
5. Mobile app fetches pending relay events.
6. Mobile app ingests each event through `GatewayRouter` + session service.
7. Mobile app acks delivery; relay marks event delivered.

## Reference implementation in this repository

Relay reference code:

- `src/experiments/flutter-relay/api-relay-reference.ts`
- `src/experiments/flutter-relay/api-relay-reference.test.ts`

Integrated references:

- Milestone 3 ingress/service: `src/experiments/flutter-m3/*`
- Milestone 2 persistence/domain: `src/experiments/flutter-m2/*`
- Milestone 1 normalization model: `src/experiments/flutter-m1/*`

## Core contracts

### Relay ingress contract

- `source`: provider/channel metadata
- `target`: agent + device routing metadata
- `eventType`: normalized event type
- `payload`: provider payload
- `idempotencyKey`: dedupe key
- `receivedAt`: deterministic ordering timestamp

### Mobile fetch/ack contract

- `fetchPending(deviceId, cursor, limit)`
- `ackDelivered(relayEventId)`
- replay-safe idempotency through stable keys

## Production notes

- Relay must be stateless at compute layer and durable at storage layer.
- Relay should support per-tenant encryption and signed webhook verification.
- Mobile should use short background fetch windows and process bounded batches.
- Observability should include relay event IDs correlated with mobile timeline events.
