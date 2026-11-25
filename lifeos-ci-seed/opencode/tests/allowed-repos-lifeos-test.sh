#!/usr/bin/env bash
# Cas propres à la liste étendue de lifeos-ci (absents de la version galass-ci).
# Chaque dépôt ci-dessous est réellement ciblable par un run lifeos-ci :
#   - antenly, antenly-ci : dépôts actifs du propriétaire (cible historique) ;
#   - galass-ci et les dépôts Galass : reprises de galass-ci ;
#   - lifeos, lifeos-ci : dépôt de référence et dépôt qui porte ces workflows.
# La version d'origine (allowed-repos-test.sh) ne teste que le cœur galass-ci et
# ne peut pas couvrir ces noms : ils y étaient même listés comme refusés.
#   opencode/tests/allowed-repos-lifeos-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
# shellcheck source=targets/allowed-repos.sh
. "$here/../targets/allowed-repos.sh"
set +e -u -o pipefail

allowed="$here/../targets/allowed-repos.sh"
task_wf="$here/../.github/workflows/task.yml"
vera_wf="$here/../.github/workflows/fr-plan-vera.yml"
[ -f "$allowed" ] || ko "allowed-repos.sh introuvable : $allowed"
for wf in "$task_wf" "$vera_wf"; do
  [ -f "$wf" ] || ko "workflow introuvable : $wf"
done

# --- 1. Les dépôts de la liste étendue sont acceptés ------------------------
extended='antenly antenly-ci galass-ci Galass_Rider Galass_Driver Galass_backend galass-emu-actions-pub lifeos lifeos-ci'
n=0
for r in $extended; do
  allowed_repo "$r" || ko "dépôt étendu refusé : $r"
  allowed_repos_list | grep -qxF -- "$r" || ko "dépôt étendu absent de allowed_repos_list : $r"
  n=$((n + 1))
done
[ "$n" -eq 9 ] || ko "liste étendue incomplète ($n/9)"
ok "allowed_repo : les 9 dépôts de la liste étendue sont acceptés"

# --- 2. validate / normalize_extra_repos : cas lifeos -----------------------
out=$(bash "$allowed" validate lifeos 'antenly-ci,galass-ci') \
  || ko "validate lifeos + extra refusé"
printf '%s\n' "$out" | grep -qxF 'target=lifeos' || ko "validate : target lifeos absent"
printf '%s\n' "$out" | grep -qxF 'extra=antenly-ci,galass-ci' \
  || ko "validate : extra inattendu ($out)"
ok "validate : target lifeos + extra antenly-ci,galass-ci"

norm=$(normalize_extra_repos 'lifeos   antenly-ci,lifeos-ci') \
  || ko "normalize_extra_repos a refusé des dépôts étendus"
[ "$norm" = 'lifeos,antenly-ci,lifeos-ci' ] || ko "normalize inattendu : [$norm]"
ok "normalize_extra_repos : espaces/virgules normalisés"

if normalize_extra_repos 'lifeos,lifeos' >/dev/null 2>&1; then
  ko "doublon lifeos accepté"
fi
if bash "$allowed" validate antenly 'Lifeos' >/dev/null 2>&1; then
  ko "casse incorrecte (Lifeos) acceptée"
fi
if bash "$allowed" check 'lifeos/x' >/dev/null 2>&1; then
  ko "chemin injecté (lifeos/x) accepté"
fi
ok "validate : doublon, casse et chemin refusés"

# --- 3. Les deux workflows publics exposent exactement la liste -------------
for wf in "$task_wf" "$vera_wf"; do
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
  [ "$opts" = "$list" ] || ko "options: target_repo de $(basename "$wf") != allowed_repos_list"
done
ok "options: target_repo de task.yml et fr-plan-vera.yml alignées"

# --- 4. La liste étendue n'est recopiée (jointure |) nulle part ailleurs -----
# Les options: des workflows reprennent les noms un par ligne (vérifié ci-dessus) ;
# une copie de la liste complète jointe par des « | » signalerait une duplication
# dangereuse qui divergerait à la première évolution de la liste blanche.
pattern=$(allowed_repos_list | paste -sd'|' - | sed 's/|/\\|/g')
copies=$(grep -R -n -E "$pattern" \
  --include='*.sh' --include='*.yml' --include='*.yaml' \
  "$here" "$here/../.github" "$here/../targets" || true)
leftover=$(printf '%s\n' "$copies" | grep -v '/targets/allowed-repos.sh:' | grep -v '^$' || true)
[ -z "$leftover" ] || ko "liste étendue recopiée hors allowed-repos.sh :
$leftover"
ok "aucune copie de la liste étendue hors allowed-repos.sh"
