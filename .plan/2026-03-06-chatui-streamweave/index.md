# I002: Web UI Chat Interface — Plan

**Plan directory:** `.plan/2026-03-06-chatui-streamweave/`
**Date:** 2026-03-06
**Status:** Planning complete, ready for implementation
**Backlog idea:** I002

---

## Summary

Build a production-quality embedded web chat UI for clawq that supports:
- Real-time SSE streaming of LLM text, thinking blocks, and tool call events
- Shell command stdout streaming with ANSI color rendering
- Slash command autocomplete (fetched from backend)
- Markdown rendering via Marked.js + Highlight.js (CDN)
- Single-binary deployment: assets embedded in OCaml, extracted to disk on first run
- Versioned hybrid serving: auto-update `~/.clawq/ui/` when clawq version changes

Frontend: **Vanilla TypeScript**, bundled with **Bun**, no SPA framework.

---

## Architecture Overview

```
clawq binary
├── Chat_ui_assets (OCaml module)
│   ├── ui_version: string         ← content hash, baked at build time
│   ├── index_html: string
│   ├── chat_js: string
│   └── chat_css: string
│
├── Ui_server (NEW OCaml module)
│   ├── init: extracts assets to ~/.clawq/ui/ if version mismatch
│   ├── serve_asset: disk-first, embedded fallback
│   └── dev_mode: skip overwrite if ~/.clawq/ui/DEV exists
│
└── Http_server (modified)
    ├── GET /              → serve index.html
    ├── GET /chat.js       → serve chat.js
    ├── GET /chat.css      → serve chat.css
    ├── GET /ui-version    → {"version": "..."}
    ├── GET /commands      → [{name, description}, ...]
    ├── POST /chat/stream  → SSE stream (extended events)
    └── POST /pair         → TOTP pairing
```

```
ui/ (TypeScript source, built with Bun)
├── src/
│   ├── main.ts            ← entry point, wires everything
│   ├── stream.ts          ← SSE consumption, event dispatch
│   ├── messages.ts        ← message list rendering
│   ├── thinking.ts        ← thinking block panel
│   ├── tool-panel.ts      ← tool call card (streaming, ANSI)
│   ├── ansi.ts            ← ANSI escape code → HTML converter
│   ├── slash.ts           ← slash command popover + autocomplete
│   └── version.ts         ← version check + reload banner
├── styles/
│   └── chat.css           ← complete styles
└── package.json           ← Bun build config
```

```
scripts/
└── gen_chat_ui_assets.sh  ← reads ui/dist/* → writes src/chat_ui_assets.ml
```

---

## Backend Changes Required

### 1. `Provider.stream_event` — New Variants

Add to `provider.ml`:

```ocaml
type stream_event =
  | Delta of string
  | ThinkingDelta of string              (* NEW: thinking/reasoning chunk *)
  | ToolCallDelta of { ... }             (* existing *)
  | ToolStart of {                       (* NEW *)
      id : string;
      name : string;
      arguments : string;               (* full JSON args, sent when known *)
    }
  | ToolOutputDelta of {                 (* NEW: for streaming shell commands *)
      id : string;
      chunk : string;                   (* raw bytes, may contain ANSI *)
    }
  | ToolResult of {                      (* NEW *)
      id : string;
      name : string;
      result : string;
      is_error : bool;
    }
  | Done
```

All new variants are forwarded through `Http_server` as SSE events:
- `tool_start`: `{"type":"tool_start","id":"...","name":"...","arguments":"..."}`
- `tool_output_delta`: `{"type":"tool_output_delta","id":"...","chunk":"..."}`
- `tool_result`: `{"type":"tool_result","id":"...","name":"...","result":"...","is_error":false}`
- `thinking_delta`: `{"type":"thinking_delta","content":"..."}`

### 2. `Provider_anthropic` — Thinking Block Support

Parse extended thinking from Anthropic SSE stream:
- `content_block_start` with `content_block.type = "thinking"` → track current block as thinking
- `content_block_delta` with `delta.type = "thinking_delta"` → emit `ThinkingDelta delta.thinking`

Anthropic API requires `"thinking": {"type":"enabled","budget_tokens":N}` in request body.
Add `thinking_budget_tokens: int option` to `Runtime_config.provider_config` (default: `None` = disabled).

