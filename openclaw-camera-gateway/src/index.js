import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { createCameraGatewayServer } from './server.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const port = Number(process.env.PORT || process.env.OPENCLAW_CAMERA_GATEWAY_PORT || 8799);
const token = process.env.OPENCLAW_CAMERA_GATEWAY_TOKEN || 'demo-token';
const publicBaseUrl = process.env.OPENCLAW_CAMERA_GATEWAY_PUBLIC_BASE_URL || `http://10.0.2.2:${port}`;
const fixturesDir = path.resolve(__dirname, '..', 'fixtures');

const server = createCameraGatewayServer({
  token,
  fixturesDir,
  publicBaseUrl,
});

server.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`openclaw-camera-gateway listening on :${port}`);
});
