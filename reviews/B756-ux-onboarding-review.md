# B756: UX/Onboarding Review for Claude Tag Parity Features

**Date**: 2026-07-02  
**Author**: MiMo (audit subagent)  
**Scope**: Onboarding readiness for Claude Tag parity features in clawq — setup flows, documentation, UX. This audit focuses on the new-user-to-productive-user path, not a comprehensive parity feature inventory (see `docs/plans/2026-06-28-claude-tag-parity-bundle-inventory.md` for that).

---

## Executive Summary

Clawq has strong CLI coverage and good documentation for most parity features, but **onboarding is fragmented**. The `clawq onboard` wizard covers provider/model/channel basics but does not touch room agents, access bundles, memory governance, cost tracking, or structured pipelines. Users must discover these features through docs or CLI help, then manually edit `config.json` or run separate wizards.

**Key gaps:**
1. No unified onboarding path from "install" to "room agent with budgets and memory"
2. Access bundles and credential handles have no CLI management surface
3. Cost tracking and activity ledger have no setup wizards
4. Several features require `CLAWQ_ADMIN=1` — the error messages are helpful but the path from error to resolution could be clearer
5. Docs for security policy (credentials, egress) are authoritative but not linked from the room-agent onboarding path

---

## 1. Feature-by-Feature Audit

### 1.1 Room Agents (Room Profiles + Bindings)

**Onboarding readiness: PARTIAL**

| Aspect | Status | Details |
|--------|--------|---------|
| Setup wizard | YES | `clawq rooms wizard` (plan/apply/rerun modes) |
| CLI help | YES | `clawq rooms --help`, `clawq rooms wizard --help` |
| Docs | YES | `docs/pilot-setup-wizard.md`, `docs/setup-guide.md` (Section 4), `docs/src/content/docs/room-agents.mdx` |
| Interactive guidance | GOOD | Wizard prompts for profile-id, model, connector, room; includes access bundle selection, memory scope setup, budget setup, connector detection, profile-id validation, and readiness checks |

**What works well:**
- The room wizard (`setup_room_wizard.ml`) already includes access bundle selection, memory scope setup, budget setup, connector detection, profile-id validation, and readiness checks.
- Admin errors are not bare: `require_admin` returns "Error: this command requires admin privileges. Set CLAWQ_ADMIN=1 in ..." with guidance.
- Profile ID validation exists with helpful constraints (lowercase alphanumeric, hyphens, underscores, max 64 chars).
- Readiness checks catch missing bundles, invalid room IDs, and other configuration issues.

**Remaining UX gaps:**
- **Non-interactive `--connector` default**: `--connector` defaults to `teams` regardless of what's configured. A user with only Slack configured gets a confusing failure in non-interactive mode. (Interactive mode auto-detects correctly.)
- **No "quick start" path**: There's no `clawq rooms quickstart` that auto-detects configured connectors and walks through a minimal setup in one command.
- **CLI reference docs inconsistency**: `docs/cli-reference.md` documents `clawq rooms wizard --plan/--apply/--rerun` as flags, but the code uses subcommands: `wizard plan|apply|rerun`.

**Actionable items:**
1. Make `--connector` default to the first configured connector in non-interactive mode (not hardcoded `teams`).
2. Consider adding a `clawq rooms quickstart` command that combines connector detection + profile creation + binding in one flow.
3. Fix the CLI reference docs to match the actual subcommand syntax.

---

### 1.2 Access Bundles

**Onboarding readiness: MISSING (CLI management)**

| Aspect | Status | Details |
|--------|--------|---------|
| Setup wizard | PARTIAL | Room wizard accepts `--access-bundles` and validates referenced bundles exist |
| CLI help | NO | No `clawq access-bundles` or equivalent CLI surface |
| Docs | YES | `docs/room-agent-architecture.md`, `docs/setup-guide.md` (Section 7), `docs/src/content/docs/room-agents.mdx`, `docs/security-policy-guide.md` |
| Validation | YES | Config loading (`config_loader.ml`) validates bundle structure; room wizard readiness checks catch missing bundles |
| Interactive guidance | PARTIAL | `clawq rooms explain-access` surfaces effective access including bundle contributions |

