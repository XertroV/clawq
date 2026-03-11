# src/CLAUDE.md

## Tool Error Messages

Error messages returned from tools must be descriptive and actionable. Each error should:

1. Clearly state what went wrong.
2. Include instructions on how to repair the function call (e.g., which parameter was invalid, what format is expected, what values are acceptable).
3. Suggest alternative recovery paths when a simple fix isn't possible (e.g., "file not found — check the path or use `list_dir` to discover available files").

Bad example:
```
Error: invalid parameter
```

Good example:
```
Error: parameter "path" must be an absolute path starting with "/". Received: "foo/bar.txt". Use an absolute path like "/home/user/foo/bar.txt", or call the "list_dir" tool first to discover files relative to the workspace root.
```

This applies to all tool implementations in `tools_builtin.ml`, `skills.ml`, and any tools exposed via `mcp_server.ml`.

## Provider API Requirements

When working on provider implementations, consult the relevant requirements docs:
- **OpenAI Responses API** (used by `provider_openai_codex.ml`): See `src/RESPONSES_API_REQUIREMENTS.md`
- **Anthropic Messages API** (used by `provider_anthropic.ml`): See `src/ANTHROPIC_API_REQUIREMENTS.md` (when created)

## Database Location

- Main database: `~/.clawq/memory.db` (contains `messages`, `session_state`, `models_cache`, `request_stats`, `task_tree`, `cron_jobs`, `inbound_queue`, etc.)
- Config: `~/.clawq/config.json`
- Daemon state: `~/.clawq/daemon_state.json`

## Durable Inbound Queue Semantics

1. Offline `session inject` enqueues to the `inbound_queue` SQLite table (schema v5), not directly to chat history. At-least-once delivery: `attempt_count` and `last_error` track retries.
2. Replay uses FIFO per-session ordering (`ORDER BY id ASC`).
3. Bang messages (`!`-prefixed) are preserved through the queue/replay cycle via a `bang` JSON field.
4. `replay_durable_inbound_queue` runs after `resume_sessions_after_channels` at daemon startup. Stale claims (>3600 s) and failed rows are reclaimed before replay begins.
5. Empty messages are recorded as failures (`"empty message"`), not replayed.
6. Both `Memory.clear_session` and `Session.reset` delete pending queue rows for the target session.
7. `session pending SESSION` shows queue rows; `session list` appends `pending_inbound=N` when count > 0.
