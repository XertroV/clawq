# SPEC: Access and Scope Policy

## Responsibility

Define the enterprise shared-agent policy core that turns room profiles into
composable access scopes. This includes access bundles, inheritance across
default/workspace/channel/room levels, effective-access snapshots for running
work, layered instructions, and human-readable access explanations.

## In Scope

- Bundle-like data model for credentials, repos, tools, skills/MCP, domains, and
  instructions.
- Deterministic resolver for inherited scopes and conflict rules.
- Effective-access snapshots bound to sessions, routines, background tasks, and
  GitHub-triggered work.
- Layered instructions with provenance and precedence.
- `rooms explain-access` style CLI/channel surface with redacted output.
- Tests for denial, inheritance, snapshot immutability, and config reload.

## Out of Scope

- Full credential proxy enforcement; P18 owns that boundary.
- Formal Coq proofs; P18 records follow-up proof/spec tasks.
- UI dashboard beyond CLI/channel text surfaces.

## Backlog Target

P14: Room Agent Access and Scope Policy.