**UX gaps:**
- **No CLI management**: Access bundles are only configurable via `config.json`. No `clawq access-bundles create/list/show/edit/delete`.
- **Complex JSON structure**: Access bundles have nested objects (repo_grants, egress_rules, credential_handles) that are error-prone to hand-edit.
- **No standalone validation**: No `clawq access-bundles validate` to check bundle config outside the room wizard context.

**Actionable items:**
1. Add `clawq access-bundles` CLI surface: `list`, `show`, `create`, `edit`, `delete`, `validate`.
2. Add inline examples in `clawq access-bundles --help`.
3. Link to `docs/security-policy-guide.md` from the room wizard help output.

---

### 1.3 Credential Handles

**Onboarding readiness: MISSING (CLI management)**

| Aspect | Status | Details |
|--------|--------|---------|
| Setup wizard | NO | No wizard for creating/editing credential handles |
| CLI help | NO | No `clawq credentials` or equivalent CLI surface |
| Docs | YES | `docs/setup-guide.md` (Section 7), `docs/security-policy-guide.md` (Section 1) |
| Encryption | YES | `clawq auth encrypt` encrypts plaintext secrets; `$ENC:` format documented |
| Validation | YES | Config loading validates handle structure |

**UX gaps:**
- **No CLI management**: Credential handles are only configurable via `config.json`. No `clawq credentials create/list/show/edit/delete`.
- **No encryption CLI**: `clawq auth encrypt` exists but is not discoverable from the credential handle docs.

**Actionable items:**
1. Add `clawq credentials` CLI surface: `list`, `show`, `create`, `edit`, `delete`, `validate`.
2. Link `clawq auth encrypt` from credential handle documentation.
3. Add inline examples in `clawq credentials --help`.

---

### 1.4 Egress Policy

**Onboarding readiness: MISSING (CLI management)**

| Aspect | Status | Details |
|--------|--------|---------|
| Setup wizard | NO | No wizard for creating/editing egress rules |
| CLI help | NO | No `clawq egress` or equivalent CLI surface |
| Docs | YES | `docs/setup-guide.md` (Section 8), `docs/security-policy-guide.md` (Section 2) |
| Validation | YES | Config loading validates egress rule structure; readiness checks verify egress audit schema |
| Introspection | YES | `clawq rooms explain-access` shows egress summaries |

**UX gaps:**
- **No CLI management**: Egress rules are only configurable via `config.json`. No `clawq egress rules/create/list/show/edit/delete`.
- **No testing**: No `clawq egress test` to simulate a request against current rules.
- **Default-deny confusion**: The docs say "all outbound requests are denied by default" but there's no inline warning when a user first enables a room agent without egress rules.

**Actionable items:**
1. Add `clawq egress` CLI surface: `rules`, `create`, `show`, `edit`, `delete`, `test`.
2. Add `clawq egress test --host api.github.com --path /repos --method GET` to simulate rule evaluation.
3. Add a readiness check warning when egress rules are not configured for a profiled room.

---

### 1.5 Room Memory (Scoped Memory)

**Onboarding readiness: GOOD**

| Aspect | Status | Details |
|--------|--------|---------|
| Setup wizard | PARTIAL | Room wizard configures memory scope; no separate memory wizard |
| CLI help | YES | `clawq rooms memory --help` shows `save ... [--visibility V]` |
| Docs | YES | `docs/memory-governance-guide.md`, `docs/src/content/docs/room-agents.mdx` |
| Interactive guidance | GOOD | CLI commands work with room_id; visibility levels documented; grant management documented |

**What works well:**
- `--visibility` flag is shown in `clawq rooms memory save --help` output.
- Grant management commands are documented with admin gating explained.
- Memory governance guide is comprehensive.

**Remaining UX gaps:**
- **Private visibility docs drift**: The docs in `docs/memory-governance-guide.md` state that `private` memories are never surfaced through room agent tools due to a wiring issue. However, current code (`visibility_principal` in `tools_builtin_room_memory.ml`) does use the bound profile id when available. The docs are stale and should be updated to reflect the current behavior.
- **No room memory configuration in room wizard**: The room wizard sets up memory scope but doesn't offer to configure visibility defaults or initial grants.

