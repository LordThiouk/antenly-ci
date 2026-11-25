#!/usr/bin/env bash
# FullRun antenly-ci : outil figé « preannot ».
#
# Déclenche le workflow preannot déjà existant de ce dépôt — `ci.yml`, dont le job
# `preannot-ina` teste le vrai inaSpeechSegmenter + TensorFlow CPU sur le commit
# d'antenly demandé — attend un verdict borné, télécharge les artefacts s'il y en a,
# et n'affiche qu'un verdict + un court extrait de journal en cas d'échec.
#
# Portée du job : GitHub Actions ne sait pas dispatcher un job isolé d'un workflow
# (`ci.yml` n'a qu'un input `ref`, et découper le workflow en deux casserait la
# barrière `report-status` qui agrège les huit jobs). Le dispatch lance donc `ci.yml`
# entier, mais le VERDICT ne lit que le job `preannot-ina` : la conclusion d'un autre
# job (rust, licences, secrets…) ne peut ni valider ni invalider preannot. Le run
# global n'est plus qu'une enveloppe pour attendre la fin.
#
#   /opt/fullrun-tools/preannot.sh run
#
# Le jeton (GITHUB_TOKEN d'antenly-ci, `actions: write`) n'est jamais dans
# l'environnement d'opencode : il vit dans un fichier root 0600, lu seulement par la
# copie figée root. L'outil rebondit en sudo quand nécessaire. Aucun secret n'est
# affiché ; l'extrait de journal est masqué, borné en lignes et en largeur.
#
# Ne relâche aucune garde FullRun. Aucun merge, aucun déploiement, aucun autre dépôt.
set -euo pipefail
set +x

FROZEN="/opt/fullrun-tools/preannot.sh"
CANON_STATE="/opt/fullrun-tools/preannot.state"
CANON_TOKEN="/opt/fullrun-live/preannot.token"
REPO="LordThiouk/antenly-ci"
WORKFLOW="ci.yml"
RUN_TITLE_PREFIX="CI antenly@"
DEFAULT_TIMEOUT_SEC=5400
DEFAULT_POLL_SEC=30
DEFAULT_LOG_TAIL=80
DEFAULT_LOG_WIDTH=300

fail() { echo "$1" >&2; exit 1; }

usage() {
  printf '%s\n' \
    "preannot.sh run   déclenche ci.yml (job preannot-ina) sur la branche de travail," \
    "                  attend un verdict borné et télécharge les artefacts éventuels." >&2
}

# Rebond sur le binaire figé (root) : le jeton n'est pas dans l'environnement
# d'opencode, seulement dans un fichier root 0600.
maybe_sudo() {
  local cmd="${1:-}"
  case "$cmd" in
    run) ;;
    *) return 0 ;;
  esac
  [ "$(id -u)" -eq 0 ] && return 0
  [ -f "$CANON_TOKEN" ] || return 0
  [ -x "$FROZEN" ] || fail "outil figé absent : $FROZEN"
  exec sudo -n -H -- "$FROZEN" "$@"
}

load_file_vars() {
  local f="$1" line k v
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    k="${line%%=*}"
    v="${line#*=}"
    case "$k" in
      OC_BRANCH) OC_BRANCH="$v" ;;
      PREANNOT_TIMEOUT_SEC) PREANNOT_TIMEOUT_SEC="$v" ;;
      PREANNOT_POLL_SEC) PREANNOT_POLL_SEC="$v" ;;
      PREANNOT_LOG_TAIL) PREANNOT_LOG_TAIL="$v" ;;
      PREANNOT_LOG_WIDTH) PREANNOT_LOG_WIDTH="$v" ;;
      PREANNOT_ART_DIR) PREANNOT_ART_DIR="$v" ;;
      PREANNOT_RUN_UID) PREANNOT_RUN_UID="$v" ;;
      PREANNOT_RUN_GID) PREANNOT_RUN_GID="$v" ;;
      *) ;;
    esac
  done < "$f"
}

