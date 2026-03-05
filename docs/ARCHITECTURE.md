# clawq Architecture

## Build Pipeline

```
coq/theories/Clawq/*.v    Coq source theories
        |
        v
  [coqc + Extraction]     scripts/extract.sh
        |
        v
src/extracted/clawq_core.{ml,mli}  Generated OCaml (tracked in git)
        |
        v
  clawq_extracted library      src/extracted/dune
        |
        v
  clawq_runtime library        src/dune (command_bridge, phase2)
        |
        v
    clawq executable            src/dune (main.ml + cmdliner)
```

## Module Map

### Coq Theories (`coq/theories/Clawq/`)

| File | Role |
|------|------|
| `Interfaces.v` | 7 record-based interface definitions (Provider, Channel, Tool, Memory, RuntimeAdapter, Tunnel, Security) |
| `Config.v` | Configuration records (GatewayConfig, MemoryConfig, SecurityConfig, ClawqConfig) with defaults and validation |
| `Cli.v` | Command ADT, `parse_command`, `dispatch`, and `usage` string |
| `Extract.v` | Extraction directives: type mappings (ExtrOcamlBasic, ExtrOcamlNativeString, ExtrOcamlNatInt) and function list |

### Extracted OCaml (`src/extracted/`)

| File | Role |
|------|------|
| `clawq_core.ml` | Auto-generated OCaml from Coq extraction. Contains command parsing, dispatch, config validation. Tracked in git so the project builds without Coq installed. |
| `clawq_core.mli` | Auto-generated interface file from Coq extraction. Tracked alongside the `.ml`. |

### Runtime (`src/`)

| File | Role |
|------|------|
| `command_bridge.ml` | Bridges CLI arguments to extracted Coq dispatch; handles runtime-only commands (e.g., `phase2`) |
| `phase2.ml` | Lists features deferred to Phase 2 |
| `main.ml` | Entry point; uses Cmdliner for CLI argument parsing |

## Dune Libraries

| Library | Modules | Dependencies |
|---------|---------|-------------|
| `clawq_extracted` | `clawq_core` | (none) — unwrapped, `-w -39` for extraction artifacts |
| `clawq_runtime` | `command_bridge`, `phase2` | `yojson`, `sqlite3`, `clawq_extracted` — unwrapped |
| `clawq` (executable) | `main` | `clawq_runtime`, `cmdliner` |

Both libraries use `(wrapped false)` so modules are accessible directly (e.g., `Clawq_core.dispatch` rather than `Clawq_extracted.Clawq_core.dispatch`). The extracted library also suppresses warning 39 (`-w -39`) since Coq extraction sometimes emits unnecessary `rec` flags.

## Interface Inventory

From `Interfaces.v`, these 7 records define the contract surface for future implementations:

| Interface | Fields | Purpose |
|-----------|--------|---------|
| `Provider` | name, complete, health | LLM provider abstraction |
| `Channel` | name, start, stop, send | Communication channel (web, telegram, etc.) |
| `Tool` | name, invoke, risk_level | Agent tool with risk classification |
| `Memory` | store, recall, forget | Key-value memory backend |
| `RuntimeAdapter` | name, start, stop | Runtime lifecycle management |
| `Tunnel` | name, start, status | Network tunnel (e.g., Cloudflare) |
| `Security` | workspace_only, audit_enabled, encrypt_secrets | Security policy flags |

## Dependency Direction

```
Interfaces.v  (no deps)
     |
     v
  Config.v    (depends on String, List, Bool)
     |
     v
   Cli.v      (depends on String, List)
     |
     v
 Extract.v    (depends on Cli, Config, ExtrOcaml*)
```

OCaml side:
```
clawq_extracted  -->  clawq_runtime  -->  clawq (executable)
   (no deps)        (yojson, sqlite3)     (cmdliner)
```

## Build Commands

| Command | What It Does |
|---------|-------------|
| `make bootstrap` | Create opam switch, install all dependencies |
| `make build` | `dune build` |
| `make extract` | Run Coq extraction via `scripts/extract.sh` |
| `make extract-check` | Verify extracted code matches what extraction produces |
| `make test` | `dune runtest` |
| `make run` | `dune exec clawq -- help` |
| `make phase2` | `dune exec clawq -- phase2` |
| `make fmt` | `dune fmt` |
| `make fmt-check` | Check formatting without modifying files |
| `make clean` | `dune clean` |
