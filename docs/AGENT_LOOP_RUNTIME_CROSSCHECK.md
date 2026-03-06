# Agent Loop Runtime Cross-Check (P5.M3.E1.T003)

This note links the `coq/theories/Clawq/AgentLoop.v` model to shipped runtime
behavior in `src/agent.ml` and existing tests.

## Model-to-runtime mapping

- `loop_steps_bounded_by_fuel` / `run_turn_global_iteration_bound`
  - Runtime analogue: `max_tool_iterations` limit in `Agent.turn` / `Agent.turn_stream`.
- `append_tool_cycle_extends_history`
  - Runtime analogue: assistant tool-call shell plus ordered tool-result insertion in
    `execute_tool_calls` and `execute_tool_calls_stream`.
- `trim_history_idempotent`, `trim_history_preserves_prefix`
  - Runtime analogue: `trim_history` and force-compression ordering constraints.

## Runtime tests/traces tied to these assumptions

- `test/test_memory_retention.ml`
  - `trim_history count only`
  - `force_compress_history`
  - `force_compress_history noop when small`
- `test/test_memory.ml`
  - `store message with tool_calls`
  - `tool result roundtrip`
  - `tool cycle history shape` (added in this pass)

## Residual gaps

- The Coq model still abstracts provider behavior (`should_continue`) and does not
  model Lwt cancellation/interruption ordering in full detail.
- The runtime executes tools in parallel and appends results deterministically by
  call order; the model captures ordering shape but not parallel timing effects.
