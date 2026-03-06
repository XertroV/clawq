# SSE Event Protocol Reference

Server-sent events on `POST /chat/stream`.

## Request

```json
{
  "session_id": "web-abc123",
  "message": "hello"
}
```

Headers: `Authorization: Bearer <token>` (required if pairing enabled).

## Response

`Content-Type: text/event-stream`

Each event:
```
data: <JSON>\n\n
```

Terminal event: `data: [DONE]\n\n`

## Event Types

### `delta`
LLM text output chunk.
```json
{"type": "delta", "content": "Hello, "}
```

### `thinking_delta`
LLM reasoning/thinking chunk (Anthropic extended thinking or OAI-compatible reasoning).
```json
{"type": "thinking_delta", "content": "The user wants a greeting..."}
```
May arrive before or interleaved with `delta` events depending on provider.
UI must buffer separately and render in a collapsible thinking block.

### `tool_call_delta`
Raw tool call streaming (LLM building up tool call arguments incrementally).
Used for debugging / low-level visibility. UI may ignore these in favor of `tool_start`.
```json
{"type": "tool_call_delta", "index": 0, "id": "call_abc", "function_name": "bash", "arguments": "{\"cmd\""}
```

### `tool_start`
Tool call about to execute. Emitted immediately before execution begins.
`arguments` is the complete JSON string of tool arguments.
```json
{"type": "tool_start", "id": "call_abc", "name": "bash", "arguments": "{\"cmd\": \"ls -la\"}"}
```

### `tool_output_delta`
Streaming stdout chunk from a shell/subprocess tool. May contain ANSI escape codes.
Only emitted by tools that support streaming output (e.g., `bash`, `run_command`).
```json
{"type": "tool_output_delta", "id": "call_abc", "chunk": "\u001b[32mfile.txt\u001b[0m\n"}
```

### `tool_result`
Tool execution complete. `result` is the final output (full, not a diff from streaming chunks).
`is_error: true` when the tool returned an error.
```json
{"type": "tool_result", "id": "call_abc", "name": "bash", "result": "file.txt\n", "is_error": false}
```

### `error`
Unrecoverable server-side error. Stream will terminate after this.
```json
{"type": "error", "message": "provider timeout"}
```

### `done`
Normal stream termination (after all tool calls complete and final text is emitted).
```json
{"type": "done"}
```

## Event Ordering

A complete turn with one tool call looks like:

```
data: {"type":"thinking_delta","content":"I should list files..."}
data: {"type":"thinking_delta","content":" to find what they need."}
data: {"type":"tool_start","id":"call_1","name":"bash","arguments":"{\"cmd\":\"ls\"}"}
data: {"type":"tool_output_delta","id":"call_1","chunk":"file.txt\n"}
data: {"type":"tool_output_delta","id":"call_1","chunk":"other.txt\n"}
data: {"type":"tool_result","id":"call_1","name":"bash","result":"file.txt\nother.txt\n","is_error":false}
data: {"type":"delta","content":"I found two files: "}
data: {"type":"delta","content":"file.txt and other.txt."}
data: {"type":"done"}
data: [DONE]
```

Multiple tool calls may be interleaved if the agent runs them (currently sequential).

## `/commands` Endpoint

`GET /commands` — no auth required.

Response:
```json
[
  {"name": "new", "description": "Start a new conversation"},
  {"name": "help", "description": "Show available commands"},
  {"name": "status", "description": "Show bot status"},
  {"name": "pair", "description": "Pair with TOTP code: /pair <6-digit-code>"}
]
```

## `/ui-version` Endpoint

`GET /ui-version` — no auth required.

Response:
```json
{"version": "sha256:abcdef1234567890"}
```

Version is a content hash of the bundled JS + CSS, baked into `Chat_ui_assets.ui_version` at build time.
