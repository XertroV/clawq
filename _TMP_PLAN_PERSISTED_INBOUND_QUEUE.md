# Persisted Inbound Queue Plan

## Objective

Add a durable inbound queue for offline `session inject` so messages can be captured while no daemon is running, then processed later through the real session runtime after daemon startup.

This plan is intentionally scoped to a maintainable first cut that preserves current live behavior and improves debuggability.

## Final Planning Decisions

- Phase 1 scope: offline `session inject` persistence plus daemon-startup draining only.
- Storage model: dedicated queue table with stable metadata columns plus `payload_json`.
- Delivery semantics: at-least-once.
- Reset semantics: `session reset` clears pending inbound queue rows for that session.
- Visibility: structured logs plus CLI visibility.
- Follow-up: add a backlog bug/task for formal verification of the key queue invariants and behaviors.

## Why This Scope

The current system has two different concepts that must not be conflated:

- persisted agent-resume state (`session_state.turn = agent`, `response_sent_at IS NULL`)
- live in-memory queued inbound messages (`Session.queued_messages`)

Live queueing today depends on runtime-only conditions:

- the session is currently busy
- the session key is queueable
- a live notifier/runtime path is present

Because of that, phase 1 should not attempt to replace or unify the live in-memory queue. Doing so now would create a much riskier change surface and make correctness harder to reason about.

Instead, phase 1 adds a durable queue only for the offline case, then replays that queue on daemon startup.

## Non-Goals For Phase 1

- Do not replace the live in-memory queue for busy sessions.
- Do not try to drain durable inbound items continuously while the daemon is already running.
- Do not make all channels durable immediately.
- Do not attempt exactly-once delivery.

These can be revisited later if phase 1 proves stable and easy to operate.

## Required Semantic Model

Persisted inbound queue rows are **durable inbound events awaiting processing**, not already-processed chat history.

That means:

- enqueueing must **not** append directly to `messages`
- queue rows are separate from chat history and compaction epochs
- the message enters chat history only when it is actually processed by the normal session runtime path

This is critical for keeping:

- chat logs faithful
- compaction behavior correct
- replay/debugging understandable
- duplicate history less likely

## Target Runtime Behavior

### When daemon is running

- `session inject` keeps using the current live path.
- Idle session: process immediately.
- Busy queueable live session: use existing in-memory queue semantics.
- Busy bang message: use existing bang/interrupt behavior.

Phase 1 does not change this behavior.

### When daemon is not running

- `session inject` creates a durable inbound queue row.
- It should warn that live queue/bang semantics were unavailable at enqueue time.
- It should report that the message has been queued for replay on next daemon start.

### On daemon startup

- reclaim stale claims, if any
- resume pending agent turns using existing logic
- then drain durable inbound queue rows through the real session runtime
- process rows in FIFO order per session
- delete successful rows
- release failed rows with retry metadata

## Delivery Guarantee

Phase 1 explicitly targets **at-least-once** processing.

Reason:

- exactly-once would require significantly more coordination around side effects, persistence, and response delivery
- the current architecture already makes a simpler guarantee more realistic than an exactly-once one

Implication:

- if the daemon crashes after processing a queued row but before deleting it, that row may replay later

Because of this, observability is mandatory.

## Storage Design

### New Table

Add a dedicated durable table, e.g. `inbound_queue`.

Recommended columns:

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `session_key TEXT NOT NULL`
- `source TEXT NOT NULL`
- `state TEXT NOT NULL` (`pending`, `claimed`)
- `payload_json TEXT NOT NULL`
- `created_at TEXT NOT NULL DEFAULT (datetime('now'))`
- `claimed_at TEXT`
- `claimed_by TEXT`
- `attempt_count INTEGER NOT NULL DEFAULT 0`
- `last_error TEXT`

Recommended indexes:

- by `state, id`
- by `session_key, state, id`

### Payload Envelope

Store the inbound event body in `payload_json`.

Recommended initial payload shape:

```json
{
  "message": "!interrupt now",
  "is_bang": true,
  "source": "session_inject",
  "enqueued_while_offline": true
}
```

Why envelope JSON is the right choice:

- future-safe for channel metadata and attachments
- avoids repeated schema churn
- preserves room for richer debugging context
- keeps operator metadata columns separate from replay payload

## Memory-Layer API Plan

Add explicit queue APIs to `src/memory.ml`.

Recommended functions:

- `enqueue_inbound_message ~db ~session_key ~source ~payload_json`
- `count_pending_inbound_messages ~db ~session_key`
- `list_pending_inbound_messages ~db ?session_key ()`
- `claim_next_inbound_message ~db ~worker_id ?session_key ()`
- `delete_inbound_message ~db ~id`
- `release_inbound_message ~db ~id ~last_error`
- `reclaim_stale_inbound_claims ~db ~older_than_seconds`
- `clear_inbound_queue ~db ~session_key`

Important API design rule:

- claim/release/delete should be modeled as explicit state transitions with clear result types, not loose SQL helpers only

This area needs to be easy to debug.

## Processing Model

### Daemon-Owned Dispatcher

Add a daemon-owned inbound queue dispatcher rather than spreading replay logic across CLI or HTTP code.

Recommended responsibilities:

- claim one row
- decode payload
- process through the real session path
- delete on success
- release on failure
- log every state transition

Recommended helper shape:

- `drain_persisted_inbound_queue_once`
- `drain_persisted_inbound_queue_for_startup`

Potential worker identity:

- hostname/pid or daemon pid string in `claimed_by`

### Ordering Rule

- preserve FIFO order within a session
- cross-session global ordering is not required

This matches the existing session-local serialization model better than trying to impose a global total order.

## Bang Message Semantics

