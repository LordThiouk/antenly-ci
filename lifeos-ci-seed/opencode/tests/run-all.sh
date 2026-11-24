#!/usr/bin/env bash
# Lance tous les tests de ce dépôt. Code de sortie non nul si un test échoue.
#   bash opencode/tests/run-all.sh
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
failed=0
ran=0
for t in "$here"/*-test.sh; do
  [ -f "$t" ] || continue
  [ "$(basename "$t")" = "run-all.sh" ] && continue
  ran=$((ran + 1))
  echo "==> $(basename "$t")"
  if bash "$t"; then
    echo "<== ok $(basename "$t")"
  else
    echo "::error::test échoué : $t"
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
