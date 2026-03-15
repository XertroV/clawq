# B458: Investigation — How Skills Are Loaded Into the Chat Log

## Context

This is a pure research task. We want to understand exactly how skills are injected into the conversation history — what message roles they use, whether they replace or augment the user message, deduplication behavior, how the three activation pathways differ, and how they interact with compaction.

## Findings

### Message Assembly Order (the final API call)

Understanding where skill messages end up requires tracing the full `build_messages` flow in `agent.ml:115-126`:

```
Final message list sent to LLM API:
  1. system_prompt        (role: system)  — built by Prompt_builder.build()
  2. ...history messages   (role: various) — List.rev of agent.history
     ↑ skill @mention system messages live here, interleaved in history
     ↑ compaction summary replaces old messages here
  3. runtime_context       — prepended to the FIRST user message's content
     (injected by inject_runtime_context, which finds the first role:"user"
      message and prepends the runtime_context block to its content)
```

Key detail: `agent.history` is stored **reversed** (newest first via `::`). `build_messages` does `List.rev` to get chronological order. So skill system messages prepended via `::` end up at the **end** of the history (just before the current user message).

### Where `@mention` skill messages land in context

In `session_turn.ml:137-141`, skill injections are prepended to `agent.history`:
```ocaml
agent.history <- Provider.make_message ~role:"system" ~content :: agent.history
```

Since history is reversed, and the user message is added *later* in `prepare_turn_history` (line 1698: `agent.history <- user_msg :: agent.history`), the final chronological order is:

```
[system prompt]
[...older history...]
[skill system msg 1]     ← @mention injections land here
[skill system msg 2]
[current user message]   ← with runtime_context prepended to its content
```

So skill `@mention` messages appear as **system messages immediately before the current user message** — essentially as "just-in-time context" adjacent to the user's turn.

### Three Activation Pathways

#### 1. `@skill-name` mentions (auto-attach)

**Flow:** User message → `expand_skill_refs()` in `session_turn.ml:114-115` → skill instructions extracted → injected into history

**Message role: SYSTEM** — Each matched skill becomes a separate `role:"system"` message prepended to `agent.history` (`session_turn.ml:137-141`). These land **just before the current user message** in chronological order.

**Format:** `[Skill: <name>]\n<instructions>`

**User message: UNCHANGED** — The original message text is NOT modified (the `@skill-name` text stays in the user message). The skill content is added as *additional* system messages, not as a replacement.

**Arguments: NOT SUPPORTED** — `@mention` has no argument syntax. The `$ARGUMENTS` placeholder is not substituted. This also means deduplication is straightforward since there's no per-invocation variation.

**Deduplication:** Hashtable in `extract_skill_refs()` (`skills.ml:523,560-561`) prevents the same skill being injected twice from the same message. The `md_skills` list (for the Available Skills section in runtime context) is also deduplicated in `session_turn.ml:118-128`. **No cross-turn deduplication** — mentioning `@skill` in consecutive messages injects it each time.

**Command injections: NO** — `expand_skill_refs` does not call `Skills_cmd_inject.expand_injections`.

**Key code:** `src/skills.ml:520-593`, `src/session_turn.ml:103-141`

#### 2. `/skill-name` slash commands

**Flow:** User text → `Slash_commands.handle()` → returns `SkillInvoke(name, args)` → connector (telegram/discord/http_server) intercepts and **rewrites the user message**.

**Message role: USER** — The skill content **replaces the user's message**. The original `/skill-name args` is rewritten to:
```
[Skill: <name>]
<instructions with $ARGUMENTS substituted>

User request: <args>
```
The `SkillInvoke` result is converted to `NotACommand` with the rewritten text, so the chat receives it as a normal user message.

**User message: REPLACED** — The original slash command text is fully replaced by the expanded skill content + original args.

**Command injections: NO** — only `substitute_arguments` is called, not `Skills_cmd_inject.expand_injections`. **This is a bug** — if a skill relies on `!`cmd`` for dynamic content, slash commands deliver the raw injection syntax instead of executed results.

**Deduplication:** None needed — single skill per slash command.

**Key code:** Identical pattern in `src/discord.ml:496-506`, `src/telegram.ml:309-319`, `src/http_server.ml:352-362`

#### 3. `use_skill` tool call

**Flow:** LLM calls `use_skill` tool → `skills.ml:621-699` → returns skill instructions as tool output text.

