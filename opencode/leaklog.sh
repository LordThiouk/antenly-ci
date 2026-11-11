#!/usr/bin/env bash
# Chiffre le journal opencode (et le rapport gitleaks déjà masqué) pour le destinataire age
# public du dépôt, quand les contrôles avant push refusent le push : le runner est effacé,
# l'artefact chiffré est la seule trace qui survit.
#   leaklog.sh <journal> <rapport|-> <job> <run_id> <sortie> <raison> [url] [branche] [base]
# Écrit <sortie>/fullrun-log-<job>-<run>.age et affiche seulement ce chemin (jamais le contenu).
set +x
set -uo pipefail
log="${1:?journal attendu}"
report="${2:?rapport attendu (ou -)}"
job="${3:?job attendu}"
run="${4:?run attendu}"
outdir="${5:?dossier de sortie attendu}"
reason="${6:?raison attendue}"
url="${7:-}"
branch="${8:-}"
base="${9:-}"

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
rcp="${OC_LOG_RECIPIENT:-}"
if [ -z "$rcp" ]; then
  rcp=$(tr -d ' \t\r\n' < "$here/log-recipient.txt" 2>/dev/null || true)
fi
[[ "$rcp" =~ ^age1[0-9a-z]{20,}$ ]] || { echo "destinataire age introuvable ou invalide" >&2; exit 2; }
[[ "$job" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { echo "job invalide" >&2; exit 2; }
[[ "$run" =~ ^[0-9]{1,20}$ ]] || { echo "run invalide" >&2; exit 2; }
command -v age >/dev/null 2>&1 || { echo "age absent du PATH" >&2; exit 3; }
[ -f "$log" ] || { echo "journal introuvable" >&2; exit 4; }

name="fullrun-log-${job}-${run}.age"
stage=$(mktemp -d) || exit 4
trap 'rm -rf "$stage"' EXIT

cp -- "$log" "$stage/opencode.log" || exit 4
files=(opencode.log)
# Rapport gitleaks réduit à fichier / lignes / règle / commit : même avec --redact, on ne garde
# ni Match, ni Secret, ni le message de commit (texte libre écrit par l'IA).
if [ "$report" != "-" ] && [ -s "$report" ]; then
  if jq '[.[] | {File, StartLine, EndLine, RuleID, Commit, Description}]' "$report" \
       > "$stage/gitleaks.json" 2>/dev/null; then
    files+=(gitleaks.json)
  else
    rm -f "$stage/gitleaks.json"
  fi
fi
{
  echo "job: $job"
  echo "run: $run"
  echo "raison: $reason"
  echo "date: $(TZ=Africa/Dakar date '+%Y-%m-%d %H:%M') (Dakar)"
  [ -n "$url" ] && echo "run_url: $url"
  [ -n "$branch" ] && echo "branche: $branch"
  [ -n "$base" ] && echo "base: $base"
  echo "note: journal masqué par redact-log.sh ; rapport gitleaks produit avec --redact (aucune valeur de secret)."
} > "$stage/meta.txt"
files+=(meta.txt)

mkdir -p "$outdir" || exit 5
if ! tar -C "$stage" -czf - "${files[@]}" 2>/dev/null | age -r "$rcp" -o "$outdir/$name"; then
  rm -f "$outdir/$name"
  echo "chiffrement age impossible" >&2
  exit 5
fi
# Garde-fou : le fichier publié doit être une archive age (en-tête X25519), jamais du clair.
if [ "$(head -c 21 "$outdir/$name" 2>/dev/null)" != "age-encryption.org/v1" ] \
   || ! head -c 200 "$outdir/$name" | grep -qa '^-> X25519 '; then
  rm -f "$outdir/$name"; echo "archive age invalide" >&2; exit 5
fi
chmod 0644 "$outdir/$name"
printf '%s\n' "$outdir/$name"
