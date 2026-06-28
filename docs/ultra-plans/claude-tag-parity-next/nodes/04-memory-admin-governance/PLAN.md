# PLAN: Memory and Admin Governance

## P17.M1 Room Memory Management

### P17.M1.E1 In-Room Scoped Memory CRUD

- T001 Add room memory save/list/show commands.
  Acceptance: users/admins can save and inspect room-scoped memories through
  CLI/channel commands with grant checks and source metadata.
- T002 Add room memory correct/forget commands.
  Acceptance: corrections preserve provenance/history; forget removes or tomb-
  stones the scoped memory according to retention policy.
- T003 Add agent tool support for scoped room memory.
  Acceptance: agent tools can propose/save/correct room memory only under the
  active effective-access snapshot and never silently write global memory.

### P17.M1.E2 Memory Provenance and Isolation Semantics

- T001 Add public/private room memory policy semantics.
  Acceptance: public workspace sharing and private room isolation are explicit,
  configurable, and tested for cross-room leakage.
- T002 Add memory provenance and audit export.
  Acceptance: each memory records room/thread/user/source/task/snapshot and can
  be exported through ledger/admin tooling.
- T003 Add negative tests for scoped memory isolation.
  Acceptance: ungranted rooms, private channels, stale snapshots, and global
  fallback attempts are denied.

## P17.M2 Admin Setup Wizard

### P17.M2.E1 Pilot Room Wizard Core

- T001 Add wizard plan/apply flow for pilot rooms.
  Acceptance: wizard can create/validate room profile, access bundle, memory
  scope, budget, connector binding, and readiness checks without side effects in
  plan mode.
- T002 Add Teams-first wizard path with Slack baseline.
  Acceptance: wizard validates a Teams room as the primary path and supports a
  Slack comparison path when configured.
- T003 Add rerun/repair behavior.
  Acceptance: partial setup can be rerun idempotently and reports what changed,
  what was already valid, and what remains blocked.

### P17.M2.E2 GitHub/Budget/Audit Validation

- T001 Validate GitHub App/repo grants in wizard.
  Acceptance: wizard checks installation, repo grants, webhook reachability,
  and room backlink readiness.
- T002 Validate budget and spend warnings.
  Acceptance: wizard reports room budget state, hard/soft limits, and denial
  message behavior.
- T003 Validate audit and delivery observability.
  Acceptance: wizard can run or simulate a connector delivery and show ledger/
  delivery/audit traces.

## P17.M3 Governance and Readiness

### P17.M3.E1 Guest, External, and Invocation Policy

- T001 Add guest/external room policy model.
  Acceptance: connectors that expose guest/shared/external metadata can refuse,
  warn, or require admin override before work starts.
- T002 Enforce invocation restrictions by scope.
  Acceptance: role/member/admin rules are checked before room work, routines,
  memory mutation, and GitHub triggers.
- T003 Add policy explanation tests.
  Acceptance: denials explain the relevant room policy without leaking unrelated
  users/scopes.

### P17.M3.E2 Readiness Report and Audit Export

- T001 Add room-agent readiness report command.
  Acceptance: command reports connector, scope, memory, GitHub, budget, audit,
  routine, ambient, and proxy-readiness status.
- T002 Add room audit export polish.
  Acceptance: exports include scope snapshot, memory, GitHub, delivery, and
  policy events with redacted references.
- T003 Document admin rollout workflow.
  Acceptance: docs cover pilot setup, Teams-first rollout, Slack baseline,
  governance limits, troubleshooting, and known deferred items.
