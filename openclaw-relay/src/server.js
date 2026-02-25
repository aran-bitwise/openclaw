import crypto from 'node:crypto';
import http from 'node:http';
import { URL } from 'node:url';

import { RelayStore } from './store.js';
import { verifySignature } from './signer.js';

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (d) => chunks.push(d));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function toSafePayload(payload) {
  return JSON.parse(JSON.stringify(payload, (_key, value) => {
    if (typeof value === 'string' && value.length > 512) {
      return `${value.slice(0, 512)}...[truncated]`;
    }
    return value;
  }));
}

function parseRouteHints(payload, headers, defaultAgentId, defaultChannelId, defaultSessionId) {
  return {
    agentId: payload.agentId || headers['x-openclaw-agent-id'] || defaultAgentId,
    channelId: payload.channelId || headers['x-openclaw-channel-id'] || defaultChannelId,
    sessionId: payload.sessionId || headers['x-openclaw-session-id'] || defaultSessionId,
  };
}

export function createRelayServer({
  webhookSecret,
  mobileBearerToken,
  storePath,
  defaultAgentId = 'default-agent',
  defaultChannelId = 'relay-webhook',
  defaultSessionId = 'relay-session',
}) {
  const store = new RelayStore(storePath);

  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url || '/', `http://${req.headers.host}`);

      if (url.pathname === '/health' && req.method === 'GET') {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
        return;
      }

      if (url.pathname === '/webhooks/generic' && req.method === 'POST') {
        const rawBody = await readBody(req);
        const signature = req.headers['x-relay-signature'];
        if (!verifySignature(webhookSecret, Array.isArray(signature) ? signature[0] : signature, rawBody)) {
          res.writeHead(401, { 'content-type': 'application/json' });
          res.end(JSON.stringify({ error: 'invalid_signature' }));
          return;
        }

        const payload = rawBody ? JSON.parse(rawBody) : {};
        const deliveryId = req.headers['x-delivery-id'];
        const idempotencyKey = Array.isArray(deliveryId)
          ? deliveryId[0]
          : deliveryId || crypto.createHash('sha256').update(rawBody).digest('hex');
        const relayEventId = `relay-${idempotencyKey}`;

        const hints = parseRouteHints(payload, req.headers, defaultAgentId, defaultChannelId, defaultSessionId);

        store.upsertPending({
          relayEventId,
          receivedAt: Date.now(),
          source: payload.source || 'generic-webhook',
          idempotencyKey,
          ...hints,
          payload: toSafePayload(payload),
          state: 'pending',
        });

        res.writeHead(202, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ accepted: true, relayEventId }));
        return;
      }

      if (url.pathname === '/events/pending' && req.method === 'GET') {
        const auth = req.headers.authorization || '';
        if (auth !== `Bearer ${mobileBearerToken}`) {
          res.writeHead(401, { 'content-type': 'application/json' });
          res.end(JSON.stringify({ error: 'unauthorized' }));
          return;
        }

        const since = Number(url.searchParams.get('since') || 0);
        const limit = Number(url.searchParams.get('limit') || 50);
        const events = store.listPending({ since, limit });

        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ events }));
        return;
      }

      if (url.pathname.startsWith('/events/') && url.pathname.endsWith('/ack') && req.method === 'POST') {
        const auth = req.headers.authorization || '';
        if (auth !== `Bearer ${mobileBearerToken}`) {
          res.writeHead(401, { 'content-type': 'application/json' });
          res.end(JSON.stringify({ error: 'unauthorized' }));
          return;
        }

        const relayEventId = url.pathname.split('/')[2];
        const result = store.ackEvent(relayEventId);
        if (!result.ok) {
          res.writeHead(404, { 'content-type': 'application/json' });
          res.end(JSON.stringify({ error: result.reason }));
          return;
        }

        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ ok: true, alreadyAcked: result.alreadyAcked }));
        return;
      }

      res.writeHead(404, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'not_found' }));
    } catch (error) {
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'server_error', message: String(error) }));
    }
  });

  return server;
}