# En CI (root + état figé) : ignorer les variables d'environnement injectables.
# En test : PREANNOT_STATE ou l'environnement.
load_config() {
  OC_BRANCH="${OC_BRANCH:-${PREANNOT_BRANCH:-}}"
  PREANNOT_TIMEOUT_SEC="${PREANNOT_TIMEOUT_SEC:-$DEFAULT_TIMEOUT_SEC}"
  PREANNOT_POLL_SEC="${PREANNOT_POLL_SEC:-$DEFAULT_POLL_SEC}"
  PREANNOT_LOG_TAIL="${PREANNOT_LOG_TAIL:-$DEFAULT_LOG_TAIL}"
  PREANNOT_LOG_WIDTH="${PREANNOT_LOG_WIDTH:-$DEFAULT_LOG_WIDTH}"
  PREANNOT_ART_DIR="${PREANNOT_ART_DIR:-${OC_WORK:-$PWD}}"
  if [ "$(id -u)" -eq 0 ] && [ -f "$CANON_STATE" ]; then
    OC_BRANCH=""
    PREANNOT_TIMEOUT_SEC="$DEFAULT_TIMEOUT_SEC"
    PREANNOT_POLL_SEC="$DEFAULT_POLL_SEC"
    PREANNOT_LOG_TAIL="$DEFAULT_LOG_TAIL"
    PREANNOT_LOG_WIDTH="$DEFAULT_LOG_WIDTH"
    PREANNOT_ART_DIR="${OC_WORK:-/tmp}/preannot"
    PREANNOT_RUN_UID=""
    PREANNOT_RUN_GID=""
    load_file_vars "$CANON_STATE"
  elif [ -n "${PREANNOT_STATE:-}" ] && [ -f "$PREANNOT_STATE" ]; then
    load_file_vars "$PREANNOT_STATE"
  fi
  [[ "${PREANNOT_TIMEOUT_SEC}" =~ ^[0-9]+$ ]] || fail "timeout invalide"
  [[ "${PREANNOT_POLL_SEC}" =~ ^[0-9]+$ ]] || fail "intervalle de sondage invalide"
  [[ "${PREANNOT_LOG_TAIL}" =~ ^[0-9]+$ ]] || fail "taille d'extrait invalide"
  [[ "${PREANNOT_LOG_WIDTH}" =~ ^[0-9]+$ ]] || fail "largeur d'extrait invalide"
  [ "$PREANNOT_TIMEOUT_SEC" -ge 1 ] || fail "timeout invalide"
  [ "$PREANNOT_POLL_SEC" -ge 0 ] || fail "intervalle de sondage invalide"
  if [ "$PREANNOT_LOG_TAIL" -lt 1 ] || [ "$PREANNOT_LOG_TAIL" -gt 200 ]; then
    fail "taille d'extrait hors bornes (1-200)"
  fi
  if [ "$PREANNOT_LOG_WIDTH" -lt 40 ] || [ "$PREANNOT_LOG_WIDTH" -gt 500 ]; then
    fail "largeur d'extrait hors bornes"
  fi
  [ -n "$OC_BRANCH" ] || fail "branche de travail manquante (OC_BRANCH)"
  validate_ref "$OC_BRANCH"
}

