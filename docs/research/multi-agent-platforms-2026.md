# Multi-Agent AI Platforms: Comparative Research (March 2026)

Research into platforms that demonstrably support rich multi-agent interaction and
substantial autonomous long-running work, with feature analysis relevant to clawq
expansion.

## Executive Summary

The multi-agent AI landscape in early 2026 has consolidated around several
production-grade approaches. The key differentiators are: (1) cloud-sandboxed
background execution with parallel agents (Cursor, Devin, Codex), (2) graph-based
stateful orchestration frameworks (LangGraph), (3) role-based team abstractions
(CrewAI, Claude Code Agent Teams), and (4) inter-agent communication protocols
(Google A2A, MCP). clawq's existing architecture (daemon, sessions, tool registry,
background tasks, durable inbound queue) provides a strong foundation; the gaps are
in multi-session coordination, structured task decomposition, and agent-to-agent
messaging.

---

## Platform Analysis

### 1. Claude Code Agent Teams (Anthropic)

**Status:** Experimental (v2.1.32+, Feb 2026). Requires Opus 4.6.

**Orchestration model:** One "team lead" session spawns teammate sessions. Each
teammate is an independent Claude Code instance with its own 1M-token context.
TeammateTool provides 13 operations: `spawnTeam`, `discoverTeams`, `requestJoin`,
`approveJoin`, `write`, `requestShutdown`, `cleanup`, etc.

**Shared state:** Shared task list with dependency tracking and auto-unblocking.
Inbox-based mailbox messaging between agents. No shared memory beyond explicit
messages — context isolation is maintained.

**Task decomposition:** Lead decomposes work into a shared task list. Teammates
claim tasks. Dependencies are tracked so blocked tasks auto-unblock when
prerequisites complete.

**Tool/runtime:** Each teammate has full Claude Code tool access. Permission
requests bubble up to the lead.

**Review loops:** Teammates can challenge each other's work and validate outputs.
No formal built-in review gate — relies on lead coordination.

**Safety:** Feature-flagged off by default. Permission model inherited from Claude
Code. No formal resource budgets per teammate.

**Resumability:** Known limitation — `/resume` and `/rewind` do not restore
in-process teammates.

**Background execution:** Each teammate runs as a separate process. Can scale to
16+ agents (demonstrated building a C compiler with 16 agents).

**Relevance to clawq:** Closest architectural analog. clawq already has sessions,
daemon supervision, and background tasks. Adding a shared task list with
dependency tracking and inter-session messaging would close the gap.

---

### 2. Cursor Background Agents + Automations

**Status:** Production (March 2026). $2B ARR, 30% of own PRs from agents.

**Orchestration model:** Up to 8 parallel cloud agents per user, each in isolated
VMs. Event-driven automations launch agents from GitHub events, Slack messages,
PagerDuty incidents, Linear issues, cron schedules, or webhooks.

**Shared state:** Git worktree isolation — each agent gets its own worktree copy.
Changes merge only when deliberately committed. No shared memory between agents.

**Task decomposition:** External — triggered by tickets, events, or user
assignment. No built-in decomposition; each agent receives a single scoped task.

**Tool/runtime:** Full dev environment (shell, file edit, browser, test runners).
Agents self-test: run builds, execute tests, record video of their work.

**Worker management:** Cloud VM per agent. Dynamic context discovery (agents pull
context themselves vs. being overloaded upfront).

**Review loops:** BugBot code review agent (70%+ resolution rate, 35% fixes merged
without modification). Agents produce merge-ready PRs.

**Observability:** Video recordings of agent work sessions. PR-based output
artifacts.

**Safety:** OS-level sandboxing (restricted tokens, filesystem ACLs). Permission
profiles with split filesystem/network policies.

**Resumability:** VM-based — sessions persist until task completion.

**Background execution:** Core differentiator. Cloud-native, fire-and-forget.
Automations turn it into a SaaS devops tool.

**Relevance to clawq:** The event-driven automation trigger model (GitHub push,
Slack message, cron, webhook -> spawn agent) is highly relevant. clawq already
has cron_jobs and webhook endpoints. Git worktree isolation per agent is a
proven pattern for safe parallel work.

---

### 3. OpenAI Codex

**Status:** Production (macOS Feb 2026, Windows Mar 2026). Powered by codex-1 (o3
variant) and GPT-5.4.

