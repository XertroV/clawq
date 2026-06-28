# INTERFACE: Proxy and Verification Boundary

## Provides

- Credential handle abstraction and redaction tests.
- Egress policy model with host/path/method/action fields.
- Callsite inventory for outbound HTTP/git/MCP/tool execution.
- Audit/warn enforcement hooks for representative integration paths.
- Verification follow-up artifact for proof/spec planning.

## Consumes

- P14 access bundles and effective snapshots.
- P16 GitHub App token flow.
- Existing MCP client/server, tool execution, HTTP client, sandbox, and audit
  modules.

## Consumers

- Later full proxy/enforcement phase.
- Formal verification phases P5/P6 or future proof-specific backlog.

## Constraints

- Do not block unrelated P15/P16/P17 work on full proxy completion.
- Denials and audit events must never include secret material.
