# Decisions

## ADR-001: Extend Room Agents Instead of Creating Tag Mode

Status: accepted

Decision: Build on P11-P13 room-agent primitives rather than creating a separate
Claude Tag compatibility subsystem.

Rationale: The existing code already contains room profiles, shared room
sessions, scoped memory/grants, budgets, activity ledgers, routines, ambient
watchers, connector capabilities, and Slack/Teams delivery paths.

## ADR-002: Split the Work Across P14-P18

Status: accepted

Decision: Use multiple backlog phases rather than a single oversized P14.

Rationale: The work has five independent failure domains: access policy,
connector UX, GitHub App workflows, memory/admin governance, and proxy/
verification boundaries. Splitting enables later workflow workers to operate on
disjoint scopes.

## ADR-003: Teams First, Slack Baseline

Status: accepted

Decision: Improve Slack where it is the Claude Tag comparison target, but treat
Teams as the highest-priority production connector and generalize behavior
through connector capabilities.

Rationale: The user uses Teams at work. Clawq already exceeds Claude Tag in raw
connector breadth; the missing piece is uniform room-agent semantics across
connectors.

## ADR-004: Staged Proxy Safety

Status: accepted

Decision: Plan credential and egress safety now, implement early policy
boundaries and audit/warn hooks first, and defer full default-deny outbound
proxy enforcement until the call surface is mapped.

Rationale: Credential/egress safety matters, but should not distract from the
main Teams/GitHub/shared-agent delivery.

## ADR-005: Proofs Tracked, Not Implemented

Status: accepted

Decision: Add verification/proof follow-up tasks for scope resolution, memory
isolation, credential egress, budget enforcement, and session lifecycle
invariants, but do not implement formal proofs in P14-P18.

Rationale: This preserves Clawq's verification story without blocking product
implementation on proof work.