### 3. `Provider` OpenAI-Compatible — Thinking Support

Two patterns used by reasoning-capable OAI-compatible models:

**Pattern A** (DeepSeek, Qwen, etc.): `choices[0].delta.reasoning_content` field in stream delta.
→ Emit `ThinkingDelta` when this field is present and non-empty.

**Pattern B** (tag-based): Content includes `<think>...</think>` tags within normal `content`.
→ Buffer content, detect opening tag → start emitting `ThinkingDelta`; closing tag → switch back to `Delta`.

Add config option `oai_thinking_style: "none" | "reasoning_content" | "tags"` to provider config.
Default: `"none"` (no special handling).

### 4. `Agent` — Tool Event Emission

In `agent.ml`, `execute_tool_calls` currently runs tools silently. Modify signature:

```ocaml
let execute_tool_calls agent ~db ~audit_enabled ~session_key ~on_chunk calls
```

Before each tool call:
```ocaml
on_chunk (Provider.ToolStart { id = tc.id; name = tc.function_name; arguments = tc.arguments })
```

After each tool call:
```ocaml
on_chunk (Provider.ToolResult { id = tc.id; name = tc.function_name; result; is_error })
```

For shell-executing tools: pass a streaming callback (`on_output_chunk`) down to `tools_builtin.ml`.
Shell stdout chunks emit `ToolOutputDelta` via `on_chunk`.

### 5. `Tools_builtin` — Shell Streaming

Add `?on_output_chunk:(string -> unit Lwt.t) option` parameter to the shell execution path.
When provided: stream stdout line-by-line (or in raw chunks with ANSI preserved).
Accumulate full output for the `ToolResult` at end (for history storage).

### 6. `Http_server` — New Routes

```
GET /                    → serve index.html (text/html)
GET /chat.js             → serve chat.js (application/javascript)
GET /chat.css            → serve chat.css (text/css)
GET /ui-version          → {"version": "<hash>"}
GET /commands            → [{"name":"new","description":"Start new session"}, ...]
```

Slash commands endpoint returns `Slash_commands.commands` as JSON. Extensible: later can merge
with tool_registry's exposed slash commands.

### 7. `Ui_server` — Asset Serving with Versioning

New module. Logic on server startup:

```
ui_dir = ~/.clawq/ui/
dev_marker = ui_dir/DEV

if dev_marker exists:
  → dev mode: serve from ui_dir, never overwrite
elif ui_dir/VERSION == Chat_ui_assets.ui_version:
  → serve from ui_dir (disk cache valid)
else:
  → write all assets + VERSION to ui_dir
  → serve from ui_dir
```

`serve_asset path`: read from `ui_dir`, on ENOENT fall back to embedded string.

Client-side version check:
- Page includes `<meta name="ui-version" content="{{VERSION}}">`
- On connect and on `visibilitychange`, fetch `GET /ui-version`
- If mismatch: show non-intrusive banner "clawq updated — reload to apply"
- Banner has "Reload" button + dismiss option

---

## Frontend Architecture

### SSE Event Dispatch (`stream.ts`)

```typescript
type ServerEvent =
  | { type: "delta"; content: string }
  | { type: "thinking_delta"; content: string }
  | { type: "tool_start"; id: string; name: string; arguments: string }
  | { type: "tool_output_delta"; id: string; chunk: string }
  | { type: "tool_result"; id: string; name: string; result: string; is_error: boolean }
  | { type: "tool_call_delta"; index: number; id?: string; function_name?: string; arguments?: string }
  | { type: "error"; message: string }
  | { type: "done" }
```

AsyncGenerator pattern: `async function* readSSE(resp: Response): AsyncGenerator<ServerEvent>`
With abort signal support for the Stop button.

### Message Model (`messages.ts`)

```typescript
interface Turn {
  id: string
  role: "user" | "assistant"
  text: string                   // accumulated text content
  thinking: string               // accumulated thinking content
  isThinkingStreaming: boolean
  isStreaming: boolean
  tools: ToolPanel[]
}

interface ToolPanel {
  id: string
  name: string
  arguments: string
  output: string                 // ANSI-capable raw string
  result: string
  status: "running" | "done" | "error"
}
```

