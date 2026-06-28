# INTERFACE: GitHub App and Room Code Workflows

## Provides

- GitHub App installation/auth module.
- Repo grant resolver and enforcement hooks for GitHub actions.
- PR subscription storage and event dispatcher.
- Triggered room run entrypoints for review/security tasks.
- Backlink/provenance records for room/GitHub relationships.

## Consumes

- P14 effective-access snapshots, repo grants, and credential handles.
- P15 room progress/artifact renderers.
- Existing GitHub webhook/API modules and task/background infrastructure.

## Consumers

- P17 setup wizard validates GitHub App installation and repo grants.
- P18 wraps GitHub credentials/token use under credential/egress policy.

## Constraints

- Existing PAT/webhook setups must continue to work during migration.
- GitHub tokens must be short-lived where possible and redacted in logs/ledger.
