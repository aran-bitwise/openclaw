# OpenClaw Mobile (Milestones 1-8)

This folder contains a standalone Flutter subproject implementing Milestones 1-8 for the OpenClaw
mobile plan.

## Structure

- `lib/domain`: entities and event/queue/schedule/hook types
- `lib/application`: routing, heartbeat/cron/hook generation, status mapping, and processing services
- `lib/infrastructure`: drift persistence and secure storage wrapper
- `lib/presentation`: chat UI, scheduler controls, and queue controls
- `test`: unit and integration-oriented tests

## Notes

- All Flutter implementation code is intentionally isolated under `/openclaw-mobile`.
- Existing repository runtime code outside this folder is used as reference only.
- Milestone 6 adds heartbeat configuration + generation with best-effort scheduling (foreground timer + app resume).
- Milestone 7 adds cron schedules (daily/weekly/custom interval subset) with missed-run policies (`skip` / `catchUp`).
- Milestone 8 adds internal hooks (startup/turnStart/turnEnd/reset/memoryFlush) with ancestry and loop guards.
- `Process now` remains as fallback until native background workers are integrated.
