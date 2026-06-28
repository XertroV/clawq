# INTERFACE: Memory and Admin Governance

## Provides

- Room memory command/tool surface.
- Memory provenance/correction/audit records.
- Wizard/readiness checks for pilot rooms.
- Governance policy checks for guests/external/shared rooms where connector
  metadata supports it.

## Consumes

- P14 scopes, memory grants, and effective-access explanations.
- P15 connector UX/renderers.
- P16 GitHub App/repo grant checks.
- P12 scoped memory and ledger internals.

## Consumers

- Operators use wizard/readiness reports before production rollout.
- P18 verification follow-up consumes policy/memory invariants.

## Constraints

- Room memory commands must never fall back to global memory in profiled rooms
  unless explicitly granted.
- Wizard must be rerunnable and safe against partial setup.
