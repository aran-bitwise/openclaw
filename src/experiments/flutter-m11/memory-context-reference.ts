export type MemoryScope = "global" | "agent" | "session";

export type MemoryEntry = {
  id: string;
  scope: MemoryScope;
  scopeId: string;
  content: string;
  createdAt: number;
};

export class MemoryContextReference {
  private readonly entries: MemoryEntry[] = [];

  add(entry: MemoryEntry): void {
    this.entries.push({ ...entry });
  }

  list(scope: MemoryScope, scopeId: string): MemoryEntry[] {
    return this.entries
      .filter((item) => item.scope === scope && item.scopeId === scopeId)
      .map((item) => ({ ...item }));
  }

  compact(scope: MemoryScope, scopeId: string, maxEntries: number): number {
    const scoped = this.entries.filter((item) => item.scope === scope && item.scopeId === scopeId);
    if (scoped.length <= maxEntries) {
      return 0;
    }

    const sorted = scoped.toSorted((a, b) => a.createdAt - b.createdAt);
    const removeSet = new Set(sorted.slice(0, sorted.length - maxEntries).map((item) => item.id));
    const before = this.entries.length;
    const kept = this.entries.filter((item) => !removeSet.has(item.id));
    this.entries.length = 0;
    this.entries.push(...kept);
    return before - kept.length;
  }
}
