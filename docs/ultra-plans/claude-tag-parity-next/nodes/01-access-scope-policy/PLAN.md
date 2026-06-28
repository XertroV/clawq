# PLAN: Access and Scope Policy

## P14.M1 Scope Bundle Model and Resolver

### P14.M1.E1 Access Bundle Data Model

- T001 Add access bundle config and storage types.
  Acceptance: bundles can represent tools, MCP/skills, repos, domains,
  credential handles, instructions, memory grants, and budget references without
  leaking secrets; config parse/validation tests cover invalid references.
- T002 Implement deterministic scope inheritance resolver.
  Acceptance: default/workspace/channel/room layers merge deterministically with
  explicit conflict errors and tested precedence.
- T003 Persist effective-access snapshots for executable work.
  Acceptance: sessions, background tasks, routines, and ambient work can record
  immutable snapshot IDs and continue with their original snapshot after config
  changes.

### P14.M1.E2 Layered Instructions and Prompt Context

- T001 Add scoped instruction records with provenance and edit policy.
  Acceptance: instructions carry source scope, author/admin metadata, enabled
  state, and lock/edit permissions.
- T002 Resolve layered instructions into prompt context.
  Acceptance: prompt construction receives ordered instruction layers with
  provenance labels and no duplicate profile/system prompt drift.
- T003 Add snapshot and config-reload tests for instructions.
  Acceptance: running work keeps its snapshot; new work sees changed config; bad
  config reload leaves previous valid state in memory.

## P14.M2 Access Explanation and Enforcement Integration

### P14.M2.E1 Explain-Access Surface

- T001 Build redacted effective-access explanation API.
  Acceptance: API lists inherited scopes, grants, denied capabilities, active
  instructions, budget, memory, repos, and credential handles without secret
  values.
- T002 Add CLI/channel commands for access explanation.
  Acceptance: admins can run `rooms explain-access`; room members can ask what
  Clawq can access here with appropriately redacted output.
- T003 Add denial and redaction regression tests.
  Acceptance: denied tools/repos/credentials are explained without exposing
  private values or unrelated scopes.

### P14.M2.E2 Enforcement Migration and Compatibility

- T001 Route room execution through effective-access snapshots.
  Acceptance: agent loops, room background tasks, routines, ambient work, and
  memory/search use the resolved snapshot rather than ad hoc profile fields.
- T002 Bridge existing room profile fields to bundle-backed resolution.
  Acceptance: current P11-P13 configs behave the same after resolver migration,
  with warnings only for ambiguous legacy settings.
- T003 Add minimal-build and reload compatibility tests.
  Acceptance: minimal build surfaces disabled messages, and daemon runtime state
  refreshes derived policy after config set/watch/SIGHUP.
