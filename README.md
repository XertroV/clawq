# clawq

Coq-first port scaffold of nullclaw with an OCaml runtime path via Coq extraction.

## Current State
- Project skeleton is in place for:
  - Coq theory modules (`coq/theories/Clawq/*`)
  - OCaml runtime wrapper (`src/*`)
  - Extraction target (`src/extracted/clawq_core.ml`)
- Detailed implementation/handoff plans:
  - `PLAN.md`
  - `HANDOFF_PLAN.md`

## Quick Start

### Prerequisites

Install the following via your system package manager:

- **opam** (OCaml package manager)
- **OCaml 5.1+** (installed automatically by bootstrap)
- **Coq 8.19+** (installed automatically by bootstrap)
- **libsqlite3-dev** (or equivalent for your distro)

### Bootstrap, Build, Run

```bash
# 1. Create opam switch "clawq-5.1" and install all dependencies
make bootstrap

# 2. Build (all make targets auto-activate the opam switch)
make build

# 3. Run
make run                        # help output
make phase2                     # show deferred phase-2 items

# 4. Test
make test
```

To use `dune` directly (outside of `make`), activate the switch first:

```bash
eval "$(opam env --switch=clawq-5.1)"
dune exec clawq -- help
```

### Extraction Workflow

```bash
# Regenerate src/extracted/ from Coq theories (requires Coq)
make extract

# Check whether extracted code has drifted from Coq sources
make extract-check
```

## Notes
- The generated extraction file path is `src/extracted/clawq_core.ml`.
- `nullclaw/` is included as reference source and should not be modified during porting.
