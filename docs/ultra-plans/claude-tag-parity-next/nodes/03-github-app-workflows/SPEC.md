# SPEC: GitHub App and Room Code Workflows

## Responsibility

Replace PAT-only GitHub room automation with GitHub App/bot semantics and
room-owned repo grants, subscriptions, status reporting, triggered runs, and
backlinks.

## In Scope

- GitHub App installation identity and scoped installation tokens.
- Global and per-room repo grants integrated with P14 access snapshots.
- PR subscription objects and CI/review update reporting into rooms.
- Triggered room runs such as code review/security review with policy checks.
- Backlinks between room threads, tasks, GitHub comments/PRs, workflow runs, and
  generated artifacts.

## Out of Scope

- GitLab/Bitbucket app identities.
- Full marketplace app distribution.
- Replacing all existing PAT paths at once; compatibility is allowed.

## Backlog Target

P16: GitHub App and Room Code Workflows.
