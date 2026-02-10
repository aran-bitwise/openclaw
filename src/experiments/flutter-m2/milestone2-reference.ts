export type Milestone2SchemaVersion = 1 | 2;

export type EventType =
  | "message"
  | "heartbeat"
  | "cron"
  | "internalHook"
  | "webhook"
  | "agentMessage";

export type EventStatus = "queued" | "processing" | "completed" | "failed" | "deadLetter";

export type MemoryScope = "global" | "agent" | "session";

export type AgentProfile = {
  id: string;
  name: string;
  defaultModel?: string;
  systemPrompt?: string;
  isEnabled: boolean;
  createdAt: number;
  updatedAt: number;
};

export type Session = {
  id: string;
  agentId: string;
  channelId: string;
  sessionKey: string;
  accountId?: string;
  threadId?: string;
  title?: string;
  lastMessageAt?: number;
  createdAt: number;
  updatedAt: number;
};

export type Event = {
  id: string;
  sessionId: string;
  type: EventType;
  source: string;
  payload: Record<string, unknown>;
  status: EventStatus;
  idempotencyKey?: string;
  createdAt: number;
  updatedAt: number;
};

export type MemoryEntry = {
  id: string;
  scope: MemoryScope;
  content: string;
  agentId?: string;
  sessionId?: string;
  tags: string[];
  createdAt: number;
  updatedAt: number;
};

export type ToolInvocation = {
  id: string;
  runId: string;
  toolName: string;
  request: Record<string, unknown>;
  response?: Record<string, unknown>;
  status: "queued" | "running" | "completed" | "failed";
  createdAt: number;
  updatedAt: number;
};

export type RunResult = {
  id: string;
  eventId: string;
  sessionId: string;
  finalText?: string;
  usage?: Record<string, unknown>;
  status: "completed" | "failed";
  errorText?: string;
  createdAt: number;
  updatedAt: number;
};

export type Milestone2StoreV2 = {
  schemaVersion: 2;
  agents: AgentProfile[];
  sessions: Session[];
  events: Event[];
  memoryEntries: MemoryEntry[];
  toolInvocations: ToolInvocation[];
  runResults: RunResult[];
};

type Milestone2StoreV1 = {
  schemaVersion: 1;
  agents: AgentProfile[];
  sessions: Omit<Session, "accountId" | "threadId">[];
  events: Event[];
  memoryEntries: MemoryEntry[];
  toolInvocations: ToolInvocation[];
  runResults: RunResult[];
};

export type Milestone2StoreAny = Milestone2StoreV1 | Milestone2StoreV2;

function assertNonEmpty(name: string, value: string | undefined): string {
  const v = value?.trim() ?? "";
  if (!v) {
    throw new Error(`${name} is required`);
  }
  return v;
}

function parseTs(input?: number): number {
  if (typeof input === "number" && Number.isFinite(input)) {
    return Math.floor(input);
  }
  return Date.now();
}

export function buildSessionKey(params: {
  agentId: string;
  channelId: string;
  sessionHint?: string;
}): string {
  const agentId = assertNonEmpty("agentId", params.agentId);
  const channelId = assertNonEmpty("channelId", params.channelId).toLowerCase();
  const hint = (params.sessionHint?.trim() || "main").toLowerCase();
  return `agent:${agentId}:${channelId}:${hint}`;
}

export function createAgentProfile(input: {
  id: string;
  name: string;
  defaultModel?: string;
  systemPrompt?: string;
  isEnabled?: boolean;
  now?: number;
}): AgentProfile {
  const now = parseTs(input.now);
  return {
    id: assertNonEmpty("id", input.id),
    name: assertNonEmpty("name", input.name),
    defaultModel: input.defaultModel?.trim() || undefined,
    systemPrompt: input.systemPrompt?.trim() || undefined,
    isEnabled: input.isEnabled ?? true,
    createdAt: now,
    updatedAt: now,
  };
}

export function createSession(input: {
  id: string;
  agentId: string;
  channelId: string;
  sessionKey?: string;
  accountId?: string;
  threadId?: string;
  title?: string;
  now?: number;
}): Session {
  const now = parseTs(input.now);
  const agentId = assertNonEmpty("agentId", input.agentId);
  const channelId = assertNonEmpty("channelId", input.channelId);
  return {
    id: assertNonEmpty("id", input.id),
    agentId,
    channelId,
    sessionKey: input.sessionKey ?? buildSessionKey({ agentId, channelId }),
    accountId: input.accountId?.trim() || undefined,
    threadId: input.threadId?.trim() || undefined,
    title: input.title?.trim() || undefined,
    createdAt: now,
    updatedAt: now,
  };
}

export function createEvent(input: {
  id: string;
  sessionId: string;
  type: EventType;
  source: string;
  payload?: Record<string, unknown>;
  status?: EventStatus;
  idempotencyKey?: string;
  now?: number;
}): Event {
  const now = parseTs(input.now);
  return {
    id: assertNonEmpty("id", input.id),
    sessionId: assertNonEmpty("sessionId", input.sessionId),
    type: input.type,
    source: assertNonEmpty("source", input.source),
    payload: input.payload ?? {},
    status: input.status ?? "queued",
    idempotencyKey: input.idempotencyKey?.trim() || undefined,
    createdAt: now,
    updatedAt: now,
  };
}

