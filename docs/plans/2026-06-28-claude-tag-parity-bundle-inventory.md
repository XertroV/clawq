# Claude Tag parity bundle inventory

Date: 2026-06-28

Source bundle: `/home/xertrov/Downloads/claude_tag_clawq_parity_bundle_2026-06-28.zip`

Purpose: enumerate every feature in the bundle and correct its public-doc-only
Clawq status against the current checkout plus a lightweight look at
`~/.clawq/memory.db` and `~/.clawq/config.json`. This is an investigation
artifact only; it does not ingest P14 tasks.

## High-level corrections

- The bundle is directionally right that Room Agents are the parity anchor, but
  the current checkout is ahead of the bundle in several areas.
- Current code already has room profile config, shared room session routing,
  room workspaces, scoped memory tables/grants, room budgets with pre-call
  reservations, room activity ledger, room routines, ambient stale-work followup,
  connector capability gates, and Slack progress delivery.
- Current live config has no `room_profiles`, `room_profile_bindings`, or
  `room_profile_codebase_grants`; connector history is disabled. The live DB has
  schema support but no active room profile/budget/scoped-memory usage.
- Access bundles and the credential/egress proxy model are still the largest
  architecture gap. Existing room profiles are a useful substrate, not a full
  Claude Tag Access-bundle equivalent.
- GitHub is PAT/webhook based. I did not find GitHub App installation identity,
  per-room repo grants, or PR subscription objects.
- There is a docs inconsistency: `room-agents.mdx` describes Slack as ambient
  history capable, while `configuration.mdx` says Slack does not use the
  separate connector-history capture path because normal Slack events already
  arrive. Code marks Slack as ambient-history capable.

## Evidence checked

- Bundle files: `README.md`, `00_EXECUTIVE_BRIEF.md`,
  `02_FEATURE_CATALOG.md`, `03_IMPLEMENTATION_ROADMAP.md`,
  `07_CLAWQ_PARITY_MATRIX.md`, `feature_catalog.json`,
  `clawq_public_capability_inventory.json`.
- Code/docs surfaces: `src/slack.ml`, `src/room_session.ml`,
  `src/room_workspace.ml`, `src/room_budget.ml`,
  `src/room_activity_ledger.ml`, `src/memory_scoped.ml`,
  `src/room_progress.ml`, `src/room_ambient_delivery.ml`,
  `src/ambient_daemon.ml`, `src/ambient_inspection.ml`,
  `src/room_request_classifier.ml`, `src/background_task_spawn.ml`,
  `src/connector_capabilities.ml`, `src/runtime_config*.ml`,
  `src/config_loader.ml`, `src/agent.ml`, `src/agent_2_tools.ml`,
  `src/mcp*.ml`, `src/github*.ml`, `docs/src/content/docs/room-agents.mdx`,
  `docs/src/content/docs/configuration.mdx`, `docs/public/llms-full.txt`.
- Runtime data: `~/.clawq/memory.db` schemas and table counts;
  `~/.clawq/config.json` room/profile/channel fields.

## Inventory

