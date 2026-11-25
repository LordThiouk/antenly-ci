#!/usr/bin/env bash
# Liste blanche unique des dépôts Galass acceptés comme target_repo ou extra_repos.
# Sourcé par extra-repos.sh, livelog.sh, wippush.sh et les étapes du workflow
# (validation, push, PR). Ne pas recopier la liste ailleurs : le test
# allowed-repos-test.sh vérifie que les options: de workflow_dispatch
# correspondent à allowed_repos_list, et qu'aucune copie en dur ne reste.
# Ce fichier ne fait que définir des fonctions : il est sûr à sourcer.

# Noms exacts, sans espaces, ordre stable (identique aux options: du workflow).
ALLOWED_REPOS='Galass_Driver Galass_Rider Galass_backend galass-emu-actions-pub'

allowed_repos_list() {
  local r
  # shellcheck disable=SC2086
  for r in $ALLOWED_REPOS; do
    printf '%s\n' "$r"
  done
}

allowed_repo() {
  local r
  # shellcheck disable=SC2086
  for r in $ALLOWED_REPOS; do
    [ "$1" = "$r" ] && return 0
  done
  return 1
}
