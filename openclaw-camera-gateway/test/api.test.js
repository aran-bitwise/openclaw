import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { createCameraGatewayServer } from '../src/server.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fixturesDir = path.resolve(__dirname, '..', 'fixtures');

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

async function withServer(options, fn) {
  const server = createCameraGatewayServer({
    token: 'demo-token',
    fixturesDir,
    publicBaseUrl: 'http://10.0.2.2:8799',
    now: () => new Date('2026-01-01T00:00:00.000Z'),
    ...options,
  });
  await new Promise((resolve) => server.listen(0, resolve));
  const port = server.address().port;
  try {
    await fn(port);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('/health returns ok without auth', async () => {
  await withServer({}, async (port) => {
    const res = await fetch(`http://127.0.0.1:${port}/health`);
    assert.equal(res.status, 200);
    const json = await res.json();
    assert.equal(json.ok, true);
    assert.equal(json.service, 'openclaw-camera-gateway');
  });
});

test('/cameras requires auth', async () => {
  await withServer({}, async (port) => {
    const unauth = await fetch(`http://127.0.0.1:${port}/cameras`);
    assert.equal(unauth.status, 401);

    const auth = await fetch(`http://127.0.0.1:${port}/cameras`, {
      headers: { authorization: 'Bearer demo-token' },
    });
    assert.equal(auth.status, 200);
    const body = await auth.json();
    assert.equal(Array.isArray(body.cameras), true);
    assert.equal(body.cameras.length, 2);
  });
});

test('/cameras/:id/snapshot requires auth and unknown camera returns 404', async () => {
  await withServer({}, async (port) => {
    const unauth = await fetch(`http://127.0.0.1:${port}/cameras/cam-living/snapshot`);
    assert.equal(unauth.status, 401);

    const missing = await fetch(`http://127.0.0.1:${port}/cameras/unknown/snapshot`, {
      headers: { authorization: 'Bearer demo-token' },
    });
    assert.equal(missing.status, 404);
  });
});

test('snapshot checksum matches fixture content', async () => {
  await withServer({}, async (port) => {
    const res = await fetch(`http://127.0.0.1:${port}/cameras/cam-living/snapshot?mode=test_fall`, {
      headers: { authorization: 'Bearer demo-token' },
    });
    assert.equal(res.status, 200);
    const json = await res.json();
    const fixture = fs.readFileSync(path.join(fixturesDir, 'fall.jpg'));
    assert.equal(json.checksum, sha256(fixture));
    assert.equal(json.capturedAt, '2026-01-01T00:00:00.000Z');
  });
});

test('snapshotUrl uses OPENCLAW_CAMERA_GATEWAY_PUBLIC_BASE_URL equivalent override', async () => {
  await withServer({ publicBaseUrl: 'http://10.0.2.2:9900' }, async (port) => {
    const res = await fetch(`http://127.0.0.1:${port}/cameras/cam-bedroom/snapshot?mode=test_ok`, {
      headers: { authorization: 'Bearer demo-token' },
    });
    const json = await res.json();
    assert.equal(json.snapshotUrl, 'http://10.0.2.2:9900/fixtures/ok.jpg');
  });
});

test('fixtures are served and return 200', async () => {
  await withServer({}, async (port) => {
    const res = await fetch(`http://127.0.0.1:${port}/fixtures/ok.jpg`);
    assert.equal(res.status, 200);
    const body = await res.text();
    assert.equal(body.includes('DEMO_OK_IMAGE_PLACEHOLDER'), true);
  });
});