| ID | Feature | Bundle status | Verified current status | P14 disposition |
|---|---|---:|---|---|
| FT-01 | Slack-native @mention entrypoint | partial | Partial. Slack event handling, allowlists, shared profiled room session keys, threaded replies, reactions, and progress messages exist. It processes allowed message events rather than a polished Tag-only mention flow. | Candidate only if we want Tag-mode UX hardening. |
| FT-02 | Thread-scoped multiplayer session | partial | Partial. Profiled Slack rooms resolve to shared `slack:<channel>` sessions; async room work records `thread_id` and can reply into Slack threads. I did not find a full participants/session-record model. | Candidate. |
| FT-03 | Visible progress checklist | partial | Partial. Room-origin background tasks can send/edit progress/final messages and Slack uses reactions/status updates. This is not yet a durable checklist/event bus with planned/current/blocked artifact links. | Candidate. |
| FT-04 | Open/read-only session record | partial | Partial. Session history, messages, background transcripts, request stats, and web UI primitives exist; no clear per-room task URL with prompt/plan/tool/artifact/cost/access snapshot. | Candidate. |
| FT-05 | Ephemeral cloud sandbox per thread | partial | Partial/different. Background tasks can use worktrees, room workspaces, native/local runner, sandbox/Landlock/Docker primitives. Room workspaces are persistent, not cloud-ephemeral per thread. | Candidate if sandbox isolation is desired. |
| FT-06 | Session persistence + idle release semantics | partial | Partial. Session state, durable inbound queue, background task readoption, room workspace GC, and thread metadata exist. Not full idle cloud-resource release/resume semantics. | Candidate. |
| FT-07 | Agent identity / service-account mode | partial | Partial. Bot/channel identity and room profile identity exist; no service-account registry with cross-service attribution/credential ownership. | Candidate. |
| FT-08 | Access bundles | likely_missing | More than missing, but not implemented. Room profiles cover model/system prompt/tool policy/ambient and codebase grants, but not composable bundles of credentials/repos/plugins/domains/instructions with inheritance/conflict snapshots. | Strong P14 candidate. |
| FT-09 | Scopes and inheritance: default, workspace, channel | partial | Partial. Room profile bindings, scoped memory, grants, and config validation exist. No default/workspace/channel inheritance resolver or `explain-access` equivalent. | Strong P14 candidate. |
| FT-10 | Credential injection through proxy; no credentials in sandbox/model | likely_missing | Likely missing. Secrets are redacted/encrypted and tool/file/network safety exists, but I found no Agent Proxy that mediates outbound HTTP/git/API credentials while hiding secrets from sandboxes/model. | Strong P14 candidate. |
| FT-11 | Default-deny egress with host/path/method rules | partial | Partial. There is sandboxing, workspace policy, audit, and HTTP tooling, but no default-deny egress proxy with host/path/method/read-only rules for all sandbox traffic. | Strong P14 candidate. |
| FT-12 | Connection gallery and typed credential support | partial | Partial. Many setup wizards and typed config parsers exist; no bindable connection gallery/manifests attached to room scopes. | Candidate. |
| FT-13 | Slack context access rules | partial | Partial. Slack receives message events and records scoped room history when bound. I did not find Slack Web API retrieval for bounded earlier history, pins, or public channel search with explainability. | Candidate. |
| FT-14 | Direct-message personal mode | partial | Partial. Session-key formats distinguish personal/room-style contexts; credential separation between personal connectors and room service credentials is not a first-class policy. | Maybe later. |
| FT-15 | Workspace memory for public channels + private-channel isolation | partial | Partial but substantial. Scoped memory tables, grants, room scope search, and profiled-room privacy guard exist. Public-workspace sharing versus private-channel isolation semantics are not fully surfaced/configured. | Candidate. |
| FT-16 | Memory management: save, list, correct, forget | partial | Partial. Global memory tools exist and scoped memory CRUD/grants exist internally/tests. I did not find complete in-channel room scoped memory CRUD with provenance/admin UX. | Candidate. |
| FT-17 | Scheduled routines | partial | Mostly implemented. `rooms routine create/list/show/edit/remove/enable/disable/trigger` exists on top of cron with profile/thread/workspace metadata. In-channel natural-language creation remains a UX layer. | Maybe no P14, unless UX/channel ownership polish. |
| FT-18 | Channel watching routines | partial | Partial. Connector history, stale queries, and ambient watcher exist; not generalized source-channel/topic-filter watch subscriptions. | Candidate. |
| FT-19 | Pull-request subscriptions | partial | Partial. GitHub webhooks, check/review event context, stable PR/issue sessions, and hook files exist. No room-owned PR subscription object with CI/review backoff/list/disable semantics found. | Candidate. |
| FT-20 | GitHub App identity, repo grants, and PR creation | partial | Partial. GitHub PAT/webhook/API reply support exists. I did not find GitHub App installation identity or per-room repo grants. | Candidate, especially identity/grants. |
| FT-21 | Project context file loading for code tasks | partial | Partial/strong. Project docs and workspace instruction loading exist and refresh on cwd/root changes; automatic repo-name-to-context with room grants/provenance is not complete. | Maybe later. |
| FT-22 | Plugins and skills attached to scopes | partial | Partial. Skills and MCP tools exist, and room profiles can restrict tools. I did not find per-room skill/plugin enablement with version pins and running-thread snapshots. | Candidate. |
| FT-23 | Skills repository with Claude-proposed PR improvements | partial | Partial/mostly missing. Skills can be created/loaded and agents can open PRs generally, but no governed skill-repo proposal loop tied to room scope. | Maybe later. |
| FT-24 | Rich outputs: answer, file, chart, maintained page, PR | partial | Partial. Background tasks/logs/transcripts and connector file/status surfaces exist; no unified artifact service with stable IDs/URLs/renderers. | Candidate. |
| FT-25 | Admin setup wizard and Slack workspace pairing | partial | Partial. Setup wizards for Slack/GitHub/config exist. No single Tag-style pilot room pairing wizard that verifies room/access/routine/GitHub. | Candidate. |
| FT-26 | Multi-workspace / Enterprise Grid routing | unknown | Unknown/likely missing. Channels carry workspace/team identifiers in places, but I did not find Enterprise Grid-style routing/isolation semantics. | Defer unless enterprise Slack is priority. |
| FT-27 | Governance: invocation restrictions, guest/shared-channel controls | partial | Partial. Channel allowlists, admin registration, guest help hiding, guest async-policy denial, and profile tool grants exist. Slack guest/external shared-channel refusal not found. | Candidate. |
| FT-28 | Quiet/remove/off/legacy controls | partial | Partial. Profiles can be disabled/deleted, rooms can bind/unbind, routines can enable/disable, ambient quiet hours exist. No complete response-mode surface for off/mention-only/ambient/legacy per room. | Candidate. |
| FT-29 | Audit page, service-account attribution, network events | partial | Partial. Security audit log and room activity ledger exist with export/filter/retention. Missing service-account attribution model and network proxy events. | Candidate, tied to FT-10/11. |
| FT-30 | Spend limits and per-channel usage analytics | partial | Strong partial. Per-profile budgets, provider pre-call checks/reservations, soft warnings, request stats `profile_id`, and redacted denial exist. Missing org/workspace/room billing product and admin analytics UI. | Maybe polish, not core P14. |
| FT-31 | Capability introspection: what can you access here? | partial | Partial. `rooms show`, `rooms inspect`, config/status commands exist. No redacted natural-language effective-access summary over inherited scopes/bundles/credentials. | Candidate. |
| FT-32 | Ambient proactive replies / follow-ups | likely_missing | Correct to partial. Ambient delivery, stale query, watcher decisions, quiet hours, rate limit, budget gate, connector capability gate, and ledger recording exist. Operational channel UX/config polish still needed. | Maybe polish, not core P14. |
| FT-33 | Admin custom instructions layered by scope | partial | Partial. Room profile `system_prompt` and model exist. No layered default/workspace/channel/admin instruction resolver with precedence/provenance/session snapshots. | Candidate. |
| FT-34 | Slack install and migration from legacy bot | not_applicable | Optional/partial. Room binding is room-by-room and can coexist with legacy behavior, but no migration wizard/compat mode found. | Defer unless migration is a goal. |
| FT-35 | Model/runtime constraints and selection strategy | implemented | Implemented/exceeds Tag. Provider:model convention, channel/session/model-set/default selection, room model field, and many providers exist. | No P14. |
| FT-36 | Future: expand beyond Slack into other workplace tools | implemented | Implemented as substrate. 17 channel configs exist; room-agent semantics are not uniformly complete across all channels. | No core P14, except connector parity polish. |
| FT-37 | Future: JIT credential grants and identity-aware user overlays | likely_missing | Likely missing. I found no JIT grant/elevation model or personal+service identity overlay. | Defer unless high priority. |
| FT-38 | Launch credits / org usage balance model | not_applicable | Not applicable as Anthropic GTM. Operational budgets are covered separately by FT-30. | No P14. |
| FT-39 | Documented limitations and parity exclusions | implemented | Mostly implemented in docs and this report. A formal decision register could still help. | No core P14. |
| FT-40 | Use-case and prompt library | partial | Partial. Built-in skills, agent prompts, docs, and examples exist; no Tag-parity use-case/template library. | Optional enablement. |
| FT-41 | Channel-owned routines survive creator changes with boundaries | unknown | Partial. Routines are profile/session owned rather than creator-owned; I did not find creator-removal semantics or explicit boundary logs. | Candidate if governance matters. |
| FT-42 | Network/event audit export boundaries | likely_missing | Mostly missing. Audit and ledger export exist; network event export boundaries need an egress proxy/network event model first. | Candidate tied to FT-10/11/29. |
| FT-43 | Slack guest and external shared-channel behavior | unknown | Likely missing. Guest/admin exists, but no Slack Connect/external-channel policy surfaced in code/docs found. | Candidate. |
| FT-44 | Room Agents as Clawq's likely parity anchor | partial | Implemented as architecture/docs/code substrate; missing a `room-agent parity` readiness/report command. | Maybe small P14 task. |
| FT-45 | Formal verification advantage and boundaries | implemented | Implemented as documented differentiator. New parity policy engines would need proofs/tests if we want to preserve the story. | No standalone P14; attach proof tasks to selected P0s. |
| FT-46 | MCP client/server as integration substrate | implemented | Implemented substrate. MCP server/client and external tool discovery exist. Room-scoped MCP policy/bundle/credential/audit wrapping is not implemented. | Candidate only as part of FT-08/10/22. |

