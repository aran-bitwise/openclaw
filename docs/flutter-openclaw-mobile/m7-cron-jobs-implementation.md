# Flutter OpenClaw Mobile Milestone 7 Cron jobs

## Scope

Milestone 7 adds **Input type 3: cron jobs** while reusing the existing runtime pipeline:
CronService -> RuntimeService/GatewayRouter -> durable queue -> processing -> timeline.

## Data model and persistence

- Added `CronSchedule` and `CronScheduleRule` domain entities.
- Supported v1 schedule subset:
  - `daily` (time-of-day minute)
  - `weekly` (weekday + time-of-day minute)
  - `custom` (`everyNMinutes` interval subset)
- Persisted fields:
  - `scheduleId`, `agentId`, `channelId`, `sessionId`
  - `enabled`, `rule`, `timezoneId`
  - `missedRunPolicy` (`skip` or `catchUp`)
  - `promptTemplate`, `lastRunAt`, `nextRunAt`
- Timezone decision in v1: **local device timezone only** (`timezoneId=local-device`).
- Drift schema migration note: `cron_schedules` table is created in app init and survives restarts.

## Scheduler behavior

- `CronService` evaluates due schedules with injected `Clock`.
- Cron events are generated as `EventType.cron` and sent through `RuntimeService.sendCron(...)`.
- Idempotency key strategy: `cron-<scheduleId>-<bucketMinute>`.
- Schedule state (`lastRunAt`/`nextRunAt`) is persisted after each due emission.
- Queue processing is auto-kicked when cron events are generated.

### Missed-run policy

- `skip`: emit only one due run when app resumes; do not backfill all missed windows.
- `catchUp`: backfills missed runs with cap.
- Current cap: **3** by default in service (tests validate capped catch-up behavior).

## Mermaid diagrams

### A) Due evaluation to UI

```mermaid
sequenceDiagram
  participant Tick as Timer/Resume/manual check
  participant Cron as CronService
  participant RT as RuntimeService
  participant DB as Drift
  participant QP as QueueProcessor
  participant UI as Timeline

  Tick->>Cron: triggerDueSchedules()
  Cron->>DB: load schedules + evaluate due windows
  Cron->>RT: sendCron(...) for due runs
  RT->>DB: insert cron Event + enqueue
  Cron->>DB: update lastRunAt/nextRunAt
  Cron->>QP: tick()
  QP->>DB: processing lifecycle + run_result
  DB-->>UI: timeline refresh with cron label and status chips
```

### B) Missed-run SKIP flow

```mermaid
flowchart TD
  A[App resumes after downtime] --> B[CronService sees schedule overdue]
  B --> C{Policy == skip?}
  C -->|Yes| D[Emit one due event]
  D --> E[Advance nextRunAt to future]
  E --> F[No historical backfill]
```

### C) Missed-run CATCH_UP flow

```mermaid
flowchart TD
  A[App resumes after downtime] --> B[CronService sees schedule overdue]
  B --> C{Policy == catchUp?}
  C -->|Yes| D[Emit due events in order]
  D --> E{Reached now or cap N?}
  E -->|No| D
  E -->|Yes| F[Persist lastRunAt/nextRunAt and stop]
```

### D) UX schedule flow

```mermaid
flowchart LR
  A[Select agent and session] --> B[Create schedule]
  B --> C[Choose type daily/weekly/custom]
  C --> D[Set prompt and missed-run policy]
  D --> E[Enable schedule]
  E --> F[Observe cron events in timeline]
  F --> G[Run now / disable / delete]
```

## Implemented vs designed

Implemented:

- Daily, weekly, and deterministic custom interval schedules.
- Persisted schedule state with robust restart behavior.
- Missed-run skip and capped catch-up behavior.
- Cron timeline labeling and queue lifecycle chips.

Deviations:

- Full cron expression parser is deferred; v1 custom subset is `everyNMinutes` only.
- Timezone is local-device only for this phase to avoid dependency and parsing complexity.

## Manual Android validation plan

1. Create/select agent and session.
2. Add three schedules (daily, weekly, custom).
3. Trigger scheduler check (manual action) and verify due events appear as cron entries.
4. Disable and re-enable schedules; confirm behavior changes accordingly.
5. Simulate missed windows by pausing app and resuming later (or debug clock in tests).
6. Verify `skip` emits one due event; verify `catchUp` emits up to cap.
7. Kill app and relaunch; confirm schedules and next run state persist.
8. Verify queued -> processing -> completed/failed chips for cron events in timeline.
