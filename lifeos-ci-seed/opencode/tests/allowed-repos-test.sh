#!/usr/bin/env bash
# Source unique de la liste blanche target_repo / extra_repos : allowed-repos.sh.
# Vérifie la fonction, l'alignement avec les options: du workflow_dispatch, et
# l'absence de copie en dur dans les scripts et le workflow.
#   opencode/tests/allowed-repos-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
# shellcheck source=opencode/allowed-repos.sh
. "$here/allowed-repos.sh"

wf="$here/../.github/workflows/opencode-fullrun.yml"
[ -f "$wf" ] || ko "workflow introuvable : $wf"
[ -f "$here/allowed-repos.sh" ] || ko "allowed-repos.sh introuvable"

# --- 1. allowed_repo suit allowed_repos_list --------------------------------
n=0
while IFS= read -r r; do
  [ -n "$r" ] || continue
  allowed_repo "$r" || ko "dépôt de la liste refusé : $r"
  n=$((n + 1))
done < <(allowed_repos_list)
[ "$n" -ge 1 ] || ko "allowed_repos_list vide"
for bad in lifeos antenly-ci Galass_backendx main 'Galass_backend;rm' '../x' 'Galass_Driver '; do
  allowed_repo "$bad" && ko "dépôt hors liste accepté : $bad"
done
allowed_repo "" && ko "chaîne vide acceptée"
ok "allowed_repo : liste acceptée, hors liste refusée"

# --- 2. options: de target_repo = allowed_repos_list (même ordre) ------------
opts=$(awk '
  $0 ~ /^      target_repo:/ { p=1; next }
  p && $0 ~ /^      [A-Za-z0-9_]+:/ { exit }
  p && $0 ~ /^[[:space:]]+-[[:space:]]+/ {
    sub(/^[[:space:]]+-[[:space:]]+/, "")
    sub(/[[:space:]]+$/, "")
    print
  }
' "$wf")
list=$(allowed_repos_list)
[ -n "$opts" ] || ko "aucune option target_repo trouvée dans le workflow"
[ "$opts" = "$list" ] || ko "options: target_repo du workflow != allowed_repos_list
workflow:
$opts
liste:
$list"
ok "options: target_repo du workflow alignées sur allowed_repos_list"

# --- 3. Pas de copie en dur du motif case hors allowed-repos.sh --------------
copies=$(grep -R -n -E 'Galass_Driver\|Galass_Rider\|Galass_backend\|galass-emu-actions-pub' \
  --include='*.sh' --include='*.yml' --include='*.yaml' \
  "$here" "$here/../.github" || true)
leftover=$(printf '%s\n' "$copies" | grep -v '/allowed-repos.sh:' | grep -v '^$' || true)
[ -z "$leftover" ] || ko "liste encore recopiée hors allowed-repos.sh :
$leftover"
ok "aucune copie en dur de la liste hors allowed-repos.sh"
