export type HookType = "app.startup" | "turn.start" | "turn.end" | "runtime.reset" | "memory.flush";

export type HookEvent = {
  hookType: HookType;
  sessionId: string;
  idempotencyKey: string;
  createdAt: number;
};

export class InternalHooksReference {
  emit(params: { hookType: HookType; sessionId: string; createdAt: number }): HookEvent {
    return {
      hookType: params.hookType,
      sessionId: params.sessionId,
      idempotencyKey: `${params.hookType}:${params.sessionId}:${params.createdAt}`,
      createdAt: params.createdAt,
    };
  }
}
