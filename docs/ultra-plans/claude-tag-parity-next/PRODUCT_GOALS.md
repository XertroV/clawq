# Product Goals

## Project

Claude Tag parity next phases for Clawq room agents.

## Goal

Extend the completed P11-P13 room-agent substrate into enterprise-grade shared
agent behavior: explicit access scopes, Teams-first room UX, GitHub App/bot
workflows, room memory/admin surfaces, and a staged credential/egress policy
boundary.

## Success Criteria

- Room access is explainable, inherited, snapshotted for running work, and
  enforced consistently across tools, memory, codebase grants, connectors, and
  routines.
- Teams becomes the primary work connector for room-agent UX while Slack remains
  the Claude Tag comparison baseline.
- GitHub App/bot identity supports repo grants, PR subscriptions, CI/review
  reporting, triggered review/security runs, and room-thread backlinks.
- Room-scoped memory can be saved, listed, corrected, forgotten, audited, and
  governed through room/admin workflows.
- Admins can configure a pilot room with a guided wizard that validates
  connector, policy, GitHub, budget, audit, and memory behavior.
- Credential and egress safety are designed with early enforcement hooks without
  allowing proxy work to consume the whole phase family.

## Non-Goals

- Do not reimplement P11-P13 foundations already delivered.
- Do not build Anthropic launch-credit or usage-balance business-model features.
- Do not implement formal Coq proofs in this phase family; record proof/spec
  follow-ups for selected invariants.
- Do not make Slack-only abstractions where connector capability fallbacks can
  generalize the behavior.
