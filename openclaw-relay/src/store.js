import fs from 'node:fs';
import path from 'node:path';

export class RelayStore {
  constructor(filePath) {
    this.filePath = filePath;
    const dir = path.dirname(filePath);
    fs.mkdirSync(dir, { recursive: true });
    if (!fs.existsSync(filePath)) {
      fs.writeFileSync(filePath, JSON.stringify({ events: [] }, null, 2));
    }
  }

  _read() {
    const raw = fs.readFileSync(this.filePath, 'utf8');
    return JSON.parse(raw);
  }

  _write(data) {
    fs.writeFileSync(this.filePath, JSON.stringify(data, null, 2));
  }

  upsertPending(event) {
    const data = this._read();
    const index = data.events.findIndex((e) => e.relayEventId === event.relayEventId);
    if (index >= 0) {
      data.events[index] = { ...data.events[index], ...event };
    } else {
      data.events.push(event);
    }
    this._write(data);
  }

  listPending({ since = 0, limit = 50 }) {
    const data = this._read();
    return data.events
      .filter((e) => e.state === 'pending' && e.receivedAt >= since)
      .sort((a, b) => a.receivedAt - b.receivedAt)
      .slice(0, limit);
  }

  ackEvent(id) {
    const data = this._read();
    const index = data.events.findIndex((e) => e.relayEventId === id);
    if (index === -1) {
      return { ok: false, reason: 'not_found' };
    }

    if (data.events[index].state === 'acked') {
      return { ok: true, alreadyAcked: true };
    }

    data.events[index].state = 'acked';
    data.events[index].ackedAt = Date.now();
    this._write(data);
    return { ok: true, alreadyAcked: false };
  }
}
