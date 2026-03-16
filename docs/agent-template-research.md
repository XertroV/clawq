# Agent Template Best Practices for AI Agent Systems

Research compiled March 2026. Covers CrewAI, Claude Code, OpenAI Agents SDK, multi-agent coordination, system prompt design, and tool restriction patterns.

---

## Table of Contents

1. [CrewAI Role/Goal/Backstory Pattern](#1-crewai-rolegoalbackstory-pattern)
2. [Claude Code Subagent Patterns](#2-claude-code-subagent-patterns)
3. [OpenAI Agents SDK Patterns](#3-openai-agents-sdk-patterns)
4. [Multi-Agent Coordination Patterns](#4-multi-agent-coordination-patterns)
5. [System Prompt Best Practices for Specialized Agents](#5-system-prompt-best-practices-for-specialized-agents)
6. [Tool Restriction Patterns](#6-tool-restriction-patterns)

---

## 1. CrewAI Role/Goal/Backstory Pattern

### The Core Triad

CrewAI structures every agent definition around three required fields. These are injected directly into the system prompt sent to the underlying model:

- **role**: The agent's area of expertise and function within the team. Acts as the primary persona anchor.
- **goal**: The individual objective that guides decision-making. Should be a single, focused directive.
- **backstory**: Contextual depth that shapes how the agent approaches problems. Not decorative — it directly influences output quality by establishing implied constraints, experience level, and domain framing.

These three fields, combined at inference time, construct a rich persona that reduces hallucinations and enforces consistent behavior across turns.

### What Makes Each Field Effective

**Role** should be specific enough to constrain behavior, not just label it:

```yaml
# Weak
role: "Analyst"

# Strong
role: "SaaS Metrics Specialist focusing on growth-stage startups"
```

**Goal** should be singular and action-oriented. Overloading goals creates ambiguity about what to optimize for:

```yaml
# Weak
goal: "Analyze things and report findings and also make recommendations"

# Strong
goal: "Identify actionable insights from business data that can directly impact customer retention"
```

**Backstory** should establish implied expertise that changes how the agent reasons, not just what it knows:

```yaml
# Weak
backstory: "You are an analyst."

# Strong
backstory: "With 10+ years analyzing SaaS business models, you've developed a keen eye for
the metrics that truly matter — the ones that separate sustainable growth from vanity."
```

### Key Configuration Fields

Beyond the triad, CrewAI agents support:

| Field | Default | Effect |
|---|---|---|
| `tools` | none | Capabilities available; start lean and add only when needed |
| `llm` | GPT-4 | Model powering the agent; match to task complexity |
| `allow_delegation` | False | Whether agent can assign subtasks to other agents |
| `reasoning` | False | Enables upfront planning before task execution |
| `max_iterations` | 20 | Hard stop to prevent runaway loops |
| `respect_context_window` | True | Auto-summarizes when approaching token limits |
| `code_execution_mode` | unsafe | Use `"safe"` (Docker sandbox) in production |

### Best Practices

- Use YAML config files for agent definitions rather than hardcoding. Keeps configuration separate from implementation, easier to version and review.
- Use `{topic}` dynamic placeholders in role/goal/backstory to make definitions reusable across contexts.
- Set `allow_delegation=False` for specialist worker agents; reserve `True` for manager/coordinator agents.
- Enable `reasoning=True` only for strategic planning agents — it adds latency.
- Match LLM to task: use capable models for reasoning-heavy roles, cheaper/faster models for routine tasks.
- Chain agents in purpose-built sequences: Planner → Researcher → Coder → Critic is a proven execution chain.
- Assign each agent one role. Multiple conflicting responsibilities degrade accuracy.

---

## 2. Claude Code Subagent Patterns

### What Subagents Are

Claude Code subagents are specialized agent instances defined as Markdown files with YAML frontmatter. Each subagent runs in its own isolated context window with a custom system prompt, specific tool access, and independent permissions. The parent agent delegates tasks to subagents via the `Agent` tool; only the subagent's final message returns to the parent — not intermediate tool calls or reasoning.

### File Format

```markdown
---
name: code-reviewer
description: Expert code review specialist. Proactively reviews code for quality, security, and maintainability. Use immediately after writing or modifying code.
tools: Read, Grep, Glob
model: sonnet
---

You are a senior code reviewer. When invoked:
1. Run git diff to see recent changes
2. Focus on modified files
3. Begin review immediately

Review for: readability, error handling, security, test coverage, naming clarity.

Provide feedback organized by: Critical (must fix) / Warnings (should fix) / Suggestions.
```

### Storage Locations and Priority

| Location | Scope | Priority |
|---|---|---|
| `--agents` CLI flag | Current session only | 1 (highest) |
| `.claude/agents/` | Current project, shareable via VCS | 2 |
| `~/.claude/agents/` | All projects for one user | 3 |
| Plugin `agents/` directory | Where plugin is enabled | 4 (lowest) |

### Supported Frontmatter Fields

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Lowercase with hyphens; used as identifier |
| `description` | Yes | Natural language for when Claude should delegate here — this is the routing signal |
| `tools` | No | Allowlist of tools; inherits all if omitted |
| `disallowedTools` | No | Denylist removed from inherited set |
| `model` | No | `sonnet`, `opus`, `haiku`, full model ID, or `inherit` |
| `permissionMode` | No | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, `plan` |
| `maxTurns` | No | Hard cap on agentic turns |
| `skills` | No | Injects skill content into context at startup |
| `mcpServers` | No | MCP servers scoped to this subagent only |
| `hooks` | No | Lifecycle hooks (PreToolUse, PostToolUse, Stop) |
| `memory` | No | Persistent memory: `user`, `project`, or `local` |
| `background` | No | Set `true` to run concurrently |
| `isolation` | No | Set `worktree` to run in isolated git worktree |

### Built-in Subagents

Claude Code ships with built-in subagents that demonstrate the intended patterns:

| Agent | Model | Tools | Purpose |
|---|---|---|---|
| Explore | Haiku | Read-only | Fast codebase search; denied Write/Edit |
| Plan | Inherits | Read-only | Gather context for planning; denied Write/Edit |
| General-purpose | Inherits | All | Complex multi-step tasks requiring both read and write |
| Bash | Inherits | Bash | Terminal commands in isolated context |

### Programmatic Definition (Agent SDK)

Via the Claude Agent SDK, subagents can be defined inline:

```python
from claude_agent_sdk import query, ClaudeAgentOptions, AgentDefinition

async for message in query(
    prompt="Review the authentication module for security issues",
    options=ClaudeAgentOptions(
        allowed_tools=["Read", "Grep", "Glob", "Agent"],
        agents={
            "code-reviewer": AgentDefinition(
                description="Expert code reviewer. Use for quality, security, maintainability reviews.",
                prompt="You are a code review specialist with expertise in security and performance...",
                tools=["Read", "Grep", "Glob"],
                model="sonnet",
            ),
        },
    ),
):
    pass
```

The `Agent` tool must be in `allowed_tools` for delegation to work. Subagents cannot spawn other subagents.

### Key Patterns

**Context isolation**: Each subagent starts with a fresh context. The only channel from parent to subagent is the task prompt string. Include file paths, error messages, and any decisions the subagent needs directly in the prompt.

**Description as routing signal**: Claude uses the `description` field to decide when to delegate. Write descriptions that are specific about triggers: "Use proactively after code changes" rather than just "reviews code."

**Read-only for review work**: Reviewer and auditor agents should have only `Read, Grep, Glob`. This enforces constraints and reduces risk of unintended modification.

**Model selection by workload**: Use `haiku` for fast lookups and exploration; `sonnet` for analysis; `opus` for complex reasoning or high-stakes reviews. Routing cheap tasks to Haiku directly controls cost.

**Persistent memory for institutional knowledge**: Enable `memory: user` on reviewer subagents to accumulate codebase-specific patterns across sessions.

**Hooks for fine-grained validation**: When you need to allow a tool but restrict specific operations within it, use `PreToolUse` hooks rather than removing the tool entirely. For example, allowing `Bash` but blocking write SQL operations via a validation script.

---

## 3. OpenAI Agents SDK Patterns

### Core Primitives

The OpenAI Agents SDK (released March 2025) is built around three composable primitives:

- **Agent**: An LLM configured with instructions, tools, and optional handoffs and guardrails.
- **Handoff**: A mechanism for an agent to delegate execution to another agent.
- **Guardrail**: A validation layer that runs on input, output, or per tool call.

### Agent Definition

```python
from agents import Agent

agent = Agent(
    name="Research Specialist",
    instructions="You are a research specialist. Find accurate, cited information on requested topics. Never fabricate sources.",
    model="gpt-4o",
    tools=[web_search, file_lookup],
    handoffs=[escalate_to_human],
)
```

The `instructions` field is the system prompt. The SDK recommends using prompt templates with variables rather than hardcoded strings, so a single base prompt can adapt to multiple contexts without maintaining separate prompts per variant.

**Context injection**: The `context` parameter on `Runner.run()` is passed to every agent, tool, and handoff in the run. Use it for dependency injection — user session data, configuration, shared state. Agents are generic on their context type.

### Handoff Patterns

Handoffs represent agent-to-agent delegation as a tool call. The LLM sees a `transfer_to_<agent_name>` tool and decides when to invoke it.

Two main patterns:

**Manager pattern**: A central orchestrator agent coordinates specialists via tool calls. The manager retains context and synthesizes results. Best for workflows where unified context matters.

```python
manager = Agent(
    name="Support Manager",
    instructions="Route customer requests to the appropriate specialist. Synthesize their responses.",
    handoffs=[billing_agent, technical_agent, refund_agent],
)
```

**Decentralized (handoff) pattern**: Agents transfer full execution control to another agent. The receiving agent takes over completely. Best for triage workflows or when you want clean handoff without the originator retaining responsibility.

Include handoff context in agent instructions. The SDK provides a recommended prompt prefix (`agents.extensions.handoff_prompt.RECOMMENDED_PROMPT_PREFIX`) that explains handoff semantics to the model.

### Guardrails

Guardrails are validation checks attached to agents. They run with a fast/cheap model to validate inputs or outputs before committing to expensive operations.

```python
from agents import Agent, input_guardrail, GuardrailFunctionOutput

@input_guardrail
async def topic_guardrail(ctx, agent, input) -> GuardrailFunctionOutput:
    # Use a cheap model to check if input is on-topic
    result = await fast_classifier.run(input)
    return GuardrailFunctionOutput(
        output_info=result,
        tripwire_triggered=result.is_off_topic,
    )

expensive_agent = Agent(
    name="Deep Researcher",
    instructions="...",
    input_guardrails=[topic_guardrail],
)
```

**Input guardrails** run only for the first agent in a chain. **Output guardrails** run only on the final output agent. **Tool guardrails** run on every function-tool invocation.

**Execution modes**:
- `run_in_parallel=True` (default): Guardrail runs concurrently with the agent. Lower latency, but the agent may consume tokens before cancellation.
- `run_in_parallel=False`: Guardrail completes before the agent starts. Zero token waste when guardrail trips, but adds serial latency.

**Layered defense**: No single guardrail provides sufficient protection. Stack multiple specialized guardrails — topic classification, safety check, output format validation — for resilience.

### Built-in Tools

The Responses API (the underlying API layer) provides hosted tools that agents can use without managing infrastructure:

- `web_search` — real-time web retrieval with citations
- `file_search` — RAG over uploaded vector stores
- `code_interpreter` — sandboxed code execution
- `computer_use` — UI interaction sequences (requires `computer-use-preview` model)

These are specified in the `tools` array alongside custom function tools. The model decides which to call based on the task and tool descriptions.

### Key Differences from Other Frameworks

- Code-first: workflows are expressed as regular Python, not declarative graphs.
- Tracing enabled by default — every run is logged for debugging and evaluation.
- Provider-agnostic: the SDK has documented paths for non-OpenAI models.
- Guardrails are first-class, not bolt-ons.

---

## 4. Multi-Agent Coordination Patterns

### Pattern Taxonomy

**Sequential / Pipeline**
Agents process output from the previous agent in a fixed order. Predictable, easy to debug, suitable for well-defined transformation chains. Example: Planner → Researcher → Coder → Reviewer.

**Orchestrator-Worker**
A central orchestrator agent dynamically assigns tasks to specialist worker agents and synthesizes results. The orchestrator retains global state; workers are stateless. Works well when the set of subtasks isn't known in advance.

**Hierarchical**
Agents organized in layers: strategic agents at the top, domain coordinators in the middle, specialist executors at the edges. Mirrors organizational design. Scales without forcing any single agent to own everything.

**Supervisor-Worker (with error suppression)**
Research from Google DeepMind validates: a centralized control plane suppresses the 17x error amplification that "bag of agents" networks produce. The supervisor acts as a single coordination point, preventing conflicting decisions.

**Maker-Checker (Review Loop)**
One agent produces output (maker); another evaluates it against criteria and either approves or returns it with specific feedback (checker). The feedback loop is the reliability mechanism — not single-pass generation.

**Decentralized (Peer-to-Peer)**
Agents hand off to each other without a central coordinator. Maximizes resilience and parallelism. Less efficient in large groups; coordination overhead grows.

### Hierarchy Design Principles

- **Strategy at the top, execution at the edges.** High-level agents make decisions; low-level agents take actions. Do not mix.
- **Saturation threshold at ~4 agents.** The March 2025 MAST study found coordination gains plateau beyond 4 agents. Below this count, adding structure helps. Above it, overhead consumes the benefit.
- **Limit group chat orchestration to 3 or fewer agents.** Managing conversation flow and preventing infinite loops becomes difficult with more participants.
- **Decomposition-first planning.** Explicit upfront decomposition before execution reduces delegation ambiguity. MIT research (2025) found that allocating tasks by skill descriptions and planning the full workflow upfront outperforms reactive delegation for structured workflows.

### Delegation Best Practices

- Give the orchestrator narrow tool permissions (mostly read and route). Do not give the coordinator agent write access to things it only needs to hand off.
- Pass bounded, complete task descriptions to subagents. The only channel to a subagent is the task prompt; vague prompts produce vague results.
- Surface dependencies explicitly. Decomposed tasks should include which prior outputs they depend on.
- Include success criteria in every delegated task. Agents without clear acceptance criteria produce inconsistent outputs.

### Failure Modes to Design Against

The 2025 MAST study (1,642 execution traces, 7 frameworks) found failure rates between 41% and 86.7%. The largest category of failure was coordination breakdowns at 36.9% of all failures. Known failure modes:

- **Circular dependencies**: Task A waits for B; B waits for A. Detect with dependency graph validation before execution.
- **Duplicate assignments**: Multiple agents receive the same subtask. Use a task registry or coordinator that tracks assignments.
- **Resource contention**: Multiple agents modify shared state concurrently. Either serialize writes or use optimistic locking with conflict detection.
- **Prompt injection via inter-agent messages**: OWASP LLM01:2025 identifies this as the primary vulnerability. Treat all inter-agent content as untrusted input.
- **Denial of Wallet**: Unbounded loops consuming API budget. Always set `maxTurns` or equivalent hard stops.

### Hybrid Approaches

Recent practice favors combining hierarchical coordination (for efficiency) with localized peer-to-peer handoffs (for resilience). The orchestrator manages the overall workflow; individual agents can hand off to each other within their domain without routing through the top.

---

## 5. System Prompt Best Practices for Specialized Agents

### Universal Principles

**Role, scope, and boundaries first.** Every specialized agent's system prompt should establish:
1. Who this agent is (persona and expertise domain)
2. What it is responsible for (scope)
3. What it will not do (explicit limits)

Without explicit limits, agents drift into adjacent behaviors and produce inconsistent results.

**Instruction hierarchy.** When instructions may conflict, make precedence explicit: system prompt > developer instructions > user input > retrieved content. Agents that lack this hierarchy produce unpredictable behavior when instructions conflict.

**Treat the prompt as code.** Version it, review it, test it against known inputs. Prompts change behavior as reliably as code changes; they deserve the same governance.

**Short sentences, active voice.** Complex nested clauses increase misinterpretation. "Analyze error messages and identify the root cause" outperforms "In order to assist the user with debugging, you should attempt to, where possible, analyze any provided error messages."

### Planner Agent

The planner translates high-level goals into structured, bounded subtasks that downstream agents can execute without ambiguity.

Key prompt elements:
- Explicitly instruct the agent to gather context before planning, not during execution.
- Require output in a structured format (e.g., numbered task list with dependencies noted).
- Require the planner to state assumptions and open questions, not paper over them.
- Distinguish between "planning mode" (information gathering, no writes) and "execution mode" (taking action). In planning mode, the agent should refuse to modify state.

Example prompt structure:
```
You are a software project planner. Your role is to decompose requirements into concrete,
bounded tasks for specialist agents.

Before producing a plan:
- Read all relevant files to understand current state
- Identify ambiguities and list them explicitly
- State your assumptions

Output format:
1. [Task description] | depends_on: [task numbers or "none"] | success_criteria: [verifiable condition]

You do not write code or modify files. You only produce plans.
```

### Coder / Implementer Agent

Key prompt elements:
- Frame the agent as a senior engineer with specific language/domain expertise.
- Require thinking holistically before writing: read related files, understand dependencies, anticipate side effects.
- Require tests or verification steps as part of output, not optional additions.
- Specify coding standards (language, formatting, error handling conventions) directly in the prompt — do not assume inherited context.
- Separate planning from writing: "First describe your approach, then implement it."

Example prompt structure:
```
You are a senior OCaml engineer. Before writing any code:
1. Read all files referenced in the task
2. Identify downstream effects of your changes
3. Describe your implementation approach

When implementing:
- Follow the existing module structure and naming conventions
- Add error handling at I/O boundaries; use option/result for expected failures
- Write or update tests for non-trivial changes

Do not make changes outside the scope of the task.
```

### Reviewer / Auditor Agent

Reviewers must have read-only tool access. If a reviewer can write, it will write, and review mode degrades.

Key prompt elements:
- Define the specific review criteria (security, performance, readability, test coverage, etc.) — reviewers without criteria produce generic output.
- Require structured output: Critical / Warning / Suggestion, each with specific code reference.
- Require actionable feedback: "This is wrong" is not feedback. "Replace the mutable ref with an immutable binding because..." is feedback.
- Instruct the agent to show current code and proposed fix side by side.

Example prompt structure:
```
You are a senior code reviewer. You analyze code only — you never modify files.

When reviewing:
1. Run git diff to see recent changes
2. For each issue found, note: location, severity (critical/warning/suggestion), explanation, and recommended fix

Severity definitions:
- Critical: security vulnerability, data loss risk, or broken correctness
- Warning: likely bug, poor error handling, or maintainability debt
- Suggestion: readability, performance, or style improvement

Always show the current code alongside your recommended change.
```

### Debugger Agent

Key prompt elements:
- Require a root cause hypothesis before attempting a fix. Agents that jump to fixes without diagnosis create new bugs.
- Require reproduction steps to be identified before any code changes.
- Require verification after fix (run tests, check the specific case that failed).
- Distinguish between fixing the symptom and fixing the cause — explicitly instruct to fix the cause.

### Orchestrator / Coordinator Agent

Key prompt elements:
- Keep scope narrow: plan, delegate, synthesize. The orchestrator should not implement.
- Include explicit delegation rules: which agent handles which types of work.
- Require the orchestrator to track task status and detect failures before proceeding.
- Set escalation conditions: when to ask the user rather than proceeding autonomously.

### Role-Specific Prompt Summary

| Role | Core prompt focus | Tool access |
|---|---|---|
| Planner | Decompose tasks, gather context, structure dependencies | Read-only |
| Implementer | Understand context, write to spec, verify | Read + Write + Bash |
| Reviewer | Identify specific issues with cited evidence | Read-only |
| Debugger | Root cause first, minimal fix, verify | Read + Write + Bash |
| Orchestrator | Delegate, track, synthesize | Read + delegate (Agent tool) |
| Research | Find information, cite sources, summarize | Read + Web |

---

## 6. Tool Restriction Patterns

### Allowlist vs. Denylist

**Allowlist** (preferred): Explicitly enumerate what is permitted. Everything not listed is blocked by default. This is the correct default for security-sensitive work.

**Denylist**: Explicitly enumerate what is blocked. Everything else is permitted. Appropriate only when the set of dangerous operations is small and well-understood, and the set of useful operations is large and unpredictable.

Allowlists are more secure because they default to denying access. Denylists require anticipating every possible threat — an inherently incomplete exercise.

In Claude Code, the `tools` frontmatter field implements an allowlist; `disallowedTools` implements a denylist. Use `tools` for new agent definitions unless you have a specific reason to prefer a denylist.

### Principle of Least Privilege

Each agent should have exactly the tools it needs to complete its approved task — no more. This is both a security principle and a quality principle: fewer tools reduces the attack surface and produces better agent behavior (models behave more reliably when they have fewer irrelevant options).

A customer service agent does not need database deletion capability. A research assistant does not need permission to send email. Every unnecessary tool is unnecessary risk and unnecessary noise.

**Practical tool tiers:**

| Tier | Tools | Appropriate for |
|---|---|---|
| Read-only analysis | `Read`, `Grep`, `Glob` | Reviewers, auditors, planners |
| Research | `Read`, `Grep`, `Glob`, `WebSearch`, `WebFetch` | Research agents |
| Documentation writer | `Read`, `Grep`, `Glob`, `Write` | Doc generators (no source code modification) |
| Full read/write | `Read`, `Edit`, `Write`, `Grep`, `Glob` | Implementers (no shell) |
| Executor | `Read`, `Edit`, `Write`, `Grep`, `Glob`, `Bash` | Full implementation + testing |
| Coordinator | `Read`, `Agent` | Orchestrators (delegates, doesn't implement) |

### Action Classification

A three-tier classification framework:

1. **Auto-approve**: Read operations, information retrieval. No side effects; approve automatically.
2. **Log and proceed**: Write operations. Record for audit; approve automatically but with traceability.
3. **Human confirmation required**: Destructive or irreversible actions (deletion, external API calls that commit resources, credential access). Require explicit approval before execution.

### Hooks for Fine-Grained Control

When you need to allow a tool but restrict specific operations within it, use `PreToolUse` hooks rather than removing the tool entirely. Example: allow `Bash` but validate every command before execution to block write SQL operations:

```yaml
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-command.sh"
```

The hook receives the tool input as JSON via stdin. Exit code 2 blocks the operation and returns the stderr message to the agent.

### Scoped Credentials

Beyond tool access, agents should operate with scoped credentials:
- Read-only database credentials for agents that only query
- Scoped API keys that grant only required permissions
- Egress allowlists restricting which external services the agent can call
- Time-bounded credentials for operations that should not persist

### Gateway Pattern

For production systems with many agents, a centralized gateway that validates every tool call before execution provides defense-in-depth. Every request is authorized using policy-as-code (e.g., Open Policy Agent) and executed in short-lived isolated environments. Agents never access infrastructure APIs directly.

### Security Failure Modes

- **Prompt injection via tool outputs**: An agent reads a file containing instructions that manipulate its behavior. Treat all content retrieved via tools as untrusted data, not trusted instructions.
- **Privilege escalation via over-permissioned tools**: An agent with write access to a database will eventually use it. Give write access only to agents that must write.
- **Denial of Wallet**: Unbounded tool call loops can exhaust API budgets. Always set hard limits (`maxTurns`, iteration caps) on any agent that calls tools in a loop.
- **Cross-agent injection**: Inter-agent messages can carry injected instructions. Validate structured inputs from other agents the same way you validate user input.

### OWASP Summary (LLM Applications, 2025)

Do:
- Apply least privilege to all agent tools and permissions
- Validate and sanitize all external inputs (including content from tools)
- Implement human-in-the-loop for high-risk or irreversible actions
- Use allowlists per agent; reject any tool call not on the list

Do not:
- Give agents unrestricted tool access or wildcard permissions
- Trust content from external sources (web pages, files, other agents) as instructions
- Allow agents to execute arbitrary code without sandboxing

---

## Key Cross-Cutting Findings

**Simplicity is a feature.** Across all frameworks and research, the consistent finding is that simpler agent designs outperform complex ones in practice. Add coordination layers only when single-agent approaches demonstrably fail. The MAST study found failure rates of 41–87% across frameworks; most failures were coordination failures, not capability failures.

**Description/goal quality determines routing quality.** In CrewAI, the `goal` determines decision-making. In Claude Code subagents, the `description` determines when Claude delegates. In the OpenAI SDK, `instructions` determine behavior. In all cases, the quality of this natural-language signal is the primary driver of correct agent behavior. Treat it with the same rigor as code.

**Tool documentation is as important as tool access.** Multiple sources emphasize that tool descriptions and parameter documentation must be treated with the same rigor as the system prompt itself. A well-described tool is used correctly; a poorly described tool is misused even by capable models.

**Role specialization improves reliability.** Agents with a single well-defined role outperform generalist agents on domain-specific tasks. The discipline of defining what an agent does not do is as important as defining what it does.

**Model selection is a design decision.** Routing expensive model capacity to tasks that require it, while using fast/cheap models for classification, validation, and routine work, is both a cost optimization and a quality optimization. Guardrails in particular should almost always use a cheaper model than the task agent.