**Message role: TOOL/ASSISTANT** — The skill content appears as tool call output in the standard tool-use flow (assistant sends tool_use, response is tool result).

**User message: NOT INVOLVED** — This is initiated by the LLM, not the user.

**Command injections: YES** — `use_skill` calls `Skills_cmd_inject.expand_injections` (`skills.ml:678-679`), executing any `!`cmd`` patterns in the skill body. This is the **only** pathway that executes command injections.

**Deduplication:** None — LLM can call `use_skill` multiple times for the same skill.

**Key code:** `src/skills.ml:621-699`

### Summary Table

| Pathway | Trigger | Role of Injected Content | User Message | Cmd Injection | Dedup | Arguments |
|---------|---------|-------------------------|--------------|---------------|-------|-----------|
| `@mention` | User types `@skill-name` | **system** (separate msg, just before user msg) | Unchanged | No | Yes (per-message, not cross-turn) | No |
| `/slash` | User types `/skill-name args` | **user** (replaces msg) | Replaced entirely | **No (bug)** | N/A | Yes ($ARGUMENTS) |
| `use_skill()` | LLM tool call | **tool result** | N/A (LLM-initiated) | Yes | No | Yes ($ARGUMENTS) |

### Interaction with Compaction

Compaction happens in `prepare_turn_history` (`agent.ml:1674-1701`), which is called **after** skill injection in `session_turn.ml`:

```
Timeline within run_locked_turn:
  1. expand_skill_refs() extracts @mentions           (line 114)
  2. skill system messages prepended to history        (line 137-141)
  3. inject_attachment_context                          (line 136)
  4. effective_message built                            (line 142-144)
  5. prepare_turn_history() called                     (line 155)
     → adds user message to history                    (agent.ml:1698)
     → compact_history_if_needed()                     (agent.ml:1699)
     → trim_history                                    (agent.ml:1700)
  6. runtime_context built (includes Available Skills)  (line 162-167)
  7. LLM turn executed with build_messages()
```

**Consequence:** Skill system messages from `@mention` are part of `agent.history` when compaction runs. If the history is long enough to trigger compaction, these skill system messages **could be summarized away** along with older history. They are not protected from compaction.

**After compaction:** The runtime_context "Available Skills" listing (step 6) is rebuilt fresh each turn, so the LLM always knows which skills exist. But the actual skill *instructions* from `@mention` could be lost if they were in the compacted portion.

**For `use_skill` tool calls:** These appear as tool_use/tool_result pairs in history and are also subject to compaction — but since they're typically recent (in the current turn), they're less likely to be compacted away.

### Additional Context: Available Skills Listing

All available skills are listed in the **runtime context** (system prompt section) via `prompt_builder.ml:244-254`:
```
## Available Skills
Use the `use_skill` tool or `/skill-name` to activate a skill. Reference @skill-name in messages to auto-attach.
- skill-name-1: description
- skill-name-2: description
```

This is injected by prepending to the first user message's content (`inject_runtime_context` at `agent.ml:105-113`). Always present regardless of activation pathway, rebuilt fresh each turn.

### Observations / Issues Found

1. **Role inconsistency**: `@mention` injects as system, `/slash` injects as user, `use_skill` injects as tool result. Same skill content, three different roles.

2. **Command injection gap (bug)**: `/slash` commands do NOT run `expand_injections`, but `use_skill` does. Skills with `!`cmd`` will not work correctly via `/slash`.

3. **No cross-turn deduplication for @mentions**: If a user mentions `@skill-name` in multiple consecutive messages, the skill instructions get injected as a new system message each time.

4. **Compaction can lose skill instructions**: `@mention` skill system messages are part of history and subject to compaction. No mechanism to re-inject them after compaction.

5. **Slash command replaces user intent**: When `/skill-name do something` is used, the user's original text disappears — it's embedded inside a larger formatted string.

6. **Code duplication**: The `SkillInvoke` handling with `Printf.sprintf "[Skill: %s]\n%s\n\nUser request: %s"` is copy-pasted identically across discord.ml, telegram.ml, http_server.ml.

7. **`use_skill` as system message (potential change)**: Currently returns as tool result. Could alternatively inject as a system message (like `@mention`) for consistency, but this would change the tool-use flow semantics — the LLM expects tool results, not silence.

### Design Decisions (from user feedback)

These decisions should guide the follow-up tasks:

1. **Unified system message approach**: All 3 pathways should inject skill instructions as **system messages** (not user messages, not tool results).