Preserve raw message text and explicit bang intent.

Do not invent a second normalization path.

Recommended rule:

- persist raw message text
- persist explicit `is_bang`
- on replay, feed the original text back into the same runtime path that live injection uses so existing normalization/interrupt logic stays authoritative

This avoids semantic drift between live and replayed bang messages.

## Relationship To Existing Resume Logic

Current startup resume handles unfinished agent turns. That must stay conceptually separate from durable inbound replay.

Recommended startup ordering:

1. initialize runtime/session manager
2. reclaim stale durable queue claims
3. resume pending agent turns with existing mechanism
4. drain durable inbound queue

Rationale:

- pending agent turns are already in-flight work that should complete first
- new inbound replay should happen after that state is stabilized

This ordering should be called out explicitly in code comments and docs.

## Reset And Cleanup Semantics

`session reset` must clear pending durable inbound rows for that session.

Reason:

- otherwise reset becomes surprising and incomplete
- users would see old deferred inbound work replay after a reset

Also update any relevant low-level cleanup path such as `Memory.clear_session` so reset semantics remain consistent across CLI/runtime behavior.

This cleanup must be logged.

## CLI / Operator Visibility

This feature needs operator tooling from day one.

### Required CLI visibility

- include `pending_inbound` count in `session list`
- add `session pending SESSION`

Recommended `session pending` output:

- queue row id
- created_at
- source
- bang flag
- claim state
- attempt_count
- last_error
- compact preview of message text

### Required logs

Log these transitions with queue id and session key:

- enqueue
- claim
- replay start
- replay success
- release/retry
- stale claim reclaim
- clear on reset

This is not optional if we want maintainable support/debugging.

## Compaction Interaction

This feature should reduce semantic mess as compaction pressure increases.

Key rules:

- durable inbound queue rows are not chat history
- compaction operates on actual processed history only
- pending inbound rows are not compacted into epochs
- if needed, operator tooling can show pending inbound rows separately from chat log epochs

This keeps chat history truthful and prevents offline deferred inputs from being mistaken for already-processed conversation turns.

## Failure Model

### Accepted risk in v1

- at-least-once replay after crash

### Must handle well

- daemon crash after claim but before processing
- daemon crash after processing but before delete
- malformed payload row
- unsupported session/channel semantics at replay time
- repeated replay failure for one row

### Recommended first-cut behavior

- malformed payload: log and park via `last_error`, release or leave claimed only if operator-visible and intentional
- normal transient failure: release with incremented attempt count and `last_error`
- repeated failures: remain pending/retriable, but clearly visible in CLI/logs

If a dead-letter state is added later, it should be introduced deliberately, not improvised.

## Recommended Implementation Phases

### Phase 1: schema and memory APIs

1. bump schema version
2. add `inbound_queue`
3. add queue API helpers in `Memory`
4. add tests for migration, enqueue, claim, release, reclaim, clear

### Phase 2: offline inject behavior

5. change no-daemon `session inject` fallback to enqueue durable inbound rows
6. stop writing offline inject directly to chat history
7. update command output to explain durable replay behavior
8. add CLI tests

### Phase 3: startup replay

9. add daemon startup reclaim of stale claims
10. add startup drain pass after pending agent resume
11. delete rows on success
12. release rows on failure with metadata
13. add restart/replay tests

### Phase 4: operator tooling

14. add pending count to `session list`
15. add `session pending SESSION`
16. add structured logs for all queue transitions
17. update docs

### Phase 5: verification follow-up

18. add a backlog bug/task via `bl bug` for formal verification of the important behaviors and invariants

Recommended verification target areas:

- per-session FIFO replay
- no chat-history insertion before processing
- reset clears pending inbound queue
- startup replay ordering relative to pending agent resume
- at-least-once semantics are documented and consistent

## Test Matrix

### Memory tests

- migration creates queue table
- enqueue stores payload and metadata
- claim is exclusive
- stale claims are reclaimable
- clear removes rows for one session only

### Command bridge tests

- no-daemon `session inject` enqueues durable row
- CLI output explains queued-for-startup behavior
- `session pending` shows expected metadata

### Daemon tests

- startup drains one queued message
- startup drains multiple queued messages in FIFO order per session
- pending agent resume happens before durable inbound replay
- failed replay increments attempts and preserves row
- reset clears pending rows

### Session/behavior tests

- replayed bang message preserves bang semantics
- replayed message becomes chat history only after processing
- unsupported/non-queueable cases behave as documented

### Documentation consistency checks

- CLI docs updated
- HTTP/gateway docs still accurate
- restart/resume docs distinguish agent-resume from durable inbound replay

## Documentation Updates Required

When implementing this plan, update:

- `docs/public/llms-full.txt`
  - `session inject`
  - session inspection commands
  - daemon restart/resume behavior
  - any new operator/debug CLI
- relevant user-facing help in `src/main.ml`
- any comments near startup resume and queue drain ordering

The docs must stay faithful to the implementation. If the implementation changes, the plan and docs should be updated in the same change.

## Opinionated Warnings

These are likely mistakes:

- storing offline injected messages directly in chat history before processing
- trying to unify live and durable queueing in phase 1
- shipping the queue without operator visibility
- pretending exactly-once exists when it does not
- forgetting to clear pending queue rows on reset

Any of those will make the feature harder to trust and much harder to debug.

## Recommended First-Cut Outcome

The first shippable version should do exactly this:

- offline `session inject` writes a durable inbound queue row
- daemon startup replays queued rows after pending agent resume
- replay uses the real runtime path
- queue rows are visible in logs and CLI
- reset clears them
- docs clearly describe at-least-once semantics

That is small enough to implement safely, but complete enough to be genuinely useful.
