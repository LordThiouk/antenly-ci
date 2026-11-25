#!/usr/bin/env bash
# Lance tous les tests de ce dépôt. Code de sortie non nul si un test échoue ou si
# un fichier *-test.sh présent n'est pas explicitement listé ci-dessous.
#   bash opencode/tests/run-all.sh
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Liste explicite : la preuve que chaque test du socle est lancé (aucun oubli).
TESTS=(
  allowed-repos-test.sh
  allowed-repos-lifeos-test.sh
  autosave-test.sh
  critical-state-isolation-test.sh
  critical-frozen-tools-test.sh
  critical-git-isolation-test.sh
  internals-test.sh
  lifeos-chain-test.sh
  lifeos-guard-test.sh
  memcap-livelog-test.sh
  memcap-test.sh
  notify-test.sh
  quota-test.sh
  redact-test.sh
  split-diff-test.sh
  subagent-fail-test.sh
  watchdog-test.sh
  upstream-fullrun/agent-idle-test.sh
  upstream-fullrun/allowed-repos-cwd-test.sh
  upstream-fullrun/chain-step-test.sh
  upstream-fullrun/checkpoint-watchdog-verdict-test.sh
  upstream-fullrun/done-check-test.sh
  upstream-fullrun/extra-repos-test.sh
  upstream-fullrun/ffmpeg-install-test.sh
  upstream-fullrun/first-link-prompt-test.sh
  upstream-fullrun/hmac-state-test.sh
  upstream-fullrun/hook-profile-install-test.sh
  upstream-fullrun/leaklog-test.sh
  upstream-fullrun/livelog-test.sh
  upstream-fullrun/merge-signed-carry-test.sh
  upstream-fullrun/oc-deadline-test.sh
  upstream-fullrun/preannot-test.sh
  upstream-fullrun/preflight-test.sh
  upstream-fullrun/prompt-contract-test.sh
  upstream-fullrun/stall-resume-test.sh
  upstream-fullrun/start-step-test.sh
  upstream-fullrun/stop-after-step-test.sh
  upstream-fullrun/stop-step-target-agent-test.sh
  upstream-fullrun/turn-end-test.sh
  upstream-fullrun/unit-contract-test.sh
  upstream-fullrun/wippush-test.sh
  upstream-fullrun/with-emulators-test.sh
)

failed=0
ran=0
for name in "${TESTS[@]}"; do
  t="$here/$name"
  if [ ! -f "$t" ]; then
    echo "::error::test listé mais absent : $t"
    failed=1
    continue
  fi
  ran=$((ran + 1))
  echo "==> $name"
  if bash "$t"; then
    echo "<== ok $name"
  else
    echo "::error::test échoué : $t"
    failed=1
  fi
done

# Complétude : tout fichier *-test.sh présent doit figurer dans TESTS.
for t in "$here"/*-test.sh; do
  [ -f "$t" ] || continue
  base=$(basename "$t")
  found=0
  for name in "${TESTS[@]}"; do
    [ "$name" = "$base" ] && { found=1; break; }
  done
  if [ "$found" -eq 0 ]; then
    echo "::error::test non listé dans run-all.sh : $base"
    failed=1
  fi
done

if [ "$ran" -eq 0 ]; then
  echo "::error::aucun test trouvé dans $here"
  exit 1
fi
if [ "$failed" -ne 0 ]; then
  echo "ECHEC : au moins un test a échoué"
  exit 1
fi
echo "PASS : $ran suite(s) de tests"
