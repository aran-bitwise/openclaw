import { describe, expect, it } from "vitest";
import { InternalHooksReference } from "./internal-hooks-reference.js";

describe("internal hooks reference", () => {
  it("emits normalized hook events", () => {
    const hooks = new InternalHooksReference();
    const event = hooks.emit({
      hookType: "app.startup",
      sessionId: "s-main",
      createdAt: 42,
    });

    expect(event.idempotencyKey).toBe("app.startup:s-main:42");
  });
});
