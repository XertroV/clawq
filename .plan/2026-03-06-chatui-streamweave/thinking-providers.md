# Thinking / Reasoning — Per-Provider Support Matrix

## Overview

"Thinking" = the model's internal reasoning before its final response.
Clawq surfaces this as `ThinkingDelta` stream events → collapsible UI panel.

## Provider Matrix

| Provider | Thinking Support | Protocol | Config Key | Notes |
|----------|-----------------|----------|------------|-------|
| Anthropic (claude-3-7+) | Yes | Separate content block | `thinking_budget_tokens: int` | Must set budget_tokens > 0 in request |
| Anthropic (older) | No | — | — | No thinking blocks |
| DeepSeek | Yes | `reasoning_content` delta field | `oai_thinking_style: "reasoning_content"` | OAI-compatible API |
| Qwen 3+ | Yes | `reasoning_content` delta field | `oai_thinking_style: "reasoning_content"` | OAI-compatible API |
| OpenAI o1/o3/o4-mini | Partial | No streaming access | — | o1 returns `reasoning_tokens` count only; no content |
| Ollama (qwq, etc.) | Yes | `<think>...</think>` tags in content | `oai_thinking_style: "tags"` | Tag-based, within normal content |
| Gemini | Yes | Via Vertex AI; separate field | TBD | Not yet implemented |
| Other OAI-compatible | No | — | `oai_thinking_style: "none"` | Default; no special handling |

## Anthropic Implementation

Request body additions when `thinking_budget_tokens > 0`:
```json
{
  "thinking": {"type": "enabled", "budget_tokens": 10000}
}
```

SSE stream events to parse:
- `content_block_start` → `content_block.type = "thinking"` → begin tracking as thinking block
- `content_block_delta` → `delta.type = "thinking_delta"` → emit `ThinkingDelta delta.thinking`
- `content_block_start` → `content_block.type = "text"` → switch back to normal text tracking

Thinking blocks always precede the text response. Multiple thinking blocks are possible
but rare; concatenate them.

## OAI-Compatible: `reasoning_content` Style

Check in stream delta:
```json
{"choices":[{"delta":{"reasoning_content":"some thought","content":null}}]}
```

When `delta.reasoning_content` is non-null and non-empty → emit `ThinkingDelta`.
When `delta.content` is non-null → emit `Delta` as normal.
Both can arrive in sequence: `reasoning_content` chunks first, then `content` chunks.

## OAI-Compatible: `tags` Style

Buffer incoming `delta.content`. Maintain state machine:
- `Normal` → looking for `<think>`
- `InThinking` → emit `ThinkingDelta`, looking for `</think>`

On `<think>`: switch to InThinking (don't emit the tag itself)
On `</think>`: switch back to Normal (don't emit the tag)
In Normal: emit `Delta`
In InThinking: emit `ThinkingDelta`

Handle split tags across chunks (e.g., `<thi` in one chunk, `nk>` in next).
Use a small lookahead buffer (max tag length = 8 chars for `</think>`).

## Config

In `runtime_config.ml`, per-provider config additions:
```ocaml
type provider_config = {
  ...
  thinking_budget_tokens : int option;       (* Anthropic only; None = disabled *)
  oai_thinking_style : string;               (* "none" | "reasoning_content" | "tags" *)
}
```

Default: `thinking_budget_tokens = None`, `oai_thinking_style = "none"`.

Example config JSON:
```json
{
  "providers": [
    {
      "name": "anthropic",
      "kind": "anthropic",
      "api_key": "...",
      "thinking_budget_tokens": 10000
    },
    {
      "name": "deepseek",
      "kind": "openai",
      "base_url": "https://api.deepseek.com",
      "api_key": "...",
      "oai_thinking_style": "reasoning_content"
    }
  ]
}
```

## UI Rendering

The thinking panel renders `ThinkingDelta` content:

```html
<div class="thinking-block" data-state="streaming">
  <button class="thinking-header">
    <span class="thinking-icon">◌</span>  <!-- pulses while streaming -->
    Thinking
    <span class="thinking-toggle">▶</span>
  </button>
  <div class="thinking-body">
    The user is asking about...
  </div>
</div>
```

States:
- `streaming`: header icon pulses (orange), toggle hidden, body visible
- `done` + `expanded`: full body visible, toggle shows ▼
- `done` + `collapsed`: body hidden (default), toggle shows ▶

Thinking block always collapses automatically when the first `Delta` event arrives
(LLM starts its actual response), so it doesn't dominate the view.

Reasoning text is rendered as plain text (no markdown) — it's often raw internal monologue.
