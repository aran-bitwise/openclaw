# OpenClaw Mobile (Milestones 1-5)

This folder contains a standalone Flutter subproject implementing Milestones 1-5 for the OpenClaw
mobile plan.

## Structure

- `lib/domain`: entities and event/queue types
- `lib/application`: routing, status mapping, and processing services
- `lib/infrastructure`: drift persistence and secure storage wrapper
- `lib/presentation`: chat UI and queue inspector controls
- `test`: unit and integration-oriented tests

## Notes

- All Flutter implementation code is intentionally isolated under `/openclaw-mobile`.
- Existing repository runtime code outside this folder is used as reference only.
- Milestone 5 keeps a temporary `Process now` action due to missing background loop scheduling in this
  phase.
