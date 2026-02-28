import path from 'node:path';

import { createRelayServer } from './server.js';

const port = Number(process.env.PORT || 8787);
const webhookSecret = process.env.RELAY_WEBHOOK_SECRET || 'dev-webhook-secret';
const mobileBearerToken = process.env.RELAY_MOBILE_TOKEN || 'dev-mobile-token';
const storePath = process.env.RELAY_STORE_PATH || path.resolve('openclaw-relay/.data/events.json');

const server = createRelayServer({
  webhookSecret,
  mobileBearerToken,
  storePath,
  defaultAgentId: process.env.RELAY_DEFAULT_AGENT_ID || 'default-agent',
  defaultChannelId: process.env.RELAY_DEFAULT_CHANNEL_ID || 'relay-webhook',
  defaultSessionId: process.env.RELAY_DEFAULT_SESSION_ID || 'relay-session',
});

server.listen(port, () => {
  console.log(`openclaw-relay listening on http://localhost:${port}`);
});