**Orchestration model:** Parallel cloud sandbox agents. Each task runs in its own
sandbox preloaded with the repository. Desktop app acts as multi-agent command
center.

**Shared state:** Each sandbox is independent. Communication via PR artifacts.

**Task decomposition:** Queue-based — users queue tasks, agents process them
asynchronously. No inter-agent decomposition.

**Tool/runtime:** Full terminal + file system in sandbox. Trained via RL to run
tests iteratively until passing.

**Review loops:** Agents propose PRs. Human reviews. No agent-to-agent review.

**Safety:** OS-level sandbox with restricted tokens and filesystem ACLs.
Permission-profile config language for precise policy control.

**Resumability:** Task-based — runs 1-30 minutes, produces artifacts.

**Background execution:** Cloud-native. Planned "Codex Jobs" automation cloud
(trigger on GitHub push, scheduled).

**Relevance to clawq:** The permission-profile config language and sandbox policy
split (filesystem vs network) are worth studying. The RL-trained "run tests
until passing" loop is an interesting agent behavior pattern.

---

### 4. Devin (Cognition Labs)

**Status:** Production. Team plan $500/mo + $2/ACU (15 min ~ 1 ACU).

**Orchestration model:** Compound AI system — multiple specialized models (Planner,
Executor, etc.) in a swarm. Multiple Devin instances can run simultaneously on
separate tasks.

**Shared state:** Per-instance sandbox. Repository indexing creates shared
knowledge base (auto-generated wikis with architecture diagrams).

**Task decomposition:** Internal Planner agent breaks tasks into steps. "The
Planner" is a high-reasoning model that outlines strategy; execution models
carry it out.

**Tool/runtime:** Shell, code editor, web browser, development environments.
Self-healing: reads error logs and iterates autonomously.

**Worker management:** Cloud sandbox per instance. Pre-configurable with
repo-specific setups.

**Review loops:** Opens PRs with detailed descriptions. Responds to human code
review comments. No formal agent-to-agent review.

**Safety:** Cloud sandbox isolation. Human-in-the-loop via PR review.

**Resumability:** Session fork and rollback — users can branch from any session
state or revert to earlier points.

**Background execution:** Core design. Operates autonomously on multi-hour tasks
assigned via Slack or Teams. "If you can do it in 3 hours, Devin can likely
do it."

**Relevance to clawq:** The session fork/rollback model is worth studying for
clawq's session management. Auto-indexing repositories into searchable
knowledge bases aligns with clawq's memory system. The Planner/Executor split
maps to clawq's potential for structured task decomposition.

---

### 5. LangGraph (LangChain)

**Status:** Production. Best raw performance in benchmarks (30-40% lower latency).

**Orchestration model:** Directed graph. Agents are nodes with typed state.
Conditional edges, branching, parallel processing. Supervisor nodes coordinate
sub-graphs.

**Shared state:** Typed state schemas with checkpointing. State is inspectable
and serializable at every step.

**Task decomposition:** Graph structure IS the decomposition. Nodes represent
tasks, edges represent dependencies and conditions.

**Tool/runtime:** Python-based. Integrates with any tool via function calling.

**Review loops:** Human-in-the-loop nodes can be inserted at any graph point.
Replay failed runs with modified inputs via LangSmith UI.

**Observability:** LangSmith — step-by-step traces with token counts per node.
Failed run replay. Best-in-class among frameworks.

**Safety:** Deterministic graph execution is most predictable. Type-safe state
transitions.

**Resumability:** Durable execution model prevents work loss during failures.
Checkpointing at every state transition.

**Background execution:** Via async Python. No built-in cloud execution.

**Relevance to clawq:** The typed state schema + checkpoint model is the gold
standard for observable, resumable multi-step workflows. clawq's task_tree
table could evolve toward this. The graph-as-decomposition pattern could
inform how clawq structures complex multi-step agent work.

---

### 6. CrewAI

**Status:** Production. 40% faster time-to-production than LangGraph for standard
workflows.

**Orchestration model:** Role-based "crews." Each agent has a role, backstory,
goal. Agents assemble into crews with assigned tasks.

**Shared state:** Shared context per crew via memory management. Role-based
prompting optimizes token usage.

**Task decomposition:** Explicit task assignment to role-specialized agents.
Sequential or parallel execution modes.

