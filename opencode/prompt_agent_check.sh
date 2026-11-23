#!/usr/bin/env bash
# Garde-fou avant lancement (lecture seule) : en mode non chaîné (chain_enabled=false), le step
# « Statut final » exige un PASS réel de CHAQUE agent de done_agents (done_check.sh, raison
# a:none:<Agent> sinon) — mais rien n'oblige le prompt effectif du lien à dispatcher cet agent.
# Constat (22 nov. 2026, 3 runs : annotation-build-solo, annotation-build-solo2,
# annotation-cloture-build) : un prompt de phase build (jamais verify ni close) tourne ~30-55 min
# en solo avec done_agents=Max, et échoue chaque fois sur a:none:Max — l'agent n'a jamais eu
# l'instruction de dispatcher Max, Max appartient à la phase close du pipeline (OPERATIONAL_RULES
# § Model selection : Build → Verify → Max → Close). Ce n'est pas un bug de done_check (la porte
# juge juste : aucune tâche Max n'a jamais existé) ni de la garde ISATool : c'est un lien condamné
# avant même de démarrer opencode, nommé ici au lieu d'être découvert après le plafond.
# Ne décide PAS à la place de done_check : ne lit aucun stockage opencode, ne lève jamais le
# raison-code a:none, n'autorise ni n'interdit un verdict — seul un nom littéral de l'agent absent
# du texte du prompt déclenche le refus, et seulement en mode non chaîné (chain_enabled=true :
# le verdict de ce lien vient de la décision de chaînage, pas de done_check — hors périmètre).
# Usage : prompt_agent_check.sh <chain_enabled:true|false> <done_agents ex. "Max,Silas"> <prompt_file>
# Sortie : rien si ok (exit 0) ; sinon ::error:: nommant chaque agent absent (exit 1).
set -uo pipefail

usage() { echo "usage: prompt_agent_check.sh <chain_enabled> <done_agents> <prompt_file>" >&2; exit 2; }
[ "$#" -eq 3 ] || usage
chain_enabled=$1
agents=$2
prompt_file=$3

case "$chain_enabled" in
  true) exit 0 ;;   # verdict de ce lien = décision de chaînage, pas done_check : hors périmètre.
  false) ;;
  *) echo "::error::prompt_agent_check : chain_enabled invalide (${chain_enabled})" >&2; exit 2 ;;
esac

[ -f "$prompt_file" ] || { echo "::error::prompt_agent_check : prompt introuvable (${prompt_file})" >&2; exit 2; }

IFS=',' read -r -a agent_list <<<"$agents"
missing=()
for ag in "${agent_list[@]}"; do
  [ -n "$ag" ] || continue
  # Nom littéral de l'agent, mot entier (évite qu'« Max » matche un sous-mot) ; sensible à la
  # casse ignorée (les prompts écrivent « Max », jamais une variante) ; recherche dans TOUT le
  # prompt effectif (préambule + corps), pas seulement le fichier source : l'agent peut aussi
  # être imposé par le chaînage en fin de fichier.
  grep -qiE "(^|[^A-Za-z0-9_])${ag}([^A-Za-z0-9_]|\$)" "$prompt_file" || missing+=("$ag")
done

if [ "${#missing[@]}" -gt 0 ]; then
  joined=$(printf '%s,' "${missing[@]}"); joined=${joined%,}
  echo "::error::prompt_agent_check : agent(s) [$joined] exigé(s) par done_agents absent(s) du prompt effectif ; en solo (chain_enabled=false) ce lien échouera à coup sûr sur a:none:${missing[0]} après le plafond (30-55 min). Choisis un prompt qui dispatche cet agent (ex. la phase close pour Max), ou passe en chain_enabled=true." >&2
  exit 1
fi
exit 0
