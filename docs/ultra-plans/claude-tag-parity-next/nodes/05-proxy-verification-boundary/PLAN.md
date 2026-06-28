# PLAN: Proxy and Verification Boundary

## P18.M1 Credential Policy Boundary

### P18.M1.E1 Credential Handle Abstraction

- T001 Inventory credential-bearing callsites.
  Acceptance: GitHub, MCP, provider, connector, tool, shell/git, and HTTP
  credential paths are listed with owner module and current redaction behavior.
- T002 Add credential handle/provider types.
  Acceptance: access bundles can reference credential handles without exposing
  values to prompts, snapshots, logs, or worker sandboxes.
- T003 Add prompt/log redaction regression tests.
  Acceptance: representative credential-backed operations prove secrets do not
  appear in prompts, ledger exports, errors, or debug logs.

### P18.M1.E2 Scoped Wrappers for GitHub, MCP, and Tools

- T001 Wrap GitHub App/PAT auth through credential policy.
  Acceptance: GitHub calls obtain credentials through snapshot-scoped handles
  and deny missing/unauthorized handles before API calls.
- T002 Wrap room-scoped MCP connectors.
  Acceptance: MCP tools can be enabled/disabled through bundle policy and are
  audited as part of room sessions.
- T003 Wrap credential-sensitive built-in tools.
  Acceptance: representative shell/git/http tools check snapshot policy before
  receiving credential handles.

## P18.M2 Egress Policy Boundary

### P18.M2.E1 Egress Policy Model and Inventory

- T001 Add host/path/method egress rule model.
  Acceptance: policy supports allow/deny/audit actions, readonly/write labels,
  and scope attachment without changing runtime behavior yet.
- T002 Inventory outbound network callsites.
  Acceptance: HTTP client, GitHub, MCP, provider, connectors, shell/git, and
  runner paths are classified by enforceability and risk.
- T003 Add egress explanation output.
  Acceptance: `explain-access` can show allowed/denied/audit egress rules with
  redacted credential references.

### P18.M2.E2 Audit/Warn Enforcement Hooks

- T001 Enforce audit mode in common HTTP/GitHub paths.
  Acceptance: representative outbound calls emit allowed/denied/audit decisions
  tied to snapshot and ledger records.
- T002 Add deny mode for explicitly wrapped safe paths.
  Acceptance: at least GitHub API and MCP tool calls can be denied by egress
  policy before outbound traffic.
- T003 Add tests for egress decisions and redaction.
  Acceptance: host/path/method matches, deny precedence, audit mode, and secret
  redaction are covered.

## P18.M3 Verification Follow-Up

### P18.M3.E1 Spec Invariants and Runtime Tests

- T001 Write scope-resolution invariant spec.
  Acceptance: spec lists resolver determinism, precedence, conflict, snapshot,
  and reload invariants with links to runtime tests.
- T002 Write memory/policy isolation invariant spec.
  Acceptance: spec lists memory isolation, repo grant, credential, egress,
  budget, and session lifecycle invariants for future proof work.
- T003 Add runtime conformance tests for proof candidates.
  Acceptance: selected invariants have executable tests before any future proof
  task is opened.

### P18.M3.E2 Formal Verification Backlog Hooks

- T001 Add proof follow-up tasks or notes for selected invariants.
  Acceptance: future proof work is linked from docs/backlog without claiming
  proofs exist.
- T002 Update verification documentation boundaries.
  Acceptance: docs clearly distinguish implemented runtime checks, tests, and
  future formal proof candidates.
- T003 Add drift check for policy docs versus implementation.
  Acceptance: docs/check command or test catches stale claims about policy/
  proxy/proof status.
