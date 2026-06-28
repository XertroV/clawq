# SPEC: Proxy and Verification Boundary

## Responsibility

Design and stage the safety boundary for credentials, egress, room-scoped MCP,
and verification follow-ups. This phase should create enforceable hooks and
audit mode first, without becoming a full network proxy project prematurely.

## In Scope

- Credential handle/provider abstraction and callsite inventory.
- Early wrappers for GitHub/MCP/tool credentials that avoid model/prompt leaks.
- Default-deny egress policy model and outbound callsite mapping.
- Audit/warn enforcement mode and test harness for representative paths.
- Verification follow-up list for future formal proofs/specs.

## Out of Scope

- Full transparent network proxy for every process.
- Coq proof implementation.
- General secret manager integration beyond handle abstraction.

## Backlog Target

P18: Credential, Egress, and Verification Boundary.
