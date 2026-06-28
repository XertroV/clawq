# PLAN: GitHub App and Room Code Workflows

## P16.M1 GitHub App Identity and Repo Grants

### P16.M1.E1 GitHub App Auth Foundation

- T001 Add GitHub App config and installation schema.
  Acceptance: config supports app id, installation id mapping, private-key
  reference, webhook secret, and migration coexistence with PAT config.
- T002 Implement GitHub App token exchange.
  Acceptance: installation tokens are minted, cached briefly, redacted, scoped
  to installation/repo, and tested against mocked GitHub responses.
- T003 Route GitHub API auth through app/PAT abstraction.
  Acceptance: existing GitHub API calls continue with PAT while App-backed calls
  use installation tokens and preserve error behavior.

### P16.M1.E2 Repo Grants and Room Authorization

- T001 Add global and per-room repo grant model.
  Acceptance: repo grants attach to access bundles/scopes and support read,
  comment, branch, PR, workflow-read, and workflow-trigger capabilities.
- T002 Enforce repo grants for GitHub-triggered and room-triggered work.
  Acceptance: unauthorized repo actions are denied before API calls or runner
  launch, with redacted explanations.
- T003 Add repo grant introspection and tests.
  Acceptance: `explain-access` includes repo grants; tests cover global grant,
  room override, denial, and legacy PAT compatibility.

## P16.M2 PR Subscriptions and Status Reporting

### P16.M2.E1 Room-Owned PR Subscriptions

- T001 Add PR subscription storage and CLI/channel commands.
  Acceptance: rooms can subscribe/list/disable PR/repo filters with owner,
  creator, room, thread, and policy snapshot metadata.
- T002 Dispatch subscribed GitHub events into room threads.
  Acceptance: PR opened/synchronized/ready/review/comment events post to the
  correct room/thread with dedupe and rate limits.
- T003 Add subscription lifecycle tests.
  Acceptance: disabled, deleted, unauthorized, and moved-room subscriptions do
  not leak updates.

### P16.M2.E2 CI and Review Update Reporting

- T001 Normalize check-suite/workflow-run/review events.
  Acceptance: GitHub webhook parsing produces stable typed summaries for CI,
  review requested/submitted, comments, and mergeability changes.
- T002 Render CI/review updates through room UX.
  Acceptance: Teams and Slack receive concise updates with status, failing job
  links, review state, and action/backlink references.
- T003 Add backoff, dedupe, and quiet-hour policy.
  Acceptance: noisy CI churn is coalesced; policy and budget gates are enforced.

## P16.M3 Triggered Code Runs and Backlinks

### P16.M3.E1 Triggered Review/Security Runs

- T001 Add room-triggered GitHub review run commands.
  Acceptance: room users can request bounded review/security/code tasks against
  granted repos/PRs, producing background tasks with snapshot IDs.
- T002 Wire workflow/security-review triggers.
  Acceptance: triggered runs can start configured workflow/agent jobs and report
  progress/final results back to the room.
- T003 Enforce policy and runner isolation.
  Acceptance: denied repos, missing grants, and unsupported runners fail before
  work starts with actionable messages.

### P16.M3.E2 Backlinks and Provenance

- T001 Add room/GitHub backlink records.
  Acceptance: PR comments, branches, commits, workflow runs, background tasks,
  room threads, and artifacts can reference each other durably.
- T002 Post GitHub comments with room provenance.
  Acceptance: bot-authored comments identify originating room/thread/task where
  appropriate without leaking private room content.
- T003 Add provenance/audit tests.
  Acceptance: ledger/export can trace which room scope caused external GitHub
  actions and which GitHub event caused room messages.
