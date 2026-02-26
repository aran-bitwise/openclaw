# openclaw-camera-gateway

A deterministic demo camera snapshot normalization service for the OpenClaw mobile aged care safety check flow.

It returns **snapshot URLs + metadata only** and intentionally does not return image bytes in API payloads.

## What this service is for

- Provides a stable camera list fixture for demos.
- Provides deterministic snapshot metadata by camera and mode.
- Lets Android emulator based mobile demos fetch camera snapshots through `10.0.2.2`.

## Environment

- `OPENCLAW_CAMERA_GATEWAY_TOKEN` (required for protected endpoints; default `demo-token`)
- `OPENCLAW_CAMERA_GATEWAY_PORT` or `PORT` (default `8799`)
- `OPENCLAW_CAMERA_GATEWAY_PUBLIC_BASE_URL` (default `http://10.0.2.2:<PORT>`)

## Run locally

```bash
cd openclaw-camera-gateway
OPENCLAW_CAMERA_GATEWAY_TOKEN=demo-token npm start
```

By default the service listens on `8799`.

## Test

```bash
cd openclaw-camera-gateway
npm test
```

## Endpoints

### `GET /health`

No auth required.

### `GET /cameras`

Requires:

```http
Authorization: Bearer <token>
```

Returns deterministic camera fixture data.

### `GET /cameras/:id/snapshot?mode=latest|test_ok|test_fall|test_uncertain`

Requires:

```http
Authorization: Bearer <token>
```

Returns metadata only:

- `snapshotUrl`
- `capturedAt`
- `checksum`
- `quality`
- `mode`

## Example curl

List cameras:

```bash
curl -s \
  -H "Authorization: Bearer demo-token" \
  "http://127.0.0.1:8799/cameras"
```

Fetch fall-test snapshot metadata:

```bash
curl -s \
  -H "Authorization: Bearer demo-token" \
  "http://127.0.0.1:8799/cameras/cam-living/snapshot?mode=test_fall"
```

## Android emulator note

For the emulator, mobile should use:

- `http://10.0.2.2:8799`

You can override generated snapshot URLs with `OPENCLAW_CAMERA_GATEWAY_PUBLIC_BASE_URL`.

## Privacy and logging expectations

- API returns snapshot URLs + metadata only.
- This service does not store image bytes in audit logs.
- Token auth is required on all endpoints except `/health`.
