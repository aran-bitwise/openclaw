# OpenClaw Mobile (Milestones 1-7)

This folder contains a standalone Flutter subproject implementing Milestones 1-7 for the OpenClaw
mobile plan.

## Structure

- `lib/domain`: entities and event/queue/schedule types
- `lib/application`: routing, heartbeat/cron generation, status mapping, and processing services
- `lib/infrastructure`: drift persistence and secure storage wrapper
- `lib/presentation`: chat UI, heartbeat + cron configuration UI, and queue controls
- `test`: unit and integration-oriented tests

## Notes

- All Flutter implementation code is intentionally isolated under `/openclaw-mobile`.
- Existing repository runtime code outside this folder is used as reference only.
- Milestone 6 adds heartbeat configuration + generation with best-effort scheduling (foreground timer + app resume).
- Milestone 7 adds cron schedules (daily/weekly/custom interval subset) with missed-run policies (`skip` / `catchUp`).
- `Process now` remains as fallback until native background workers are integrated.
