#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OPAM_SWITCH="${OPAM_SWITCH:-$(opam switch show 2>/dev/null || echo clawq-5.1)}"
COQC="opam exec --switch=${OPAM_SWITCH} -- coqc"

# Compile and verify all theories + proofs
./scripts/coq_verify.sh

echo "Running extraction..."
${COQC} -R coq/theories Clawq coq/theories/Clawq/Extract.v

if [ ! -f src/extracted/clawq_core.ml ]; then
  echo "ERROR: extraction did not produce src/extracted/clawq_core.ml"
  exit 1
fi

echo "Extraction complete: src/extracted/clawq_core.ml src/extracted/clawq_core.mli"
