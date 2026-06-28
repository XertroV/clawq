# INTERFACE: Access and Scope Policy

## Provides

- `access_bundle` configuration/storage types.
- Scope resolver from org/default, workspace, channel/room, and local bindings.
- Effective-access snapshot records for session/task/routine execution.
- Redacted access explanation API for CLI and connectors.
- Layered instruction resolution API for prompt construction.

## Consumes

- P11 room profiles, bindings, room sessions, and room workspaces.
- P12 tool/codebase grants, scoped memory grants, budgets, and ledger.
- P13 routines and ambient watcher profile execution.

## Consumers

- P15 connector UX uses explanations and session snapshots.
- P16 GitHub App workflows use repo grants and snapshots.
- P17 wizard/governance configures bundles and audits access.
- P18 credential/egress policy wraps credentials and network rules in bundles.

## Constraints

- Existing unprofiled sessions must remain compatible.
- Minimal build must return actionable disabled messages for integration-only
  surfaces.
- Effective snapshots must not silently change while a background task is
  running.
