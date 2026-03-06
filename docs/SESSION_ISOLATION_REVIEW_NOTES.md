# Session Isolation Review Notes (P5.M2.E1.T001)

Reviewed `src/session.ml` for same-key and cross-key hazards around creation,
locking, reset, and persistence.

## Confirmed properties

- Same-key turns are serialized by per-session `Lwt_mutex`.
- Session creation and table updates are guarded by `sessions_lock`.
- `reset` waits for in-flight same-key work by acquiring the same per-session lock.
- `reset` clears both in-memory table entry and persisted session history.

## Assumptions made explicit

- Persistence (`Memory.store_message`) is treated as sequential/atomic per call.
- The runtime relies on cooperative Lwt scheduling (no preemptive races inside a held lock).
- Key isolation concerns map to key-local effects, not unequal message contents.

## Open race / contention questions

- `with_session_lock` currently holds `sessions_lock` while waiting for the per-key mutex.
  This avoids key-removal races, but can create cross-key contention (one busy key can delay
  unrelated keys that need `sessions_lock` briefly).
- `reset` also acquires `sessions_lock` before waiting on the per-key mutex, preserving ordering
  and avoiding deadlock with `with_session_lock`, but contributing to the same contention pattern.

## Follow-up candidates

- Introduce a two-phase lookup pattern (obtain key entry under `sessions_lock`, then release
  global lock before waiting on per-key mutex), with versioning/removal checks.
- Add contention-focused stress tests for independent keys under concurrent turns + resets.
