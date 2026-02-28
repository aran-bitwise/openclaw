import { describe, expect, it } from "vitest";
import { CronSchedulerReference } from "./cron-scheduler-reference.js";

describe("cron scheduler reference", () => {
  it("builds deterministic cron run idempotency keys", () => {
    const scheduler = new CronSchedulerReference();
    scheduler.upsertSchedule({
      scheduleId: "daily-1",
      agentId: "main",
      ruleType: "daily",
      timezone: "UTC",
      promptTemplate: "summarize",
      enabled: true,
    });

    expect(scheduler.buildRun("daily-1", 1_700_000_000)?.idempotencyKey).toBe("daily-1:1700000000");
  });
});