2. **`use_skill` tool**: Return brief tool result like `"Loaded skill X, has_args: true"`. Also inject a system message with the full instructions (same format as `@mention`).

3. **`/skill-name` (no args)**: Leave user message as-is (`/skill-name` stays in user message). Add system message with skill instructions. **Dedupeable** (no args = same content each time).

4. **`/skill-name args`**: Leave user message as-is. Add **non-dedupeable** system message with expanded skill (args substituted). Each invocation with different args produces different content.

5. **Dedup logic**: Dedup based on skill name + whether arguments are provided. If `$ARGUMENTS` is not used/provided, assume same content → dedupeable. On dedup hit, add a brief system message like "User invoked skill X (already loaded) — follow those instructions."

6. **Command injection**: All pathways should run `expand_injections` (fix the `/slash` bug).

7. **Compaction interaction**:
   - Instruct the summarizer to **exclude skill bodies** from the summary
   - After compaction, **auto-reload eligible skills** as system messages (noting they were autoloaded due to compaction)
   - Message order after compaction: `[system prompt] → [skill system msgs] → [compaction summary] → [agent] → [user] → ...`

## Follow-Up Backlog: New Phase Structure

Create phase **"Skill Injection Overhaul"** with one milestone, one epic, and 5 tasks.
Reference plan: `~/.claude-w/plans/stateless-orbiting-hippo.md`

### Task 1: Unify all skill activation pathways to system messages
**Estimate:** 4h | **Complexity:** high | **Priority:** high

Currently @mention injects as system msg, /slash replaces the user msg, use_skill returns as tool result. Unify all three to inject skill instructions as system messages:
- @mention (`@skill` anywhere in body): already system messages — no change to injection mechanism
- /slash (`/skill` at start of message only, no args): leave user message as-is, inject dedupeable system message with skill body
- /slash (with args): leave user message as-is, inject NON-dedupeable system message with $ARGUMENTS expanded
- use_skill tool: return brief "Loaded skill X, has_args: true/false" as tool result; also inject full instructions as system message
- Extract shared SkillInvoke handling from discord.ml, telegram.ml, http_server.ml into skills.ml
- When loading via @mention or /slash, send connector notification "Loaded skill: X" (NOT a system message — visible user notification via connector send). use_skill doesn't need this since it shows in tool log.

**Acceptance Criteria:**
- [ ] All 3 pathways inject skill instructions as role:"system" messages
- [ ] /slash no longer replaces the user message
- [ ] use_skill returns brief acknowledgment as tool result, not full instructions
- [ ] Shared skill expansion logic extracted to skills.ml (no copy-paste in connectors)
- [ ] @mention and /slash send "Loaded skill: X" notification to user via connector
- [ ] Existing tests updated; new tests for each pathway
- [ ] `make test` passes

**Files:** `src/skills.ml`, `src/session_turn.ml`, `src/discord.ml`, `src/telegram.ml`, `src/http_server.ml`, `src/slack.ml`, `src/slash_commands.ml`

### Task 2: Fix command injection in /slash and @mention pathways
**Estimate:** 1h | **Complexity:** medium | **Priority:** high | **Depends on:** T001

/slash and @mention only call substitute_arguments, not Skills_cmd_inject.expand_injections. Skills with `!`cmd`` syntax don't work via these pathways. Fix: run expand_injections in all pathways (shared code from Task 1 makes this straightforward).

**Acceptance Criteria:**
- [ ] All 3 pathways call expand_injections
- [ ] Test with a skill containing `!`cmd`` syntax via each pathway
- [ ] `make test` passes

**Files:** `src/skills.ml`

### Task 3: Cross-turn skill deduplication
**Estimate:** 2h | **Complexity:** medium | **Priority:** medium | **Depends on:** T001

When a skill is invoked without arguments (any pathway), check if the same skill system message already exists in recent history. If so, add a brief system message "User invoked skill X (already loaded) — follow those instructions." instead of re-injecting the full body. Dedup key: skill name + whether args are provided (NOT command expansion output — assume same if $ARGUMENTS not used/provided).

**Acceptance Criteria:**
- [ ] No-args invocation is deduped: second mention of same skill injects brief "already loaded" msg
- [ ] With-args invocation is NOT deduped: each invocation injects full expanded body
- [ ] Dedup checks recent history (not just current message)
- [ ] Tests for dedup and non-dedup cases
- [ ] `make test` passes

**Files:** `src/skills.ml`, `src/session_turn.ml`