**Tool/runtime:** Python-based. Custom tool integration. A2A protocol support.

**Review loops:** Agents can review each other's outputs within the crew.

**Observability:** Less mature than LangSmith. Community tooling.

**Safety:** Role constraints limit agent scope.

**Relevance to clawq:** The role/backstory/goal pattern for agent specialization
is a lightweight way to create focused sub-agents without complex graph
structures. A2A protocol support is forward-looking.

---

### 7. Google ADK + A2A Protocol

**Status:** ADK v1.0.0 stable (production-ready). A2A v0.2 spec. Python SDK
released. Java ADK v0.1.0.

**Orchestration model:** Workflow agents (Sequential, Parallel, Loop) for
deterministic pipelines, or LLM-driven dynamic routing. Model-agnostic
(200+ models).

**Shared state:** Via A2A protocol — agents communicate over network. Agent
discovery via AgentCards (JSON capability descriptors at well-known endpoints).

**Task decomposition:** Workflow agent types handle common patterns. Complex
decomposition via LLM routing.

**Interoperability:** A2A protocol enables cross-framework agent communication.
Designed to complement MCP. 50+ industry partners.

**Relevance to clawq:** A2A protocol is the emerging standard for agent-to-agent
communication across ecosystems. clawq could expose an AgentCard and
implement A2A endpoints alongside its existing MCP server, enabling external
agents to interact with clawq sessions.

---

## Feature Matrix

| Feature | Claude Teams | Cursor | Codex | Devin | LangGraph | CrewAI | Google ADK |
|---|---|---|---|---|---|---|---|
| Multi-agent parallel | Yes (16+) | Yes (8) | Yes | Yes | Yes | Yes | Yes |
| Cloud sandbox | No (local) | Yes | Yes | Yes | No | No | Via Vertex |
| Background execution | Process-based | Cloud VMs | Cloud | Cloud | Async | Async | Cloud opt. |
| Shared task list | Yes (deps) | No | Queue | Internal | Graph state | Task list | Workflow |
| Inter-agent messaging | Mailbox | No | No | No | State edges | In-crew | A2A protocol |
| Session fork/rollback | No | Worktrees | No | Yes | Checkpoints | No | No |
| Event-driven triggers | No | Yes (rich) | Planned | Slack/Teams | No | No | No |
| Observability | Limited | Video+PR | PR | PR+wiki | LangSmith | Basic | Cloud logs |
| Typed state/schema | No | No | No | No | Yes | No | Yes |
| Protocol support | MCP | None | None | None | Community | A2A | MCP+A2A |
| Resumability | Limited | VM-based | Task-based | Fork/rollback | Checkpoints | No | Stateless opt. |

---

## Recommendations for clawq Feature Expansion

### High Priority (directly actionable, builds on existing architecture)

1. **Structured Task Decomposition with Dependencies**
   - Evolve `task_tree` table into a first-class shared task system with status
     tracking, dependency edges, and auto-unblocking.
   - Model: Claude Code Agent Teams task list + LangGraph checkpoint semantics.
   - Why: clawq already has `task_tree` and `background_task` tables. Adding
     dependency tracking and status progression is incremental.

2. **Inter-Session Messaging / Mailbox**
   - Add a message-passing mechanism between sessions (mailbox table in SQLite).
   - Sessions can send findings, request reviews, or delegate sub-tasks.
   - Model: Claude Code Agent Teams mailbox + A2A protocol concepts.
   - Why: clawq's `inbound_queue` already demonstrates durable message delivery.
     Inter-session messaging is a natural extension.

3. **Session Isolation via Git Worktrees**
   - When spawning parallel agent sessions for the same repo, create per-session
     git worktrees to prevent file conflicts.
   - Model: Cursor Background Agents worktree isolation.
   - Why: Prevents the most common multi-agent failure mode (concurrent file
     edits). Git worktrees are lightweight and well-understood.

4. **Event-Driven Agent Triggers**
   - Extend cron_jobs to support webhook/event triggers (GitHub push, issue
     creation, Slack/Telegram message patterns).
   - Model: Cursor Automations trigger model.
   - Why: clawq already has HTTP server endpoints and channel integrations.
     Connecting inbound events to agent session spawning is a natural bridge.

### Medium Priority (significant value, moderate effort)