**Actionable items:**
1. Update `docs/memory-governance-guide.md` to reflect that private visibility now works correctly when a room has a bound profile.
2. Add visibility defaults and grant configuration to the room wizard flow.

---

### 1.6 Cost Tracking

**Onboarding readiness: GOOD**

| Aspect | Status | Details |
|--------|--------|---------|
| Setup wizard | PARTIAL | Room wizard configures budget limits; no separate cost wizard |
| CLI help | YES | `clawq costs --help`, `clawq usage --help`, `clawq active --help` |
| Docs | PARTIAL | Documented in `docs/cli-reference.md`, `docs/src/content/docs/cli-reference.mdx`, `docs/src/content/docs/room-agents.mdx` |
| Output format | GOOD | `clawq costs` output has column headers (PERIOD, COST, TURNS, PROMPT, ADDED, COMPLETION) with `$` units |

**What works well:**
- `clawq costs` output has proper column headers and units.
- Room wizard includes budget configuration (token limits, cost limits, reset periods).
- Budget readiness checks are comprehensive.

**Remaining UX gaps:**
- **No standalone cost wizard**: Cost tracking is auto-enabled but there's no `clawq setup cost` wizard for configuring budget limits outside the room wizard context.
- **No cost alerts**: No `clawq costs alerts` or `clawq costs set-alert` to configure cost threshold notifications.

**Actionable items:**
1. Consider adding `clawq setup cost` wizard for standalone budget configuration.
2. Consider adding `clawq costs alerts` to show/configure alert thresholds.

---

### 1.7 Activity Ledger

**Onboarding readiness: GOOD**

| Aspect | Status | Details |
|--------|--------|---------|
| Setup wizard | NO | Activity ledger is auto-enabled for profiled rooms |
| CLI help | YES | `clawq rooms ledger --help` shows filters (room-id, event-type, from, to, actor, profile-id, thread-id, task-id, background-id, requester, status) |
| Docs | PARTIAL | Documented in `docs/cli-reference.md`, `docs/src/content/docs/cli-reference.mdx`, `docs/src/content/docs/room-agents.mdx` |
| Interactive guidance | GOOD | Filters are documented; export formats documented |

**What works well:**
- `clawq rooms ledger list --help` shows all available filters.
- Export supports JSON and JSONL formats.
- Retention cleanup is available.

**Remaining UX gaps:**
- **No retention configuration CLI**: `clawq rooms ledger retention-cleanup` exists but there's no `clawq rooms ledger set-retention` to configure the default retention period.
- **No dedicated docs page**: Activity ledger is documented in CLI reference but has no dedicated docs page.

**Actionable items:**
1. Add `clawq rooms ledger set-retention --days 90` to configure default retention.
2. Consider adding a dedicated docs page for activity ledger.

---

### 1.8 Structured Pipelines

**Onboarding readiness: PARTIAL**

| Aspect | Status | Details |
|--------|--------|---------|
| Setup wizard | YES | `clawq pipeline wizard` |
| CLI help | YES | `clawq pipeline --help` |
| Docs | PARTIAL | Documented in `docs/cli-reference.md`, `docs/src/content/docs/cli-reference.mdx`, `docs/src/content/docs/background-tasks.mdx` |
| Room integration | YES | Pipelines can be triggered from rooms via `/workflow run <pipeline>` slash command and `clawq pipeline trigger ... --room-id ...` |

**What works well:**
- Pipeline wizard exists for interactive pipeline creation.
- Pipelines can be triggered from rooms via slash commands.
- Pipeline validation exists.

**Remaining UX gaps:**
- **No room-profile pipeline binding**: No way to bind a default pipeline to a room profile (e.g., `"pipeline": "my-pipeline"` in room profile config).

**What works well:**
- `clawq pipeline create` scaffolds a YAML file with a complete example including inputs, steps, and output schema.

**Actionable items:**
1. Add pipeline binding to room profiles: `"pipeline": "my-pipeline"` in room profile config.

---

### 1.9 Agent Templates

**Onboarding readiness: PARTIAL**