### Task 4: Compaction-aware skill reloading
**Estimate:** 3h | **Complexity:** high | **Priority:** medium | **Depends on:** T001

Two changes: (1) Instruct the compaction summarizer to exclude skill instruction bodies from the summary. (2) After compaction, auto-reload eligible skills as system messages marked autoloaded. Target message order after compaction: `[system prompt] → [skill system msgs (autoloaded)] → [compaction summary] → [conversation continues]`.

**Acceptance Criteria:**
- [ ] Compaction summarizer prompt instructs LLM to exclude skill bodies
- [ ] After compaction, active skills are re-injected as system messages
- [ ] Re-injected skills marked as autoloaded (e.g., "[Skill: X (autoloaded after compaction)]")
- [ ] Message order: system prompt → skills → compaction summary → rest
- [ ] Tests for compaction with skills in history
- [ ] `make test` passes

**Files:** `src/agent.ml`, `src/session_turn.ml`, `src/prompt_builder.ml`

### Task 5: Connector notification for skill loading
**Estimate:** 1h | **Complexity:** low | **Priority:** medium | **Depends on:** T001

When a skill is loaded via @mention or /slash, send "Loaded skill: X" to the user via the connector's normal send_message. NOT for use_skill (tool log shows it). Skill system messages (instructions) never sent via connector.

**Acceptance Criteria:**
- [ ] @mention triggers "Loaded skill: X" message via connector
- [ ] /slash triggers "Loaded skill: X" message via connector
- [ ] use_skill does NOT trigger connector notification
- [ ] Skill instruction system messages never sent to user
- [ ] `make test` passes

**Files:** `src/session_turn.ml`, connector files

## Backlog Commands

```bash
# Create phase
bl add-phase -T "Skill Injection Overhaul" -w 2 -e 11 -p high \
  --description "Unify skill loading across all activation pathways to use system messages, add deduplication, fix command injection gap, and handle compaction. Plan: ~/.claude-w/plans/stateless-orbiting-hippo.md"

# Create milestone (assuming phase = P10)
bl add-milestone P10 -T "Unified Skill Loading" -e 11 -c high

# Create epic
bl add-epic P10.M1 -T "Skill System Messages & Compaction" -e 11 -c high

# Create tasks
bl add P10.M1.E1 -T "Unify all skill activation pathways to system messages" \
  -e 4 -c high -p high \
  -b "Unify @mention, /slash, and use_skill to all inject as system messages. /slash stops replacing user message. use_skill returns brief ack, injects system msg. Extract shared handling from connectors into skills.ml. Send connector notification 'Loaded skill: X' for @mention and /slash. Plan: ~/.claude-w/plans/stateless-orbiting-hippo.md"

bl add P10.M1.E1 -T "Fix command injection in /slash and @mention pathways" \
  -e 1 -c medium -p high -d P10.M1.E1.T001 \
  -b "Run expand_injections in all pathways, not just use_skill. Plan: ~/.claude-w/plans/stateless-orbiting-hippo.md"

bl add P10.M1.E1 -T "Cross-turn skill deduplication" \
  -e 2 -c medium -p medium -d P10.M1.E1.T001 \
  -b "Dedup no-args skill invocations across turns. Inject brief 'already loaded' msg on dedup hit. With-args not deduped. Key: skill name + has_args. Plan: ~/.claude-w/plans/stateless-orbiting-hippo.md"

bl add P10.M1.E1 -T "Compaction-aware skill reloading" \
  -e 3 -c high -p medium -d P10.M1.E1.T001 \
  -b "Exclude skill bodies from compaction summaries. Auto-reload active skills after compaction as system msgs marked autoloaded. Order: [sys prompt]->[skills]->[compaction summary]->[conversation]. Plan: ~/.claude-w/plans/stateless-orbiting-hippo.md"

bl add P10.M1.E1 -T "Connector notification for skill loading" \
  -e 1 -c low -p medium -d P10.M1.E1.T001 \
  -b "Send 'Loaded skill: X' via connector for @mention and /slash. NOT for use_skill. Skill instruction system msgs never sent via connector. Plan: ~/.claude-w/plans/stateless-orbiting-hippo.md"
```

## Plan Steps

1. `git rebase master` to ensure up to date with parent branch
2. Run the backlog commands above to create phase/milestone/epic/tasks
3. `bl done B458` to mark the investigation task complete
4. Load and use the `review-and-fix` skill as the final step