## Suggested P14 grouping candidates

1. Access and scope policy core: FT-08, FT-09, FT-31, FT-33.
2. Credential and egress safety: FT-10, FT-11, FT-29, FT-42, plus MCP wrapping from FT-46.
3. Connector room-agent UX hardening: FT-01, FT-02, FT-03, FT-04, FT-13, generalized through connector capabilities with Teams as the highest-priority production connector and Slack as the Tag comparison baseline.
4. Memory semantics: FT-15, FT-16, and public/private room sharing rules.
5. GitHub/code integration governance: FT-19, FT-20, FT-21, FT-23.
6. Admin and governance polish: FT-25, FT-27, FT-28, FT-41, FT-43.
7. Optional enablement/polish: FT-24, FT-34, FT-40, FT-44.

## User selection notes for P14 planning

- Definitely include access/scope policy work. The plan should treat bundles,
  inherited scopes, effective-access snapshots, and explain/introspection
  surfaces as central rather than optional polish.
- Include credential/egress safety, but keep it staged. Early P14 should design
  the policy/proxy boundary and ensure new access abstractions do not paint us
  into a corner; full outbound proxy coverage can land later if it would
  distract from the core room-agent/user-facing work.
- Improve Slack UX because it is the Claude Tag comparison target, but do not
  make the design Slack-only. Generalize through connector capability surfaces
  wherever possible, with Teams as the highest-priority work connector.
- Definitely include room-scoped memory semantics and management.
- Definitely include GitHub App/bot work: service identity, global and per-room
  repo grants, PR subscriptions, CI/review update reporting, triggered runs
  such as security reviews, and backlinks where appropriate.
- Include an admin wizard experience plus governance controls, especially where
  they help pilot and verify a real room setup.
- Treat model/runtime selection as done except for integration with new scope
  policy snapshots.
- Treat launch credits as Anthropic-specific business-model material and skip.
- Do not implement formal proofs in P14, but add proof/spec follow-up entries
  for selected policy/session/memory invariants so verification work can follow.

## Items probably not worth implementing as parity work

- FT-35, FT-38, FT-39, FT-45 as standalone work.
- FT-37 unless JIT elevation becomes a concrete enterprise requirement.
- FT-34 unless there are real legacy Slack installs to migrate.
