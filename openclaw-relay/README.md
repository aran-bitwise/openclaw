# OpenClaw Relay (Milestone 9)

Minimal relay service for receiving signed webhooks and exposing pending events to mobile clients.

## Endpoints

- `POST /webhooks/generic` (HMAC SHA-256 via `x-relay-signature`)
- `GET /events/pending?since=<ms>&limit=<n>` (bearer auth)
- `POST /events/:id/ack` (bearer auth, idempotent)
- `GET /health`

## Environment

- `RELAY_WEBHOOK_SECRET` (default: `dev-webhook-secret`)
- `RELAY_MOBILE_TOKEN` (default: `dev-mobile-token`)
- `RELAY_STORE_PATH` (default: `openclaw-relay/.data/events.json`)
- `PORT` (default: `8787`)

## Run

```bash
cd openclaw-relay
npm start
```

## Security model in M9

- Incoming provider webhooks are verified with shared-secret HMAC SHA-256.
- Mobile fetch/ack calls use a bearer token.
- Payload is persisted in a log-safe redacted form.