Rendered DOM structure (no virtual DOM — direct manipulation):

```html
<div class="turn assistant">
  <div class="thinking-block collapsed">   <!-- ThinkingDelta target -->
    <div class="thinking-header">Thinking <span class="toggle">▶</span></div>
    <div class="thinking-body">...</div>
  </div>
  <div class="tool-panel" data-id="...">  <!-- ToolStart creates this -->
    <div class="tool-header">
      <span class="tool-name">bash</span>
      <span class="tool-status running">running</span>
    </div>
    <div class="tool-output ansi">...</div>  <!-- ToolOutputDelta streams here -->
  </div>
  <div class="message-text">...</div>      <!-- Delta streams here -->
</div>
```

### ANSI Renderer (`ansi.ts`)

Minimal subset: handle SGR sequences (colors 30-37, 90-97, 1=bold, 0=reset).
Output: span elements with inline `color:` / `font-weight:` styles.
No external dependency. ~80 lines. Sufficient for shell tool output.

### Slash Command Popover (`slash.ts`)

- On input `keydown`: detect `/` at position 0 or after whitespace → fetch `/commands` (cached)
- Filter commands by text after `/` (case-insensitive prefix match)
- Popover DOM: absolute positioned above input, `z-index: 100`
- Keyboard: `↑`/`↓` to move selection, `Enter`/`Tab` to complete, `Esc` to close
- Click: select and close popover
- On complete: replace typed `/xxx` with `/<command-name> ` (with trailing space)

### Markdown Rendering

- Marked.js from jsDelivr CDN (SRI hash pinned)
- highlight.js from jsDelivr CDN (SRI hash pinned, `github-dark` theme)
- mermaid.js from jsDelivr CDN (SRI hash pinned)
- Configured: `marked.setOptions({ highlight: (code, lang) => hljs.highlight(code, {language: lang}).value })`
- Applied to final (non-streaming) text content after `done` event
- During streaming: plain text (avoid re-parsing on every chunk)
- XSS: `marked` runs with `sanitize: false` + DOMPurify (or set `mangle: false, headerIds: false` + escape HTML manually for user content)

### Mermaid Diagram Rendering

After `done` event, post-process rendered HTML:
- Find all `<code class="language-mermaid">` blocks produced by Marked.js
- For each: call `mermaid.render(uniqueId, diagramSource)` → returns SVG string
- Replace the `<pre><code>` block with the SVG output (wrapped in a `.mermaid-diagram` div)
- Init: `mermaid.initialize({ startOnLoad: false, theme: 'dark' })`
- Error handling: if render fails, leave the raw fenced block visible with an error note
- Mermaid supports: flowcharts, sequence diagrams, class diagrams, ER diagrams, Gantt, etc.

### Version Check (`version.ts`)

- Read `<meta name="ui-version">` on load
- `GET /ui-version` on `visibilitychange` (tab re-focus) + 5min interval
- On mismatch: insert `.version-banner` div at top with "clawq updated" message
- Banner auto-dismisses on reload

---

## Makefile Integration

```makefile
ui:                    ## Build chat UI TypeScript → dist/ → chat_ui_assets.ml
	cd ui && bun install && bun run build
	./scripts/gen_chat_ui_assets.sh

ui-dev:                ## Watch mode for UI development
	cd ui && bun run dev

ui-check:              ## Verify generated assets are up to date
	./scripts/gen_chat_ui_assets.sh --check
```

`gen_chat_ui_assets.sh --check` exits non-zero if committed `chat_ui_assets.ml` doesn't match
current `ui/dist/` output. Add to CI as optional lint gate.

---

## File Map (New + Modified)

