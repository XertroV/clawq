#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OPAM_SWITCH="${OPAM_SWITCH:-$(opam switch show 2>/dev/null || echo clawq-5.1)}"
COQC="opam exec --switch=${OPAM_SWITCH} -- coqc"

if ! opam exec --switch="${OPAM_SWITCH}" -- which coqc >/dev/null 2>&1; then
  echo "coqc is required. Run scripts/bootstrap_coq.sh first."
  exit 1
fi

echo "Compiling Coq theories (switch: ${OPAM_SWITCH})..."
# Core definitions
${COQC} -R coq/theories Clawq coq/theories/Clawq/Interfaces.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/Config.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/Cli.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/PathSafety.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/AuditChain.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/AuditChainConcrete.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/RateLimiter.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/QuoteParsing.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/ShellSafety.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/SecretStore.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/ChannelAuth.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/AuditRetention.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/AgentLoop.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/SessionIsolation.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/LandlockPolicy.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/ToolSafety.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/PairCoding.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/PmodelParsing.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/TaskTree.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/SchedulerCron.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/DiscordGateway.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/SandboxPolicy.v

echo "Compiling Coq proofs..."
${COQC} -R coq/theories Clawq coq/theories/Clawq/ConfigProofs.v
${COQC} -R coq/theories Clawq coq/theories/Clawq/CliProofs.v

if rg -n '^Admitted\.$' coq/theories/Clawq/LandlockPolicy.v >/dev/null; then
  echo "LandlockPolicy.v still contains Admitted proofs."
  rg -n '^Admitted\.$' coq/theories/Clawq/LandlockPolicy.v
  exit 1
fi

echo "Verified: coq/theories/Clawq/LandlockPolicy.v contains no Admitted proofs."

if rg -n '^Admitted\.$' coq/theories/Clawq/PairCoding.v >/dev/null; then
  echo "PairCoding.v still contains Admitted proofs."
  rg -n '^Admitted\.$' coq/theories/Clawq/PairCoding.v
  exit 1
fi

echo "Verified: coq/theories/Clawq/PairCoding.v contains no Admitted proofs."

if rg -n '^Admitted\.$' coq/theories/Clawq/PmodelParsing.v >/dev/null; then
  echo "PmodelParsing.v still contains Admitted proofs."
  rg -n '^Admitted\.$' coq/theories/Clawq/PmodelParsing.v
  exit 1
fi

echo "Verified: coq/theories/Clawq/PmodelParsing.v contains no Admitted proofs."

if rg -n '^Admitted\.$' coq/theories/Clawq/TaskTree.v >/dev/null; then
  echo "TaskTree.v still contains Admitted proofs."
  rg -n '^Admitted\.$' coq/theories/Clawq/TaskTree.v
  exit 1
fi

echo "Verified: coq/theories/Clawq/TaskTree.v contains no Admitted proofs."

if rg -n '^Admitted\.$' coq/theories/Clawq/SchedulerCron.v >/dev/null; then
  echo "SchedulerCron.v still contains Admitted proofs."
  rg -n '^Admitted\.$' coq/theories/Clawq/SchedulerCron.v
  exit 1
fi

echo "Verified: coq/theories/Clawq/SchedulerCron.v contains no Admitted proofs."

if rg -n '^Admitted\.$' coq/theories/Clawq/DiscordGateway.v >/dev/null; then
  echo "DiscordGateway.v still contains Admitted proofs."
  rg -n '^Admitted\.$' coq/theories/Clawq/DiscordGateway.v
  exit 1
fi

echo "Verified: coq/theories/Clawq/DiscordGateway.v contains no Admitted proofs."

if rg -n '^Admitted\.$' coq/theories/Clawq/SandboxPolicy.v >/dev/null; then
  echo "SandboxPolicy.v still contains Admitted proofs."
  rg -n '^Admitted\.$' coq/theories/Clawq/SandboxPolicy.v
  exit 1
fi

echo "Verified: coq/theories/Clawq/SandboxPolicy.v contains no Admitted proofs."
