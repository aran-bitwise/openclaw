export type CronRuleType = "daily" | "weekly" | "custom";

export type CronSchedule = {
  scheduleId: string;
  agentId: string;
  ruleType: CronRuleType;
  timezone: string;
  promptTemplate: string;
  enabled: boolean;
};

export type CronRun = {
  scheduleId: string;
  agentId: string;
  eventType: "cron";
  idempotencyKey: string;
  scheduledAt: number;
};

export class CronSchedulerReference {
  private readonly schedules = new Map<string, CronSchedule>();

  upsertSchedule(schedule: CronSchedule): void {
    this.schedules.set(schedule.scheduleId, { ...schedule });
  }

  listSchedules(): CronSchedule[] {
    return [...this.schedules.values()].map((item) => ({ ...item }));
  }

  buildRun(scheduleId: string, scheduledAt: number): CronRun | undefined {
    const schedule = this.schedules.get(scheduleId);
    if (!schedule || !schedule.enabled) {
      return undefined;
    }

    return {
      scheduleId,
      agentId: schedule.agentId,
      eventType: "cron",
      idempotencyKey: `${scheduleId}:${scheduledAt}`,
      scheduledAt,
    };
  }
}
