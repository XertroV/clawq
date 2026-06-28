# INTERFACE: Teams-First Connector Room UX

## Provides

- Room session record/query API for visible work state.
- Progress checklist/event model usable by connector renderers.
- Teams card renderer and Slack edited-message renderer for room progress.
- Delivery observability events for attempted/accepted/failed connector sends.

## Consumes

- P14 effective-access snapshots and explanations.
- P11-P13 room sessions, task delivery, routines, ambient watcher, and connector
  capability matrix.

## Consumers

- P16 GitHub subscriptions and triggered runs render updates/backlinks through
  these room UX primitives.
- P17 wizard validates connector UX and delivery.

## Constraints

- Thread-less connectors must have deterministic fallback behavior.
- Connector failures must be observable without relying on model self-report.
