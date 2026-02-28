import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { URL } from 'node:url';

function readFixture(filePath) {
  return fs.readFileSync(filePath);
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { 'content-type': 'application/json' });
  res.end(JSON.stringify(payload));
}

function sendFile(res, filePath) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    sendJson(res, 404, { error: 'not_found' });
    return;
  }
  res.writeHead(200, { 'content-type': 'image/jpeg' });
  fs.createReadStream(filePath).pipe(res);
}

export function createCameraGatewayServer({
  token,
  fixturesDir,
  publicBaseUrl,
  version = '0.1.0',
  now = () => new Date(),
}) {
  const camerasFixturePath = path.join(fixturesDir, 'cameras.json');
  const camerasPayload = JSON.parse(readFixture(camerasFixturePath).toString('utf8'));

  const modeToFile = {
    latest: 'ok.jpg',
    test_ok: 'ok.jpg',
    test_fall: 'fall.jpg',
    test_uncertain: 'uncertain.jpg',
  };

  const cameraById = new Map(camerasPayload.cameras.map((camera) => [camera.cameraId, camera]));

  const requireAuth = (req, res) => {
    const auth = req.headers.authorization || '';
    if (auth !== `Bearer ${token}`) {
      sendJson(res, 401, { error: 'unauthorized' });
      return false;
    }
    return true;
  };

  return http.createServer((req, res) => {
    try {
      const url = new URL(req.url || '/', `http://${req.headers.host}`);
      const pathname = url.pathname;

      if (pathname === '/health' && req.method === 'GET') {
        sendJson(res, 200, {
          ok: true,
          service: 'openclaw-camera-gateway',
          version,
          time: now().toISOString(),
        });
        return;
      }

      if (pathname.startsWith('/fixtures/') && req.method === 'GET') {
        const rel = pathname.replace('/fixtures/', '');
        const full = path.normalize(path.join(fixturesDir, rel));
        if (!full.startsWith(path.normalize(fixturesDir))) {
          sendJson(res, 400, { error: 'invalid_path' });
          return;
        }
        sendFile(res, full);
        return;
      }

      if (pathname === '/cameras' && req.method === 'GET') {
        if (!requireAuth(req, res)) return;
        sendJson(res, 200, camerasPayload);
        return;
      }

      if (pathname.startsWith('/cameras/') && pathname.endsWith('/snapshot') && req.method === 'GET') {
        if (!requireAuth(req, res)) return;

        const cameraId = pathname.split('/')[2];
        const camera = cameraById.get(cameraId);
        if (!camera) {
          sendJson(res, 404, { error: 'camera_not_found' });
          return;
        }

        const mode = url.searchParams.get('mode') || 'latest';
        const fixture = modeToFile[mode] || modeToFile.latest;
        const fixturePath = path.join(fixturesDir, fixture);
        const bytes = readFixture(fixturePath);
        sendJson(res, 200, {
          cameraId,
          capturedAt: now().toISOString(),
          snapshotUrl: `${publicBaseUrl}/fixtures/${fixture}`,
          checksum: sha256(bytes),
          quality: { w: 1280, h: 720, format: 'jpg' },
          mode,
        });
        return;
      }

      sendJson(res, 404, { error: 'not_found' });
    } catch (error) {
      sendJson(res, 500, { error: 'server_error', message: String(error) });
    }
  });
}
