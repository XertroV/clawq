---
name: idea
description: Log a planning idea to the backlog. Use when the user has a feature idea, enhancement suggestion, or brainstorm they want tracked.
argument-hint: <idea description>
---

# idea

File `$ARGUMENTS` as a backlog idea using `bl idea`.

## Setup

Get the live CLI interface:
!`bl idea --help`

## Instructions

1. Interpret the idea description in `$ARGUMENTS`.
2. Craft a concise, searchable title (reword if the raw input is vague or verbose).
3. Quick duplicate check: `bl list --search "keywords"` — if an existing idea clearly covers it, mention it and stop. Keep this brief (one search, move on).
4. Choose the right invocation:
   - **Simple ideas** (clear one-liner): `bl idea --simple "Title here"`
   - **Detailed ideas** (enough context for a body): `bl idea --title "Title" --body "Description"`
5. Add `--priority`, `--complexity`, or `--estimate` only when clearly inferable from the description.
6. Report the created idea ID and title.

## Constraints

- Use `--simple` for straightforward ideas; only expand `--body` when the description warrants it.
- Keep duplicate searching to one quick search — move on promptly.
- Use only flags from the live `--help` output above.
- Only ask follow-up if the description is truly unintelligible.
