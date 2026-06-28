# Claude Tag Parity Next Ultra Plan

Status: bootstrapped from the Claude Tag parity bundle inventory and ingested
into `.backlog`.

Seed inventory: `docs/plans/2026-06-28-claude-tag-parity-bundle-inventory.md`

Prior foundation: `docs/ultra-plans/room-agent-profiles/` and backlog phases
P11, P12, P13.

## Tree

| Node | Responsibility | Backlog Target |
|---|---|---|
| 01-access-scope-policy | Access bundles, inherited scopes, effective snapshots, layered instructions, explain-access | P14, 19 tasks |
| 02-teams-connector-ux | Teams-first room-agent UX, Slack baseline parity, progress/session artifacts, connector render fallbacks | P15, 21 tasks |
| 03-github-app-workflows | GitHub App identity, repo grants, PR/CI/review subscriptions, triggered runs, backlinks | P16, 24 tasks |
| 04-memory-admin-governance | Room memory CRUD/provenance, setup wizard, guest/governance/audit surfaces | P17, 19 tasks |
| 05-proxy-verification-boundary | Staged credential proxy, egress policy boundary, MCP wrapping, verification follow-up list | P18, 21 tasks |

## Delivery Order

1. P14 establishes the scope resolver and effective-access snapshot used by all
   later phases.
2. P15 and P17 can proceed mostly in parallel after the P14 scope model lands.
3. P16 depends on P14 grants and should coordinate with P15/P17 for room-thread
   output and wizard validation.
4. P18 starts with design/inventory tasks early, then enforces wrappers after
   P14/P16 policy contracts stabilize.

## Review Dashboard

| Date | Review | Result |
|---|---|---|
| 2026-06-28 | Initial bundle/code inventory | Complete, see seed inventory |
| 2026-06-28 | Ultra-plan bootstrap | Complete |
| 2026-06-28 | Planning fan-out | Complete, folded into nodes/backlog |
| 2026-06-28 | `.backlog` ingestion | PASS, P14-P18 created with 104 tasks |
| 2026-06-28 | `bl check --strict` | PASS |
| 2026-06-28 | Workflow implementation launch | Starting with P14.M1.E1 wave |
