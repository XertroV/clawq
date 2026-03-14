# Slash Command Rendering Compatibility

Internal reference for connector-safe slash-command output.

Last reviewed: 2026-03-14.

## Why This Exists

- `/help` previously rendered as a Markdown table.
- That is not portable across connectors.
- Slash-command replies should prefer a shared safe text layout, with connector-specific rich rendering only when the connector has confirmed support.

## Connector Summary

### Teams

Source: https://learn.microsoft.com/en-us/microsoftteams/platform/resources/bot-v3/bots-text-formats

- Text-only bot messages do not support table formatting.
- Markdown/XML support is partial and platform-dependent.
- Lists are not consistently supported on iOS/Android.
- Safe default for slash commands: plain line-oriented text, avoid tables.

### Telegram

Sources:
- https://core.telegram.org/bots/api#formatting-options
- https://core.telegram.org/bots/api#html-style
- https://core.telegram.org/bots/api#markdownv2-style

- Supports a limited HTML/MarkdownV2 formatting set.
- Supported HTML tags include `b`, `i`, `u`, `s`, `code`, `pre`, `a`, `blockquote`, `blockquote expandable`, spoiler tags, and Telegram-specific emoji/time tags.
- Only documented tags are supported; tables are not supported.
- Safe rich mode for slash commands: Telegram HTML.

### Slack

Source: https://docs.slack.dev/messaging/formatting-message-text/

- Top-level message text uses `mrkdwn`.
- Supported text features include bold, italic, strike, quotes, inline code, fenced code blocks, links, and manual list-like text.
- Rich layouts belong in Block Kit, not Markdown tables.
- Safe default for slash commands: plain line-oriented text or simple `mrkdwn` emphasis; do not rely on tables.

### Discord

Source: https://support.discord.com/hc/en-us/articles/210298617-Markdown-Text-101-Chat-Formatting-Bold-Italic-Underline

- Supports common Markdown features such as emphasis, headers, lists, code blocks, and block quotes.
- No documented table support in regular message formatting.
- Safe default for slash commands: plain line-oriented text or simple Markdown; do not rely on tables.

### Web / HTTP / Plain Text

- Treat as plain text unless a caller explicitly renders richer content.
- Safe default for slash commands: plain line-oriented text.

## Repo Policy

- Default slash-command layout should be connector-safe plain text.
- Connector-specific rich renderers are allowed when they are explicitly supported and already wired for that connector.
- Telegram uses dedicated rich HTML rendering. Discord, Slack, and Teams use code blocks for tabular data.
- New slash-command output should be modeled as structured sections/rows first, then rendered per connector.
- Do not introduce Markdown tables for shared slash-command output.

## Practical Rules

- Use aligned lines, short headings, bullet lists, and code formatting sparingly.
- Avoid Markdown tables, HTML outside Telegram, and connector-specific syntax in shared formatters.
- For tabular data: use `Table_format.render` (CLI-style space-padded columns) wrapped in `Format_adapter.code_block` to preserve monospace alignment on connectors. For `Plain`, `code_block` is a no-op.
- If interactive UI is needed, prefer `Rich_message` with a text fallback.
- When adding a new slash command, decide whether it needs:
  - a shared plain renderer only, or
  - a shared plain renderer plus a Telegram HTML variant.

## Current Implementation Direction

- `src/slash_commands.ml` owns slash-command content rendering.
- Connectors select a rendering target instead of formatting replies ad hoc.
- Telegram uses HTML-specific renderers (`<pre>` for tables, `<b>` for headings).
- Discord, Slack, and Teams use `Format_adapter.code_block` (triple-backtick fences) for tabular output like `/costs`, `/usage`, `/model usage`, and `/help`.
- Web/Plain receives raw text (no code block wrapping).