| File | Status | Notes |
|------|--------|-------|
| `ui/src/main.ts` | NEW | Entry point |
| `ui/src/stream.ts` | NEW | SSE AsyncGenerator |
| `ui/src/messages.ts` | NEW | Turn/message rendering |
| `ui/src/thinking.ts` | NEW | Thinking block panel |
| `ui/src/tool-panel.ts` | NEW | Tool card DOM |
| `ui/src/ansi.ts` | NEW | ANSI → HTML converter |
| `ui/src/slash.ts` | NEW | Slash command popover |
| `ui/src/version.ts` | NEW | Version check + banner |
| `ui/styles/chat.css` | NEW | Complete stylesheet |
| `ui/package.json` | NEW | Bun config |
| `scripts/gen_chat_ui_assets.sh` | NEW | Asset → OCaml string generator |
| `src/chat_ui_assets.ml` | MODIFIED | Regenerated by script; add `ui_version` |
| `src/ui_server.ml` | NEW | Hybrid serving + versioning |
| `src/provider.ml` | MODIFIED | New stream_event variants |
| `src/provider_anthropic.ml` | MODIFIED | Thinking block parsing |
| `src/provider.ml` (dispatch) | MODIFIED | Forward new events |
| `src/agent.ml` | MODIFIED | ToolStart/ToolResult/ToolOutputDelta emission |
| `src/tools_builtin.ml` | MODIFIED | Shell streaming callback |
| `src/http_server.ml` | MODIFIED | New GET routes, /commands, /ui-version |
| `src/runtime_config.ml` | MODIFIED | `thinking_budget_tokens`, `oai_thinking_style` |
| `src/slash_commands.ml` | MODIFIED | Expose as JSON |
| `src/dune` | MODIFIED | Add ui_server module |
| `Makefile` | MODIFIED | `make ui`, `make ui-dev`, `make ui-check` |
| `test/test_ui_server.ml` | NEW | Versioning logic tests |
| `test/test_provider_thinking.ml` | NEW | ThinkingDelta parsing tests |
| `test/test_ansi.ts` | NEW | ANSI renderer unit tests |

---

## Open Questions / Known Risks

1. **Anthropic extended thinking** requires `budget_tokens` > 0 in request. Config UI / default value TBD.
2. **Shell streaming ANSI**: `tools_builtin.ml` shell execution may batch output. Investigate `Lwt_process` for line-by-line streaming.
3. **Marked.js CDN**: SRI hashes must be pinned to specific versions. Need to document update procedure.
4. **XSS**: Markdown from LLM output must be sanitized. Use `DOMPurify` from CDN or restrict to code/em/strong/ul/ol/li/p/pre/code tags via allowlist.
5. **Session persistence**: Current in-memory sessions lost on clawq restart. Unrelated to I002 but affects UX.
6. **Parallel tool execution**: `execute_tool_calls` uses `Lwt_list.map_p` — tool events from different tools can interleave in the SSE stream. Client must match events by `id` field, not assume sequential ordering.
7. **Multi-provider match exhaustion**: Adding new `stream_event` variants requires updating match statements in ALL provider modules: `provider_anthropic.ml`, `provider.ml` (dispatch), `provider_gemini.ml`, `provider_vertex.ml`, `provider_cohere.ml`, `provider_ollama.ml`. T001 must enumerate all these sites.
8. **config_loader.ml coupling**: Adding `thinking_budget_tokens`/`oai_thinking_style` to `runtime_config.ml provider_config` requires updating the JSON parser in `config_loader.ml` (the provider_config constructor at line ~46). Must be done in T002/T003 or as a prerequisite subtask.
9. **Mermaid.js size**: mermaid.js is large (~2.5MB minified). Load lazily: dynamically import only when a mermaid block is detected post-render. Don't load if no diagrams present.
10. **Marked.js + Mermaid interaction**: Marked.js html-escapes unknown code blocks by default. Must configure a custom `renderer.code` override so `language-mermaid` blocks are preserved as raw text for mermaid.js to consume. Verify this interaction in a standalone test before implementing T007.
11. **SRI hashes**: Implementation must compute and pin SRI hashes for marked.js, highlight.js, DOMPurify at specific version numbers. Document update procedure in index.html. Cannot be done at plan time — do at implementation of P3.M2.E1.T001.
12. **Static asset auth**: `GET /`, `/chat.js`, `/chat.css`, `/ui-version`, `/commands` do NOT require pairing/auth — the HTML/JS is public; auth happens at `/chat/stream` level only.

---

## Supporting Docs

- [backend-events.md](./backend-events.md) — SSE event protocol reference
- [versioning.md](./versioning.md) — Asset versioning + dev mode details
- [thinking-providers.md](./thinking-providers.md) — Per-provider thinking support matrix
