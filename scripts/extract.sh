#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! command -v coqc >/dev/null 2>&1; then
  echo "coqc is required. Run scripts/bootstrap_coq.sh first."
  exit 1
fi

echo "Compiling Coq theories..."
coqc -R coq/theories Clawq coq/theories/Clawq/Interfaces.v
coqc -R coq/theories Clawq coq/theories/Clawq/Config.v
coqc -R coq/theories Clawq coq/theories/Clawq/Cli.v

echo "Running extraction..."
coqc -R coq/theories Clawq coq/theories/Clawq/Extract.v

if [ ! -f src/extracted/clawq_core.ml ]; then
  echo "ERROR: extraction did not produce src/extracted/clawq_core.ml"
  exit 1
fi

echo "Extraction complete: src/extracted/clawq_core.ml src/extracted/clawq_core.mli"
