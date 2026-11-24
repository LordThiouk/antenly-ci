#!/usr/bin/env bash
# Quota opencode : validation de models.txt et détection du VRAI quota.
#   opencode/quota.sh list <models.txt>
#   opencode/quota.sh validate <models.txt>
#   opencode/quota.sh next <models.txt> <modèle_courant> [options]
#
# Options de next :
#   --output <fichier>           sortie d'opencode de CETTE tentative
#   --internal-log-dir <dir>     ~/.local/share/opencode/log
#   --since-file <fichier>       ne lire que les journaux plus récents que ce marqueur
#
# Codes de sortie de next :
#   0  aucun quota détecté
#   10 quota détecté, modèle suivant imprimé sur stdout
#   20 quota détecté, plus aucun modèle disponible (statut quota)
#   2  usage invalide
#   3  models.txt invalide
#
# La détection ignore les lignes de diff (^[+-], ^@@), les blocs de code et le
# contenu de fichiers : seul un vrai message d'erreur fournisseur compte.
set -euo pipefail

q_error() { printf '::error::%s\n' "$1" >&2; }

q_trim() {
  local s="${1-}"
  s="${s%$'\r'}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
}

# Imprime les modèles valides, un par ligne. Échoue (3) sur toute ligne invalide.
q_models() {
  local file="${1-}" raw line n=0
  [ -n "$file" ] || { q_error "models.txt non fourni"; return 3; }
  [ -f "$file" ] || { q_error "models.txt introuvable : $file"; return 3; }
  while IFS= read -r raw || [ -n "$raw" ]; do
    line=$(q_trim "$raw")
    [ -n "$line" ] || continue
    case "$line" in
      \#*) continue ;;
    esac
    if ! [[ "$line" =~ ^opencode/[a-z0-9.-]+-free$ ]]; then
      q_error "modèle refusé (seuls les opencode/*-free sont admis) : $line"
      return 3
    fi
    printf '%s\n' "$line"
    n=$((n + 1))
  done < "$file"
  if [ "$n" -eq 0 ]; then
    q_error "models.txt ne contient aucun modèle valide"
    return 3
  fi
  return 0
}

# Une ligne est-elle une VRAIE erreur de quota/limite ?
q_line_is_error() {
  local line="${1-}" low
  low="${line,,}"
  if [[ "$low" =~ free[[:space:]_-]?usage[[:space:]_-]?limit ]] \
    || [[ "$low" =~ (^|[^0-9])429([^0-9]|$) ]] \
    || [[ "$low" == *"too many requests"* ]]; then
    return 0
  fi
  if [[ "$low" =~ (^|[^[:alnum:]_])(error|fatal|ai_apicallerror|apicallerror)([^[:alnum:]_]|$) ]]; then
    if [[ "$low" =~ rate[[:space:]_.-]?limit ]] \
      || [[ "$low" == *"quota"* ]] \
      || [[ "$low" == *"insufficient"* ]] \
      || [[ "$low" == *"exceeded"* ]]; then
      return 0
    fi
  fi
  return 1
}

# Lit un flux et retourne 0 dès qu'une vraie erreur est vue.
# Ignore les diffs et les blocs de code (``` ou ~~~) : un fichier qui contient
# « quota » ne déclenche jamais la bascule.
q_scan_stream() {
  local line trimmed in_code=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    trimmed="${line#"${line%%[![:space:]]*}"}"
    if [[ "$trimmed" == '```'* || "$trimmed" == '~~~'* ]]; then
      if [ "$in_code" -eq 0 ]; then in_code=1; else in_code=0; fi
      continue
    fi
    [ "$in_code" -eq 1 ] && continue
    case "$line" in
      +*|-*|@@*) continue ;;
    esac
    if q_line_is_error "$line"; then
      return 0
    fi
  done
  return 1
}

# Détecte un quota dans les sorties et/ou le journal interne.
q_detect() {
  local dir="" since="" f
  local -a outputs=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --output)
        [ "$#" -ge 2 ] || { q_error "--output sans valeur"; return 2; }
        outputs+=("$2")
        shift 2
        ;;
      --internal-log-dir)
        [ "$#" -ge 2 ] || { q_error "--internal-log-dir sans valeur"; return 2; }
        dir="$2"
        shift 2
        ;;
      --since-file)
        [ "$#" -ge 2 ] || { q_error "--since-file sans valeur"; return 2; }
        since="$2"
        shift 2
        ;;
      *)
        q_error "option inconnue : $1"
        return 2
        ;;
    esac
  done

  for f in "${outputs[@]}"; do
    [ -f "$f" ] || continue
    if q_scan_stream < "$f"; then
      return 0
    fi
  done

  if [ -n "$dir" ] && [ -d "$dir" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ -f "$f" ] || continue
      if q_scan_stream < "$f"; then
        return 0
      fi
    done < <(if [ -n "$since" ] && [ -f "$since" ]; then
               find "$dir" -type f -newer "$since" -print
             else
               find "$dir" -type f -print
             fi)
  fi
  return 1
}

q_next() {
  local file="${1-}" current="${2-}" i idx=-1 n
  [ -n "$file" ] || { q_error "models.txt non fourni"; return 2; }
  [ -n "$current" ] || { q_error "modèle courant non fourni"; return 2; }
  shift 2 || true

  local -a models=()
  local line models_raw
  if ! models_raw=$(q_models "$file"); then
    return 3
  fi
  while IFS= read -r line; do
    [ -n "$line" ] && models+=("$line")
  done <<< "$models_raw"
  n="${#models[@]}"
  [ "$n" -gt 0 ] || { q_error "aucun modèle disponible"; return 3; }

  if ! q_detect "$@"; then
    return 0
  fi

  for i in "${!models[@]}"; do
    if [ "${models[$i]}" = "$current" ]; then
      idx="$i"
      break
    fi
  done
  if [ "$idx" -lt 0 ]; then
    q_error "modèle courant absent de models.txt : $current"
    return 20
  fi
  if [ $((idx + 1)) -lt "$n" ]; then
    printf '%s\n' "${models[$((idx + 1))]}"
    return 10
  fi
  printf 'QUOTA_EXHAUSTED\n'
  return 20
}

usage() {
  cat >&2 <<'USAGE'
usage: quota.sh list <models.txt>
       quota.sh validate <models.txt>
       quota.sh next <models.txt> <modele_courant> [--output F] [--internal-log-dir D] [--since-file F]
USAGE
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    list)
      [ "$#" -eq 2 ] || { usage; return 2; }
      q_models "$2"
      ;;
    validate)
      [ "$#" -eq 2 ] || { usage; return 2; }
      q_models "$2" >/dev/null
      echo "models.txt valide"
      ;;
    next)
      [ "$#" -ge 3 ] || { usage; return 2; }
      shift
      q_next "$@"
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
