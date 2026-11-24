#!/usr/bin/env bash
# Mapping UNIQUE étape FullRun → agent(s) validateur(s) de l'étape (FullRunPipeline.ts).
# Un job borné à une étape (stop_after_step) doit exiger le PASS de l'agent de CETTE
# étape, jamais de Max par défaut. Utilisé par le workflow pour calculer
# OC_DONE_AGENTS_EFFECTIVE quand l'input done_agents est vide.
#   opencode/step-agents.sh <étape|0-7>         -> agent par défaut (code 0) ou code 64
#   opencode/step-agents.sh --list <étape|0-7>  -> agents autorisés, séparés par des virgules
# Sourçable : fullrun_step_agent <étape> et fullrun_step_agents <étape> écrivent sur stdout.
# Les étapes et leurs agents sont ceux de FullRunPipeline.ts et ne changent pas :
#   0/scaffold, 1/completeness_pre → Algorithm
#   2/vera                         → Algorithm
#   3/serena                       → Architect
#   4/build                        → Designer/Aditi (UI) ou Engineer/Forge/Anvil (logique)
#   5/verify                       → code-reviewer, Forge ou Silas
#   6/max                          → Max
#   7/close                        → Max
# Pas de `set -u` global : le script est sourçable et ne doit pas modifier le shell appelant.

fullrun_step_agent() {
  local step="${1:-}"
  case "${step,,}" in
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

fullrun_step_agents() {
  local step="${1:-}"
  case "${step,,}" in
    0|scaffold)          printf '%s\n' Algorithm ;;
    1|completeness_pre)  printf '%s\n' Algorithm ;;
    2|vera)              printf '%s\n' Algorithm ;;
    3|serena)            printf '%s\n' Architect ;;
    4|build)             printf '%s\n' 'Designer,Aditi,Engineer,Forge,Anvil' ;;
    5|verify)            printf '%s\n' 'code-reviewer,Forge,Silas' ;;
    6|max)               printf '%s\n' Max ;;
    7|close)             printf '%s\n' Max ;;
    *) return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  set -u
  case "${1:-}" in
    --list|--agents)
      [ "$#" -eq 2 ] || { printf 'usage: %s [--list] <étape|0-7>\n' "$0" >&2; exit 64; }
      fullrun_step_agents "$2" || { printf 'étape inconnue : %s\n' "$2" >&2; exit 64; }
      ;;
    *)
      [ "$#" -eq 1 ] || { printf 'usage: %s [--list] <étape|0-7>\n' "$0" >&2; exit 64; }
      fullrun_step_agent "$1" || { printf 'étape inconnue : %s\n' "$1" >&2; exit 64; }
      ;;
  esac
fi
