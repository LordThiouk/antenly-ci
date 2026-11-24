#!/usr/bin/env bash
# Mapping UNIQUE étape FullRun → agent validateur de l'étape (FullRunPipeline.ts).
# Un job borné à une étape (stop_after_step) doit exiger le PASS de l'agent de CETTE
# étape, jamais de Max par défaut. Utilisé par le workflow pour calculer
# OC_DONE_AGENTS_EFFECTIVE quand l'input done_agents est vide.
#   opencode/step-agents.sh <étape|0-7>   -> nom de l'agent (code 0) ou code 64
# Sourçable : fullrun_step_agent <étape> écrit le nom sur stdout.
# Les étapes et leurs agents sont ceux de FullRunPipeline.ts et ne changent pas :
#   0/scaffold, 1/completeness_pre → Algorithm
#   2/vera                         → Algorithm
#   3/serena                       → Architect
#   4/build                        → Forge
#   5/verify                       → Silas
#   6/max                          → Max
#   7/close                        → Max
set -u

fullrun_step_agent() {
  case "${1,,}" in
    0|scaffold)          printf '%s\n' Algorithm ;;
    1|completeness_pre)  printf '%s\n' Algorithm ;;
    2|vera)              printf '%s\n' Algorithm ;;
    3|serena)            printf '%s\n' Architect ;;
    4|build)             printf '%s\n' Forge ;;
    5|verify)            printf '%s\n' Silas ;;
    6|max)               printf '%s\n' Max ;;
    7|close)             printf '%s\n' Max ;;
    *) return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  [ "$#" -eq 1 ] || { printf 'usage: %s <étape|0-7>\n' "$0" >&2; exit 64; }
  fullrun_step_agent "$1" || { printf 'étape inconnue : %s\n' "$1" >&2; exit 64; }
fi
