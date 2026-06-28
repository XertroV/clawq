# Research Log

## 2026-06-28 - Bundle and Code Inventory

Source: `docs/plans/2026-06-28-claude-tag-parity-bundle-inventory.md`

Findings:

- Existing Clawq code exceeds the bundle's public-baseline assumptions in room
  profiles, shared Slack sessions, room workspaces, scoped memory/grants,
  budgets, activity ledger, routines, ambient follow-up, connector capability
  gates, and Slack progress delivery.
- The main missing/shared-agent gaps are enterprise semantics: composable access
  bundles, inherited scope resolution, effective-access snapshots, GitHub App
  identity/repo grants, room-owned PR subscriptions, polished Teams/Slack UX,
  memory management UX, admin setup wizard, and staged credential/egress policy.
- Runtime usage under `~/.clawq/` did not show active room profile/budget/scoped
  memory setup, so P14-P18 should include wizard/readiness checks and not assume
  production configuration exists.

## 2026-06-28 - Planning Fan-Out

Status: completed.

Summaries folded into the ultra-plan and `.backlog`:

- Access/scope lane recommended a narrow P14 over FT-08, FT-09, FT-31, and
  FT-33: minimal access bundles, inheritance resolver, effective snapshots,
  explain-access, and layered instructions.
- Teams connector lane emphasized a connector-general delivery contract,
  Teams-first progress cards/checklists, session records, context capture, and
  delivery observability because transport success is not proof of visibility.
- GitHub lane recommended App identity, repo grants, PR subscriptions,
  CI/review reporting, triggered review/security runs, and bidirectional
  backlinks, while preserving PAT compatibility.
- Memory/admin lane recommended room memory CRUD/provenance, grant management,
  public/private semantics, pilot wizard, and readiness checks.
- Proxy/verification lane recommended staged credential handles, explicit
  egress wrappers for first-party HTTP/MCP/browser surfaces, room-scoped MCP
  enforcement, and proof follow-up placeholders rather than full proxy/proof
  implementation.

## 2026-06-28 - Backlog Ingestion

Created `.backlog` phases:

- P14: Room Agent Access and Scope Policy, 19 tasks.
- P15: Teams-First Room-Agent UX, 21 tasks.
- P16: GitHub App and Room Code Workflows, 24 tasks.
- P17: Room Memory and Admin Governance, 19 tasks.
- P18: Credential Egress and Verification Boundary, 21 tasks.

Validation:

- `bl check --strict` passed.
- `bl list -a` showed P14.M1.E1.T001 as the first available task.