5. **Session Fork and Rollback**
   - Allow forking a session's state (history, memory) at any point, creating
     a branch for exploration or parallel approaches.
   - Model: Devin session fork/rollback.
   - Why: Valuable for exploratory tasks and error recovery. clawq's session
     state is already persisted in SQLite, making fork semantically simple.

6. **Agent Observability Dashboard**
   - Expose per-session token usage, tool invocations, task progress, and
     error rates through the web UI.
   - Model: LangSmith traces + Cursor video recordings (simplified).
   - Why: `request_stats` table already captures per-turn token/cost data.
     Surfacing this with task correlation enables oversight of multi-agent work.

7. **Typed Task State / Checkpointing**
   - Add optional typed state schemas to tasks so that intermediate results
     are inspectable, serializable, and resumable after failures.
   - Model: LangGraph typed state + durable execution.
   - Why: Makes long-running tasks robust against crashes and enables
     human inspection of intermediate progress.

### Lower Priority (forward-looking, ecosystem positioning)

8. **A2A Protocol Support**
   - Expose clawq sessions as A2A-compatible agents with AgentCard discovery.
   - Enable clawq to consume external A2A agents as tool providers.
   - Model: Google ADK A2A integration.
   - Why: Emerging interoperability standard. clawq already has MCP server;
     A2A adds agent-level discovery and delegation.

9. **Role-Based Agent Specialization**
   - Allow session configs to include role/persona definitions that constrain
     the agent's tool access and behavioral focus.
   - Model: CrewAI role/backstory/goal pattern.
   - Why: Lightweight way to create focused sub-agents for specific domains
     (testing, code review, documentation) without architectural changes.

10. **Cloud Sandbox Execution (Optional)**
    - Support optional remote sandbox execution for agent sessions (container
      or VM-based) for users who want isolation beyond Landlock.
    - Model: Cursor/Codex cloud VMs.
    - Why: Lower priority because clawq's Landlock + Firejail/Bubblewrap
      sandbox already provides local isolation. Cloud execution is an
      enterprise feature.

---

## Key Architectural Insights

**What works in production:**
- Git worktree isolation is the pragmatic standard for multi-agent file safety
- Durable message queues (not shared memory) are the reliable inter-agent pattern
- Task lists with dependency tracking outperform free-form agent coordination
- Event-driven triggers (not just cron) are essential for autonomous operation
- Permission models must scale to multi-agent (bubble-up or pre-approve)

**What clawq already has that others don't:**
- Formal verification pipeline (Coq extraction) — unique safety guarantee
- Durable inbound queue with at-least-once delivery — production-grade messaging
- Landlock OS sandboxing + Firejail/Bubblewrap — defense in depth
- MCP server for tool interoperability
- Per-session Lwt_mutex + lazy memory cleanup — solid concurrency foundation

**Critical gap vs. leaders:**
- No structured multi-session coordination (task decomposition + messaging)
- No git worktree isolation for parallel agent work
- No event-driven agent spawning beyond cron
- Limited observability of multi-agent workflows

---

## Sources

- [Claude Code Agent Teams docs](https://code.claude.com/docs/en/agent-teams)
- [Claude Code's Hidden Multi-Agent System](https://paddo.dev/blog/claude-code-hidden-swarm/)
- [Cursor Automations](https://www.helpnetsecurity.com/2026/03/06/cursor-automations-turns-code-review-and-ops-into-background-tasks/)
- [Cursor Background Agents](https://cursor.com/product)
- [OpenAI Codex cloud](https://developers.openai.com/codex/cloud/)
- [OpenAI Agents SDK orchestration](https://openai.github.io/openai-agents-python/multi_agent/)
- [Devin 2.0](https://cognition.ai/blog/devin-2)
- [Devin AI Guide 2026](https://aitoolsdevpro.com/ai-tools/devin-guide/)
- [Google ADK + A2A](https://google.github.io/adk-docs/a2a/)
- [LangGraph vs CrewAI vs AutoGen 2026](https://dev.to/synsun/autogen-vs-langgraph-vs-crewai-which-agent-framework-actually-holds-up-in-2026-3fl8)
- [Top AI Agent Frameworks 2026](https://www.shakudo.io/blog/top-9-ai-agent-frameworks)
- [Multi-Agent Frameworks for Enterprise 2026](https://www.multimodal.dev/post/best-multi-agent-ai-frameworks)
