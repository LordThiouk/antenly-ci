#!/usr/bin/env bash
# Liste blanche unique des dépôts LordThiouk acceptés comme target_repo ou
# extra_repos. Sourcée par les workflows et par les scripts de ce dépôt.
#   targets/allowed-repos.sh list
#   targets/allowed-repos.sh check <dépôt>
#   targets/allowed-repos.sh validate <target_repo> [extra_repos]
# Ne recopie jamais cette liste ailleurs.
set -euo pipefail

# Noms exacts, stables, sans espaces. L'ordre est celui des options: du workflow.
ALLOWED_REPOS='antenly antenly-ci galass-ci Galass_Rider Galass_Driver Galass_backend galass-emu-actions-pub lifeos lifeos-ci'

allowed_repos_list() {
  local r
  # shellcheck disable=SC2086
  for r in $ALLOWED_REPOS; do
    printf '%s\n' "$r"
  done
}

# Nom de dépôt strict : pas de chemin, pas d'injection, pas de "..".
valid_repo_name() {
  local r="${1-}"
  [ -n "$r" ] || return 1
  [[ "$r" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  case "$r" in
    *..*) return 1 ;;
  esac
  return 0
}

allowed_repo() {
  local r="${1-}" a
  valid_repo_name "$r" || return 1
  # shellcheck disable=SC2086
  for a in $ALLOWED_REPOS; do
    [ "$r" = "$a" ] && return 0
  done
  return 1
}

# Normalise extra_repos (virgules et/ou espaces) en liste séparée par des
# virgules, sans doublon. Échoue si un élément est invalide ou hors liste.
normalize_extra_repos() {
  local raw="${1-}" token out=""
  local IFS=$', \t\n'
  # shellcheck disable=SC2086
  for token in $raw; do
    [ -n "$token" ] || continue
    valid_repo_name "$token" || return 1
    allowed_repo "$token" || return 1
    case ",$out," in
      *",$token,"*) return 1 ;;
    esac
    out="${out:+$out,}$token"
  done
  printf '%s\n' "$out"
}

usage() {
  cat >&2 <<'USAGE'
usage: allowed-repos.sh list
       allowed-repos.sh check <depot>
       allowed-repos.sh validate <target_repo> [extra_repos]
USAGE
}

main() {
  local cmd="${1:-}" target extra norm
  case "$cmd" in
    list)
      allowed_repos_list
      ;;
    check)
      [ "$#" -eq 2 ] || { usage; return 2; }
      if ! allowed_repo "$2"; then
        echo "::error::dépôt non autorisé : $2"
        return 1
      fi
      ;;
    validate)
      [ "$#" -ge 2 ] || { usage; return 2; }
      target="$2"
      extra="${3-}"
      if ! allowed_repo "$target"; then
        echo "::error::target_repo non autorisé : $target"
        return 1
      fi
      if ! norm=$(normalize_extra_repos "$extra"); then
        echo "::error::extra_repos invalide (dépôt inconnu, doublon ou caractères interdits)"
        return 1
      fi
      printf 'target=%s\n' "$target"
      printf 'extra=%s\n' "$norm"
      ;;
    *)
      usage
      return 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