# Le ref est un input string de ci.yml (branche ou commit d'antenly) : pas de
# métacaractère, pas de chemin, pas de valeur qui ressemble à une option.
validate_ref() {
  local ref="$1"
  [[ "$ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] || fail "ref refusée : format invalide"
  case "$ref" in
    *..*|*/|*.lock|refs/*) fail "ref refusée : format invalide" ;;
  esac
  case "${ref,,}" in
    main|master) fail "ref refusée : seule une branche de fonctionnalité est acceptée" ;;
  esac
}

gh_bin() {
  printf '%s\n' "${PREANNOT_GH:-gh}"
}

read_token() {
  local f="${PREANNOT_TOKEN_FILE:-}"
  if [ "$(id -u)" -eq 0 ] && [ -f "$CANON_TOKEN" ]; then
    f="$CANON_TOKEN"
  fi
  [ -n "$f" ] || f="$CANON_TOKEN"
  [ -r "$f" ] || fail "jeton GITHUB_TOKEN inaccessible (fichier d'outil figé)"
  IFS= read -r token < "$f" || true
  [ -n "${token:-}" ] || fail "jeton GITHUB_TOKEN vide"
}

gh_cmd() {
  local gh
  gh=$(gh_bin)
  GH_TOKEN="$token" GH_PROMPT_DISABLED=1 "$gh" "$@"
}

iso_minus() {
  local sec="$1"
  date -u -d "-${sec} seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || python3 -c 'import datetime,sys; s=int(sys.argv[1]); print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=s)).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$sec"
}

redact_stream() {
  # Masque le jeton s'il apparaît, coupe les lignes trop longues, garde un tail court.
  # Le jeton passe par l'ENVIRONNEMENT, jamais par argv : `ps` est lisible par tout
  # utilisateur de la box, et un secret en argument y resterait visible le temps du filtre.
  local tok="$1" tailn="$2" width="$3"
  PREANNOT_REDACT_TOKEN="$tok" python3 -c '
import os, sys
tok, tailn, width = os.environ.get("PREANNOT_REDACT_TOKEN", ""), int(sys.argv[1]), int(sys.argv[2])
out = []
for line in sys.stdin.read().splitlines():
    if tok:
        line = line.replace(tok, "***")
    if len(line) > width:
        line = line[:width] + "…"
    out.append(line)
if len(out) > tailn:
    out = out[-tailn:]
sys.stdout.write("\n".join(out))
if out:
    sys.stdout.write("\n")
' "$tailn" "$width"
}

# Le run créé par ce dispatch : même workflow, même ref (run-name `CI antenly@<ref>`),
# créé après le `since`. Un run d'un autre ref ne doit jamais être pris pour le nôtre.
find_new_run() {
  local since="$1" ref="$2" json
  json=$(gh_cmd run list -R "$REPO" --workflow="$WORKFLOW" \
    --event=workflow_dispatch --limit 20 \
    --json databaseId,createdAt,displayTitle,url) || return 1
  python3 -c '
import json,sys
since, ref, rows = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
want = sys.argv[4] + ref
cands = [r for r in rows
         if (r.get("createdAt") or "") >= since and (r.get("displayTitle") or "") == want]
if not cands:
    sys.exit(2)
cands.sort(key=lambda r: r.get("createdAt") or "", reverse=True)
print(cands[0]["databaseId"])
' "$since" "$ref" "$json" "$RUN_TITLE_PREFIX"
}

# Verdict borné au job `preannot-ina` : `jobs` est demandé au même appel. Le run entier
# ne sert qu'à attendre la fin (un échec rust/licences ne dit rien de preannot).
view_run() {
  gh_cmd run view "$1" -R "$REPO" --json status,conclusion,url,jobs
}

# Artefacts : best-effort. Leur absence ne change pas le verdict du run.
download_artifacts() {
  local run_id="$1" base="$2" dir="$2/preannot-$1" n json
  json=$(gh_cmd api "repos/$REPO/actions/runs/$run_id/artifacts" 2>/dev/null) \
    || { echo "artefact : liste indisponible"; return 0; }
  n=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("total_count") or 0)' "$json" 2>/dev/null || echo 0)
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if [ "$n" -eq 0 ]; then
    echo "artefact : aucun"
    return 0
  fi
  mkdir -p "$base"
  if gh_cmd run download "$run_id" -R "$REPO" -D "$dir" >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ] && [[ "${PREANNOT_RUN_UID:-}" =~ ^[0-9]+$ ]] \
       && [[ "${PREANNOT_RUN_GID:-}" =~ ^[0-9]+$ ]]; then
      chown -R "$PREANNOT_RUN_UID:$PREANNOT_RUN_GID" "$dir" 2>/dev/null || true
    fi
    echo "artefact : $n téléchargé(s) dans $dir"
  else
    echo "artefact : $n trouvé(s), téléchargement impossible"
  fi
}

run_preannot() {
  local since run_id deadline status conclusion url view s_status s_conclusion s_url
  load_config
  # Même garde que les autres outils figés : seulement depuis le FullRun (ou un test
  # avec un `gh` simulé).
  if [ "${GITHUB_ACTIONS:-}" != "true" ] && [ -z "${PREANNOT_GH:-}" ]; then
    fail "refus : lancer seulement depuis le FullRun (ou un test avec PREANNOT_GH)"
  fi
  read_token
  echo "déclenchement : $REPO $WORKFLOW (job preannot-ina) ref=$OC_BRANCH"
  # Pas de --ref : le workflow vit sur la branche par défaut d'antenly-ci ; la ref
  # passée est l'input `ref` de ci.yml (branche ou commit d'antenly), pas une ref du
  # dépôt de workflows.
  if ! gh_cmd workflow run "$WORKFLOW" -R "$REPO" -f "ref=${OC_BRANCH}"; then
    fail "échec du déclenchement : le jeton GITHUB_TOKEN a-t-il actions:write sur ${REPO} ?"
  fi

  since=$(iso_minus 15)
  deadline=$(( $(date +%s) + PREANNOT_TIMEOUT_SEC ))
  run_id=""
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if run_id=$(find_new_run "$since" "$OC_BRANCH" 2>/dev/null); then
      [ -n "$run_id" ] && break
    fi
    run_id=""
    [ "$PREANNOT_POLL_SEC" -gt 0 ] && sleep "$PREANNOT_POLL_SEC"
    [ "$PREANNOT_POLL_SEC" -eq 0 ] && sleep 1
  done
  [ -n "$run_id" ] || fail "aucun run preannot trouvé avant le délai (déclenchement peut-être refusé)"
  echo "run=${run_id} https://github.com/${REPO}/actions/runs/${run_id}"

  status=""
  conclusion=""
  url=""
  job_conclusion=""
  job_name="preannot-ina"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    view=$(view_run "$run_id") || fail "impossible de lire le run ${run_id}"
    # shellcheck disable=SC2016
    eval "$(python3 -c '
import json,sys,shlex
d=json.loads(sys.argv[1])
for k in ("status","conclusion","url"):
    print("s_%s=%s" % (k, shlex.quote(str(d.get(k) or ""))))
# Conclusion du seul job qui nous intéresse (nom de job = clé du workflow, sans `name:`).
want = sys.argv[2]
jc = ""
for j in d.get("jobs") or []:
    if (j.get("name") or "") == want:
        jc = str(j.get("conclusion") or "")
        break
print("s_job=%s" % shlex.quote(jc))
' "$view" "$job_name")"
    status="$s_status"
    conclusion="$s_conclusion"
    url="$s_url"
    # shellcheck disable=SC2154 # s_job est produit par l eval ci-dessus
    job_conclusion="$s_job"
    case "$status" in
      completed|cancelled) break ;;
    esac
    [ "$PREANNOT_POLL_SEC" -gt 0 ] && sleep "$PREANNOT_POLL_SEC"
    [ "$PREANNOT_POLL_SEC" -eq 0 ] && sleep 1
  done

  if [ "$status" != "completed" ] && [ "$status" != "cancelled" ]; then
    echo "verdict=timeout status=${status:-?} run=${run_id}" >&2
    echo "timeout : le run ${run_id} n'a pas fini en ${PREANNOT_TIMEOUT_SEC}s" >&2
    exit 124
  fi

  # Verdict = conclusion du job `preannot-ina` quand GitHub la donne ; sinon (ancienne
  # réponse `gh`, job absent) repli explicite sur la conclusion du run, annoncé comme tel.
  verdict_from="run"
  if [ -n "${job_conclusion:-}" ]; then
    conclusion="$job_conclusion"
    verdict_from="job ${job_name}"
  fi

  echo "verdict=${conclusion:-$status} status=$status run=$run_id verdict_de=$verdict_from"
  [ -n "$url" ] && echo "url=$url"
  download_artifacts "$run_id" "$PREANNOT_ART_DIR"

  if [ "$conclusion" = "success" ]; then
    echo "preannot : succès"
    return 0
  fi

  echo "preannot : échec (${conclusion:-$status})"
  echo "extrait des logs (tail, pas le journal complet) :"
  set +e
  if ! gh_cmd run view "$run_id" -R "$REPO" --log-failed 2>/dev/null \
      | redact_stream "$token" "$PREANNOT_LOG_TAIL" "$PREANNOT_LOG_WIDTH"; then
    echo "(extrait indisponible)"
  fi
  set -e
  return 1
}

cmd="${1:-}"
case "$cmd" in
  run) ;;
  help|-h|--help) usage; exit 0 ;;
  *) usage; fail "commande inconnue : ${cmd:-<vide>}" ;;
esac

maybe_sudo "$@"
run_preannot
