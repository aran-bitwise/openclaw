import test from 'node:test';
import assert from 'node:assert/strict';

import { computeSignature, verifySignature } from '../src/signer.js';

test('verifySignature accepts valid signature', () => {
  const secret = 's3cr3t';
  const body = '{"hello":"world"}';
  const sig = computeSignature(secret, body);

  assert.equal(verifySignature(secret, sig, body), true);
});

test('verifySignature rejects invalid signature', () => {
  const secret = 's3cr3t';
  const body = '{"hello":"world"}';

  assert.equal(verifySignature(secret, 'sha256=deadbeef', body), false);
});
