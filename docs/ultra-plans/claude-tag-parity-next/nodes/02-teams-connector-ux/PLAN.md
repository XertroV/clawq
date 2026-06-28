# PLAN: Teams-First Connector Room UX

## P15.M1 Shared Room UX Primitives

### P15.M1.E1 Session Records and Progress Events

- T001 Add durable room session record model.
  Acceptance: room/thread/background/routine work has queryable status,
  participants, origin, snapshot, artifacts, and connector thread references.
- T002 Add progress checklist event model.
  Acceptance: planned/current/blocked/completed/final states are appendable,
  resumable, and renderable without re-running model text.
- T003 Link artifacts and backlinks from room work.
  Acceptance: generated files, PRs, logs, workflow runs, and task records have
  stable references visible in final connector messages.

### P15.M1.E2 Connector Rendering and Fallbacks

- T001 Extend connector capabilities for room UX rendering.
  Acceptance: matrix covers editable message, card/buttons, file/link, markdown,
  thread reply, delivery ack, and fallback strategy.
- T002 Implement Slack progress checklist renderer.
  Acceptance: Slack room work edits one visible progress message when possible
  and falls back to threaded updates safely.
- T003 Implement Teams progress card renderer.
  Acceptance: Teams room work posts/updates an Adaptive Card or supported
  fallback with status, action controls, and artifact links.

## P15.M2 Teams Production Room UX

### P15.M2.E1 Teams Context, Threads, and Delivery Proof

- T001 Harden Teams room/session thread mapping.
  Acceptance: Teams conversation/activity/reply IDs map to stable room/thread
  sessions and do not fork on replay.
- T002 Add bounded Teams room context capture.
  Acceptance: configured Teams rooms can capture allowed context for room-agent
  prompts with retention, privacy, and connector-history policy enforced.
- T003 Record Teams delivery observability.
  Acceptance: outbound Teams sends distinguish scheduled, generated, attempted,
  accepted, failed, and visible-enough states with correlatable IDs.

### P15.M2.E2 Teams Interactive Controls and Generalization

- T001 Add Teams inspect/continue/cancel controls for room work.
  Acceptance: card actions route through room policy and produce clear user
  feedback for allowed, denied, stale, and unsupported states.
- T002 Generalize connector command/control fallbacks.
  Acceptance: connectors without cards/buttons get deterministic text commands
  and links; tests cover unsupported capability paths.
- T003 Add Slack/Teams room UX smoke tests and docs.
  Acceptance: smoke tests cover one Slack baseline and one Teams production path;
  docs describe fallbacks and operational limits.
