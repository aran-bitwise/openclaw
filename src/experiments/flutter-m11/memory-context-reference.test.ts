import { describe, expect, it } from "vitest";
import { MemoryContextReference } from "./memory-context-reference.js";

describe("memory context reference", () => {
  it("compacts oldest scoped entries", () => {
    const memory = new MemoryContextReference();
    memory.add({
      id: "1",
      scope: "agent",
      scopeId: "main",
      content: "a",
      createdAt: 1,
    });
    memory.add({
      id: "2",
      scope: "agent",
      scopeId: "main",
      content: "b",
      createdAt: 2,
    });
    memory.add({
      id: "3",
      scope: "agent",
      scopeId: "main",
      content: "c",
      createdAt: 3,
    });

    expect(memory.compact("agent", "main", 2)).toBe(1);
    expect(memory.list("agent", "main").map((entry) => entry.id)).toEqual(["2", "3"]);
  });
});