export function createEmptyStore(): Milestone2StoreV2 {
  return {
    schemaVersion: 2,
    agents: [],
    sessions: [],
    events: [],
    memoryEntries: [],
    toolInvocations: [],
    runResults: [],
  };
}

export function migrateStore(input: Milestone2StoreAny): Milestone2StoreV2 {
  if (input.schemaVersion === 2) {
    return {
      ...input,
      sessions: input.sessions.map((s) => ({ ...s })),
      agents: input.agents.map((a) => ({ ...a })),
      events: input.events.map((e) => ({ ...e })),
      memoryEntries: input.memoryEntries.map((m) => ({ ...m, tags: [...m.tags] })),
      toolInvocations: input.toolInvocations.map((t) => ({ ...t })),
      runResults: input.runResults.map((r) => ({ ...r })),
    };
  }

  return {
    schemaVersion: 2,
    agents: input.agents.map((a) => ({ ...a })),
    sessions: input.sessions.map((s) => ({ ...s, accountId: undefined, threadId: undefined })),
    events: input.events.map((e) => ({ ...e })),
    memoryEntries: input.memoryEntries.map((m) => ({ ...m, tags: [...m.tags] })),
    toolInvocations: input.toolInvocations.map((t) => ({ ...t })),
    runResults: input.runResults.map((r) => ({ ...r })),
  };
}

export function serializeStore(store: Milestone2StoreV2): string {
  return JSON.stringify(store);
}

export function deserializeStore(json: string): Milestone2StoreV2 {
  const parsed = JSON.parse(json) as Partial<Milestone2StoreAny>;
  if (parsed.schemaVersion !== 1 && parsed.schemaVersion !== 2) {
    throw new Error("Unsupported schemaVersion");
  }

  return migrateStore({
    schemaVersion: parsed.schemaVersion,
    agents: Array.isArray(parsed.agents) ? (parsed.agents as AgentProfile[]) : [],
    sessions: Array.isArray(parsed.sessions)
      ? (parsed.sessions as Milestone2StoreAny["sessions"])
      : [],
    events: Array.isArray(parsed.events) ? (parsed.events as Event[]) : [],
    memoryEntries: Array.isArray(parsed.memoryEntries)
      ? (parsed.memoryEntries as MemoryEntry[])
      : [],
    toolInvocations: Array.isArray(parsed.toolInvocations)
      ? (parsed.toolInvocations as ToolInvocation[])
      : [],
    runResults: Array.isArray(parsed.runResults) ? (parsed.runResults as RunResult[]) : [],
  });
}

export class Milestone2Repository {
  private store: Milestone2StoreV2;

  constructor(initial?: Milestone2StoreAny) {
    this.store = initial ? migrateStore(initial) : createEmptyStore();
  }

  listAgents(): AgentProfile[] {
    return this.store.agents.map((a) => ({ ...a }));
  }

  createAgent(agent: AgentProfile): AgentProfile {
    if (this.store.agents.some((a) => a.id === agent.id)) {
      throw new Error(`Agent already exists: ${agent.id}`);
    }
    this.store.agents.push({ ...agent });
    return { ...agent };
  }

  updateAgent(
    id: string,
    patch: Partial<Pick<AgentProfile, "name" | "defaultModel" | "systemPrompt" | "isEnabled">>,
  ): AgentProfile {
    const idx = this.store.agents.findIndex((a) => a.id === id);
    if (idx < 0) {
      throw new Error(`Agent not found: ${id}`);
    }
    const current = this.store.agents[idx];
    const next: AgentProfile = {
      ...current,
      name: patch.name?.trim() || current.name,
      defaultModel:
        patch.defaultModel === undefined
          ? current.defaultModel
          : patch.defaultModel?.trim() || undefined,
      systemPrompt:
        patch.systemPrompt === undefined
          ? current.systemPrompt
          : patch.systemPrompt?.trim() || undefined,
      isEnabled: patch.isEnabled ?? current.isEnabled,
      updatedAt: Date.now(),
    };
    this.store.agents[idx] = next;
    return { ...next };
  }

  createSession(session: Session): Session {
    if (!this.store.agents.some((agent) => agent.id === session.agentId)) {
      throw new Error(`Unknown agentId: ${session.agentId}`);
    }
    if (this.store.sessions.some((s) => s.id === session.id)) {
      throw new Error(`Session already exists: ${session.id}`);
    }
    this.store.sessions.push({ ...session });
    return { ...session };
  }

  listSessionsByAgent(agentId: string): Session[] {
    return this.store.sessions
      .filter((s) => s.agentId === agentId)
      .map((s) => ({ ...s }))
      .toSorted((a, b) => b.updatedAt - a.updatedAt);
  }

  appendEvent(event: Event): Event {
    if (!this.store.sessions.some((s) => s.id === event.sessionId)) {
      throw new Error(`Unknown sessionId: ${event.sessionId}`);
    }
    if (
      event.idempotencyKey &&
      this.store.events.some((existing) => existing.idempotencyKey === event.idempotencyKey)
    ) {
      throw new Error(`Duplicate idempotencyKey: ${event.idempotencyKey}`);
    }
    this.store.events.push({ ...event });
    return { ...event };
  }

  exportJson(): string {
    return serializeStore(this.store);
  }

  snapshot(): Milestone2StoreV2 {
    return deserializeStore(this.exportJson());
  }
}
