#!/usr/bin/env bash
# Tests de la liste blanche target_repo / extra_repos.
#   targets/allowed-repos-test.sh (exécuté via opencode/tests/run-all.sh)
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo_root=$(cd "$here/.." && pwd)
ar="$repo_root/targets/allowed-repos.sh"
[ -x "$ar" ] || { echo "FAIL allowed-repos.sh absent : $ar" >&2; exit 1; }

# shellcheck source=../../targets/allowed-repos.sh
# shellcheck disable=SC1091
. "$ar"

pass=0
ok() { pass=$((pass + 1)); }
bad() { echo "FAIL $1" >&2; exit 1; }

expected='antenly
antenly-ci
galass-ci
Galass_Rider
Galass_Driver
Galass_backend
galass-emu-actions-pub
lifeos
lifeos-ci'
[ "$(allowed_repos_list)" = "$expected" ] || bad "liste blanche inattendue"

while IFS= read -r r; do
  [ -n "$r" ] || continue
  allowed_repo "$r" || bad "dépôt autorisé refusé : $r"
  ok
done < <(allowed_repos_list)

for bad_repo in inconnu autre lifeos-ci2 ../x 'a;b' 'LordThiouk/autre' '' '..' 'antenly '; do
  if allowed_repo "$bad_repo"; then
    bad "dépôt hors liste accepté : [$bad_repo]"
  fi
  ok
done

# validate : target + extra_repos (virgules et espaces).
out=$(bash "$ar" validate antenly "galass-ci Galass_Rider")
printf '%s\n' "$out" | grep -qx 'target=antenly' || bad "validate : target incorrect"
printf '%s\n' "$out" | grep -qx 'extra=galass-ci,Galass_Rider' || bad "validate : extra incorrect"
ok

# check : autorisé / refusé.
bash "$ar" check lifeos >/dev/null || bad "check lifeos refusé"
ok
if bash "$ar" check "LordThiouk/autre" >/dev/null 2>&1; then
  bad "check a accepté LordThiouk/autre"
fi
ok

# Injections dans extra_repos : refus.
for injection in '../x' 'a;b' 'LordThiouk/autre' 'inconnu'; do
  if bash "$ar" validate antenly "$injection" >/dev/null 2>&1; then
    bad "validate a accepté l'injection : $injection"
  fi
  ok
done

# Doublon : refus.
if bash "$ar" validate antenly "galass-ci,galass-ci" >/dev/null 2>&1; then
  bad "validate a accepté un doublon"
fi
ok

# Les options: target_repo des workflows publics restent alignées sur la liste.
for wf in "$repo_root/.github/workflows/task.yml" "$repo_root/.github/workflows/fr-plan-vera.yml"; do
  [ -f "$wf" ] || bad "workflow absent : $wf"
  opts=$(awk '
    /^      target_repo:/ { p=1; next }
    p && /^      [A-Za-z0-9_]+:/ { exit }
    p && /^          - / {
      sub(/^          - /, "")
      print
    }
  ' "$wf")
  [ "$opts" = "$expected" ] || bad "options target_repo de $(basename "$wf") non alignées sur allowed_repos_list"
  ok
done

echo "PASS allowed-repos-test : $pass cas"
