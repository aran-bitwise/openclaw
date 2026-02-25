import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { createRelayServer } from '../src/server.js';
import { computeSignature } from '../src/signer.js';

function makeTempStore() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'openclaw-relay-'));
  return path.join(dir, 'events.json');
}

test('pending and ack lifecycle is idempotent', async () => {
  const storePath = makeTempStore();
  const server = createRelayServer({
    webhookSecret: 'whsec',
    mobileBearerToken: 'mobile-token',
    storePath,
  });

  await new Promise((resolve) => server.listen(0, resolve));
  const port = server.address().port;

  try {
    const body = JSON.stringify({ source: 'unit-test', hello: 'world' });
    const sig = computeSignature('whsec', body);

    const ingest = await fetch(`http://127.0.0.1:${port}/webhooks/generic`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-relay-signature': sig,
        'x-delivery-id': 'delivery-1',
      },
      body,
    });
    assert.equal(ingest.status, 202);

    const pending = await fetch(`http://127.0.0.1:${port}/events/pending?since=0&limit=10`, {
      headers: { authorization: 'Bearer mobile-token' },
    });
    assert.equal(pending.status, 200);
    const pendingJson = await pending.json();
    assert.equal(pendingJson.events.length, 1);

    const id = pendingJson.events[0].relayEventId;
    const ack1 = await fetch(`http://127.0.0.1:${port}/events/${id}/ack`, {
      method: 'POST',
      headers: { authorization: 'Bearer mobile-token' },
    });
    assert.equal(ack1.status, 200);

    const ack2 = await fetch(`http://127.0.0.1:${port}/events/${id}/ack`, {
      method: 'POST',
      headers: { authorization: 'Bearer mobile-token' },
    });
    assert.equal(ack2.status, 200);

    const pending2 = await fetch(`http://127.0.0.1:${port}/events/pending?since=0&limit=10`, {
      headers: { authorization: 'Bearer mobile-token' },
    });
    const pendingJson2 = await pending2.json();
    assert.equal(pendingJson2.events.length, 0);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
