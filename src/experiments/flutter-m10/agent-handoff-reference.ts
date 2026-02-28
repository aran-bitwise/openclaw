export type AgentHandoff = {
  fromAgentId: string;
  toAgentId: string;
  taskPayload: Record<string, unknown>;
  traceId: string;
};

export class AgentHandoffReference {
  private readonly allowlist = new Set<string>();

  allowRoute(fromAgentId: string, toAgentId: string): void {
    this.allowlist.add(`${fromAgentId}->${toAgentId}`);
  }

  createHandoff(
    params: Omit<AgentHandoff, "traceId"> & { traceId?: string },
  ): AgentHandoff | undefined {
    const route = `${params.fromAgentId}->${params.toAgentId}`;
    if (!this.allowlist.has(route)) {
      return undefined;
    }

    return {
      fromAgentId: params.fromAgentId,
      toAgentId: params.toAgentId,
      taskPayload: { ...params.taskPayload },
      traceId: params.traceId ?? `${route}:${Date.now()}`,
    };
  }
}
