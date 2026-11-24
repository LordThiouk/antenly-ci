#!/usr/bin/env bash
# Garde-fou lifeos_write.
#   opencode/lifeos-guard.sh writes <true|false> <target_repo> [extra_repos]
#   opencode/lifeos-guard.sh destination <true|false> <repo|url> <branche>
#   opencode/lifeos-guard.sh readonly <répertoire>
#
# Règles :
#  - lifeos_write=false : target_repo=lifeos et tout lifeos en extra_repos sont
#    refusés ; aucune destination LordThiouk/lifeos n'est acceptée.
#  - lifeos_write=true  : push sur une branche de fonctionnalité puis PR vers
#    lifeos autorisés (jamais main/master).
#  - Dans tous les cas, main/master/HEAD sont des destinations interdites.
set -euo pipefail

lg_error() { printf '::error::%s\n' "$1" >&2; }

# Normalise une destination (URL https, git@github.com:, owner/repo, .git,
# casse indifférente) en "owner/repo" minuscule.
lg_norm_repo() {
  local s="${1-}"
  s="${s,,}"
  s="${s%.git}"
  s="${s#https://github.com/}"
  s="${s#http://github.com/}"
  s="${s#ssh://git@github.com/}"
  s="${s#ssh://github.com/}"
  s="${s#git@github.com:}"
  s="${s#github.com/}"
  s="${s#/}"
  s="${s%/}"
  printf '%s\n' "$s"
}

lg_is_lifeos() {
  local n
  n=$(lg_norm_repo "${1-}")
  case "$n" in
    lifeos|lordthiouk/lifeos) return 0 ;;
  esac
  return 1
}

lg_forbidden_branch() {
  local b="${1-}"
  [ -n "$b" ] || return 0
  b="${b,,}"
  b="${b#refs/heads/}"
  case "$b" in
    main|master|head|refs/*) return 0 ;;
  esac
  return 1
}

lg_valid_write() {
  case "${1-}" in
    true|false) return 0 ;;
  esac
  return 1
}

lg_extra_tokens() {
  local raw="${1-}" token
  local IFS=$', \t\n'
  # shellcheck disable=SC2086
  for token in $raw; do
    [ -n "$token" ] || continue
    printf '%s\n' "$token"
  done
}

# Vérifie la cohérence lifeos_write / target_repo / extra_repos.
lg_check_writes() {
  local write="${1-}" target="${2-}" extra="${3-}" token
  if ! lg_valid_write "$write"; then
    lg_error "lifeos_write invalide : $write (attendu true ou false)"
    return 1
  fi
  [ -n "$target" ] || { lg_error "target_repo vide"; return 1; }
  [[ "$target" =~ ^[A-Za-z0-9._-]+$ && "$target" != *..* ]] \
    || { lg_error "target_repo invalide : $target"; return 1; }

  if [ "$write" = false ]; then
    if lg_is_lifeos "$target"; then
      lg_error "lifeos_write=false : target_repo=lifeos est interdit (lifeos en lecture seule)"
      return 1
    fi
    while IFS= read -r token; do
      [ -n "$token" ] || continue
      [[ "$token" =~ ^[A-Za-z0-9._-]+$ && "$token" != *..* ]] \
        || { lg_error "extra_repos invalide : $token"; return 1; }
      if lg_is_lifeos "$token"; then
        lg_error "lifeos_write=false : lifeos ne peut pas être dans extra_repos en écriture"
        return 1
      fi
    done < <(lg_extra_tokens "$extra")
  fi
  return 0
}

# Vérifie une destination de push/PR avant toute action.
lg_check_destination() {
  local write="${1-}" repo="${2-}" branch="${3-}"
  if ! lg_valid_write "$write"; then
    lg_error "lifeos_write invalide : $write (attendu true ou false)"
    return 1
  fi
  [ -n "$repo" ] || { lg_error "destination vide"; return 1; }
  [ -n "$branch" ] || { lg_error "branche de destination vide"; return 1; }
  if lg_forbidden_branch "$branch"; then
    lg_error "destination interdite : push/PR sur main/master est toujours refusé ($branch)"
    return 1
  fi
  if [ "$write" = false ] && lg_is_lifeos "$repo"; then
    lg_error "lifeos_write=false : destination LordThiouk/lifeos interdite"
    return 1
  fi
  return 0
}

# Vérifie qu'un clone lifeos est réellement en lecture seule (aucun bit d'écriture).
lg_check_readonly() {
  local dir="${1-}"
  [ -n "$dir" ] || { lg_error "répertoire lifeos vide"; return 1; }
  [ -d "$dir" ] || { lg_error "répertoire lifeos absent : $dir"; return 1; }
  if find "$dir" -xdev -perm /222 -print -quit 2>/dev/null | grep -q .; then
    lg_error "lifeos_write=false : $dir n'est pas en lecture seule"
    return 1
  fi
  return 0
}

usage() {
  cat >&2 <<'USAGE'
usage: lifeos-guard.sh writes <true|false> <target_repo> [extra_repos]
       lifeos-guard.sh destination <true|false> <repo|url> <branche>
       lifeos-guard.sh readonly <repertoire>
USAGE
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    writes)
      [ "$#" -ge 3 ] || { usage; return 2; }
      lg_check_writes "$2" "$3" "${4-}"
      ;;
    destination)
      [ "$#" -eq 4 ] || { usage; return 2; }
      lg_check_destination "$2" "$3" "$4"
      ;;
    readonly)
      [ "$#" -eq 2 ] || { usage; return 2; }
      lg_check_readonly "$2"
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
