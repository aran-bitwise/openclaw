# OpenClaw Mobile (Milestones 1-4)

This folder contains a standalone Flutter subproject implementing Milestones 1-4 for the OpenClaw
mobile plan.

## Structure

- `lib/domain`: entities and event/queue types
- `lib/application`: routing and processing services
- `lib/infrastructure`: drift persistence and secure storage wrapper
- `lib/presentation`: app UI and queue inspector
- `test`: unit and integration-oriented tests

## Notes

- All Flutter implementation code is intentionally isolated under `/openclaw-mobile`.
- Existing repository runtime code outside this folder is used as reference only.