| Aspect | Status | Details |
|--------|--------|---------|
| Setup wizard | YES | `clawq agents setup` |
| CLI help | YES | `clawq agents --help` |
| Docs | PARTIAL | Documented in `docs/cli-reference.md`, `docs/src/content/docs/cli-reference.mdx` |
| Room integration | PARTIAL | Agent templates can be used with subagents (`--agent`) and background tasks; no room-profile binding |

**What works well:**
- Agent template wizard exists (`clawq agents setup`).
- Agent templates can be used with subagents and background tasks.
- Template validation exists in config loading.

**Remaining UX gaps:**
- **No room-profile template binding**: No way to bind a default agent template to a room profile.
- **No inline examples**: `clawq agents create` scaffolds a YAML file but doesn't include inline examples.
- **No binding guidance**: `clawq agents bind` exists but doesn't explain what patterns are or how to use them.

**Actionable items:**
1. Add agent template binding to room profiles: `"agent_template": "my-template"` in room profile config.
2. Add inline examples in `clawq agents create --help`.
3. Add `clawq agents bind --help` explaining pattern syntax and usage.

---

### 1.10 Subagents (Native/Local)

**Onboarding readiness: GOOD**

| Aspect | Status | Details |
|--------|--------|---------|
| Setup wizard | NO | No dedicated wizard; subagents are auto-enabled |
| CLI help | YES | `clawq subagents --help` |
| Docs | YES | `docs/src/content/docs/background-tasks.mdx`, `docs/cli-reference.md` |
| Interactive guidance | GOOD | CLI commands documented; repo path, agent template, and model options explained |

**What works well:**
- Subagent CLI is well-documented with clear help text.
- Background tasks docs page covers subagents thoroughly.
- Agent template integration works (`--agent` flag).

**Remaining UX gaps:**
- **No repo path guidance**: `clawq subagents start` requires a repo path but doesn't explain how to find or select one.
- **No model selection guidance**: `clawq subagents start --model` exists but doesn't explain what models are available.

**Actionable items:**
1. Add `clawq subagents start --help` with examples showing repo path usage.
2. Consider adding `clawq subagents start --interactive` that lists available repos and models.

---

## 2. Additional Parity Features (Not Covered in Detail)

The following features from the parity bundle inventory (`docs/plans/2026-06-28-claude-tag-parity-bundle-inventory.md`) are implemented but not audited in detail for onboarding readiness. They are listed here for completeness:

| Feature | Status | Notes |
|---------|--------|-------|
| Room Routines | IMPLEMENTED | `clawq rooms routine` CLI surface exists; documented in CLI reference |
| Ambient Follow-ups | IMPLEMENTED | Ambient watcher, stale queries, delivery lifecycle exist; configuration via room profile |
| GitHub App Identity | IMPLEMENTED | GitHub App auth, repo grants, PR subscriptions, backlinks exist; setup via `clawq setup github` |
| Effective-Access Introspection | IMPLEMENTED | `clawq rooms explain-access` shows resolved access including bundles, credentials, egress |
| Scoped Instructions | IMPLEMENTED | Room profile `system_prompt` and layered instructions exist |
| Progress Checklists | IMPLEMENTED | Teams Adaptive Cards and Slack mrkdwn progress rendering exist |
| Session Records | IMPLEMENTED | `clawq rooms session` CLI surface exists |
| Governance Modes | PARTIAL | Quiet/off/legacy modes partially implemented via room profile status and ambient settings |

---

## 3. Documentation Completeness

### 3.1 Docs Site Coverage

| Feature | Docs Site | CLI Reference | Setup Guide | Room Agents | Memory Gov | Security Policy | Background Tasks |
|---------|-----------|---------------|-------------|-------------|------------|-----------------|------------------|
| Room Agents | YES | YES | YES | YES | YES | YES | YES |
| Access Bundles | PARTIAL | NO | YES | YES | NO | YES | NO |
| Credential Handles | NO | NO | YES | NO | NO | YES | NO |
| Egress Policy | NO | NO | YES | NO | NO | YES | NO |
| Room Memory | PARTIAL | YES | NO | YES | YES | NO | NO |
| Cost Tracking | PARTIAL | YES | NO | YES | NO | NO | NO |
| Activity Ledger | PARTIAL | YES | NO | YES | NO | NO | NO |
| Structured Pipelines | PARTIAL | YES | NO | NO | NO | NO | YES |
| Agent Templates | PARTIAL | YES | NO | NO | NO | NO | NO |
| Subagents | PARTIAL | YES | NO | NO | NO | NO | YES |

### 3.2 Documentation Gaps

1. **No dedicated docs pages** for access bundles, credential handles, egress policy, cost tracking, or activity ledger.
2. **Scattered coverage**: Room agent docs are split across `room-agents.mdx`, `setup-guide.md`, `pilot-setup-wizard.md`, `memory-governance-guide.md`, and `security-policy-guide.md`.
3. **No quickstart for room agents**: The quickstart page covers basic setup but not room-agent configuration.
4. **CLI reference docs inconsistency**: `docs/cli-reference.md` documents `clawq rooms wizard --plan/--apply/--rerun` as flags, but the code uses subcommands: `wizard plan|apply|rerun`.

---

## 4. UX Review

### 4.1 New User Journey

A new user installing clawq would:

1. Install via npm: `npm install -g @clawq/clawq`
2. Run `clawq onboard` — configures provider, model, channel
3. Run `clawq agent` — starts daemon
4. Send a message to the bot — works

**What's missing:**
- No guidance on setting up room agents, access bundles, or memory governance
- No guidance on configuring cost tracking or activity ledger
- No guidance on using structured pipelines or agent templates
- No guidance on using subagents

### 4.2 Room Agent Setup Journey

A user wanting to set up a room agent would:

1. Read `docs/pilot-setup-wizard.md` or `docs/setup-guide.md`
2. Create access bundles in `config.json` (manual, but validated by config loader)
3. Create credential handles in `config.json` (manual, but validated by config loader)
4. Create egress rules in `config.json` (manual, but validated by config loader)
5. Run `clawq rooms wizard` to create room profile and binding (includes readiness checks)
6. Run `clawq rooms readiness` to verify setup
7. Send a message to the room — works

**What works well:**
- Steps 2-4 are validated by config loading and room wizard readiness checks.
- Step 5 includes comprehensive readiness checks that catch missing bundles, invalid room IDs, and other issues.
- `clawq rooms explain-access` shows resolved effective access.

**What's missing:**
- No CLI for steps 2-4 (manual config.json editing)
- No examples of common configurations
- No troubleshooting for room-agent-specific issues

### 4.3 Confusing Defaults

1. **Teams-first in non-interactive mode**: The room wizard defaults to Teams connector in non-interactive mode even if only Slack is configured. (Interactive mode auto-detects correctly.)
2. **Admin gating**: Many commands require `CLAWQ_ADMIN=1`. The error messages are helpful ("Set CLAWQ_ADMIN=1 in ...") but the path from error to resolution could be clearer.
3. **Profile-id format**: The wizard validates profile-id format but doesn't explain the constraints inline.

### 4.4 Missing Error Messages

1. **Budget exceeded**: The redacted error message is intentionally vague for security, but could include a pointer to `clawq costs` or `clawq rooms readiness` for the admin.
2. **Egress denied**: No inline guidance on how to add egress rules when a request is denied.

---

## 5. Onboarding Readiness Ranking

| Feature | Readiness | Priority | Key Gap |
|---------|-----------|----------|---------|
| Room Agents | GOOD | HIGH | Non-interactive `--connector` default; CLI reference docs inconsistency |
| Access Bundles | MISSING (CLI) | HIGH | No CLI management surface |
| Credential Handles | MISSING (CLI) | HIGH | No CLI management surface |
| Egress Policy | MISSING (CLI) | HIGH | No CLI management surface |
| Room Memory | GOOD | MEDIUM | Private visibility docs drift |
| Cost Tracking | GOOD | MEDIUM | No standalone cost wizard |
| Activity Ledger | GOOD | MEDIUM | No retention configuration CLI |
| Structured Pipelines | PARTIAL | LOW | No room-profile pipeline binding |
| Agent Templates | PARTIAL | LOW | No room-profile template binding |
| Subagents | GOOD | LOW | No repo path guidance |

---

## 6. Recommended Actions

### 6.1 High Priority (P14)

1. **Add CLI surface for access bundles**: `clawq access-bundles list/show/create/edit/delete/validate`
2. **Add CLI surface for credential handles**: `clawq credentials list/show/create/edit/delete/validate`
3. **Add CLI surface for egress rules**: `clawq egress rules/create/show/edit/delete/test`
4. **Fix `--connector` default**: Default to first configured connector in non-interactive mode
5. **Fix CLI reference docs**: Update `docs/cli-reference.md` to match actual subcommand syntax

### 6.2 Medium Priority (P14)

6. **Fix private visibility docs drift**: Update `docs/memory-governance-guide.md` to reflect current behavior
7. **Add retention configuration CLI**: `clawq rooms ledger set-retention --days 90`
8. **Add inline help text**: Link to `docs/security-policy-guide.md` from room wizard help output
9. **Add dedicated docs pages**: For access bundles, credential handles, egress policy

### 6.3 Low Priority (P15)

10. **Add pipeline binding to room profiles**: `"pipeline": "my-pipeline"` in room profile config
11. **Add agent template binding to room profiles**: `"agent_template": "my-template"` in room profile config
12. **Add standalone cost wizard**: `clawq setup cost` for budget configuration outside room wizard
13. **Add cost alerts**: `clawq costs alerts` to show/configure alert thresholds

---

## 7. Appendix: Evidence

### 7.1 Source Files Checked

- `src/setup_main.ml` — Setup wizard hub (no room agent, access bundle, or cost tracking wizards)
- `src/setup_room_wizard.ml` — Room wizard (exists, well-implemented with access bundle, memory, budget, connector detection, validation)
- `src/command_bridge.ml` — CLI command routing
- `src/command_bridge_agent_cmds.ml` — Room/agent CLI commands
- `src/command_bridge_room_memory.ml` — Room memory CLI commands (includes `--visibility` flag)
- `src/command_bridge_usage.ml` — Cost tracking CLI (includes column headers)
- `src/subagent_tool.ml` — Subagent LLM tools
- `src/room_activity_ledger.ml` — Activity ledger implementation
- `src/room_budget.ml` — Cost tracking implementation
- `src/structured_pipeline.ml` — Structured pipeline implementation
- `src/agent_template.ml` — Agent template implementation
- `src/memory_scoped.ml` — Scoped memory implementation
- `src/memory_types.ml` — Memory visibility types
- `src/config_loader.ml` — Config validation (validates bundles, handles, egress rules)
- `src/slash_commands.ml` — Slash commands (includes `/workflow run <pipeline>`)

### 7.2 Docs Files Checked

- `docs/cli-reference.md` — Full CLI reference
- `docs/setup-guide.md` — Comprehensive setup guide
- `docs/pilot-setup-wizard.md` — Room wizard documentation
- `docs/memory-governance-guide.md` — Memory governance guide
- `docs/room-agent-architecture.md` — Room agent architecture
- `docs/security-policy-guide.md` — Security & policy guide (credentials, egress, room policy)
- `docs/src/content/docs/room-agents.mdx` — Room agents docs page
- `docs/src/content/docs/background-tasks.mdx` — Background tasks docs page
- `docs/src/content/docs/cli-reference.mdx` — CLI reference docs page
- `docs/src/content/docs/quickstart.mdx` — Quickstart docs page
- `docs/src/content/docs/configuration.mdx` — Configuration docs page
- `docs/src/content/docs/tools.mdx` — Tools docs page
- `docs/plans/2026-06-28-claude-tag-parity-bundle-inventory.md` — Parity bundle inventory

### 7.3 CLI Help Output Checked

- `clawq --help` — Main help
- `clawq rooms --help` — Room management help
- `clawq rooms wizard --help` — Room wizard help
- `clawq rooms memory --help` — Room memory help (shows `--visibility`)
- `clawq rooms ledger --help` — Activity ledger help (shows filters)
- `clawq costs --help` — Cost tracking help
- `clawq usage --help` — Usage help
- `clawq active --help` — Active window help
- `clawq subagents --help` — Subagents help
- `clawq pipeline --help` — Pipeline help
- `clawq agents --help` — Agent templates help
- `clawq setup --help` — Setup wizard help

---

*End of report.*
