#!/usr/bin/env bash
# FullRun galass-ci : option with_emulators.
# Déclenche le e2e Artemis sur LordThiouk/galass-emu-actions-pub (secrets e2e déjà
# présents là-bas), attend un verdict borné, et n'affiche qu'un court extrait en
# échec. Pas de démarrage local d'émulateurs, pas de build APK, pas de secret e2e
# sur galass-ci. Le jeton (GALASS_TOKEN) n'est jamais affiché ni passé à opencode.
#
#   emu-e2e.sh run            déclenche, attend, affiche le verdict
#   emu-e2e.sh status <run_id> état du run (lecture seule, id numérique) : status=… conclusion=…
#   emu-e2e.sh resolve-refs   affiche rider_ref et driver_ref
#   emu-e2e.sh prompt-block   bloc à ajouter au prompt (aucun secret)
#   emu-e2e.sh append-prompt  ajoute le bloc à $OC_WORK/prompt.md
#
# Ne relâche aucune garde FullRun. Modèle dispatché : opencode/*-free (jamais FreeLLM, jamais de clé API).
set -euo pipefail
set +x

FROZEN="/opt/fullrun-tools/emu-e2e.sh"
CANON_STATE="/opt/fullrun-tools/emu-e2e.state"
CANON_TOKEN="/opt/fullrun-live/emu-e2e.token"
# Chaînage : un run e2e peut durer plus qu'un lien (jobs courts). INFLIGHT = id du run lancé et pas
# encore terminé (lu par le step chain, transmis au lien suivant dans chain_state) ; RESUME = id
# restauré au démarrage du lien suivant (root 0600) : « run » reprend alors le sondage de CE run au
# lieu d'en relancer un. Fichiers root, hors de portée d'opencode.
EMU_INFLIGHT_FILE="${EMU_E2E_INFLIGHT_FILE:-/opt/fullrun-live/emu-run}"
EMU_RESUME_FILE="${EMU_E2E_RESUME_FILE:-/opt/fullrun-live/emu-resume}"
EMU_OWNER="LordThiouk"
EMU_REPO_NAME="galass-emu-actions-pub"
EMU_REPO="${EMU_OWNER}/${EMU_REPO_NAME}"
EMU_WORKFLOW="artemis-staging-e2e.yml"
RIDER_REPO="Galass_Rider"
DRIVER_REPO="Galass_Driver"
DEFAULT_MODEL="opencode/deepseek-v4.1-flash-free"
DEFAULT_TIMEOUT_SEC=10800
DEFAULT_POLL_SEC=30
DEFAULT_LOG_TAIL=80
DEFAULT_LOG_WIDTH=300
# Plafond par appel gh : un appel réseau qui pend ne doit jamais bloquer la boucle d'attente.
DEFAULT_GH_TIMEOUT_SEC=60
# Après TERM, KILL au bout de N s : un gh qui ignore TERM ne bloque pas non plus.
GH_KILL_AFTER_SEC=5
# Lectures consécutives du run en échec avant d'abandonner (erreurs transitoires tolérées).
MAX_VIEW_FAILS=5
FALLBACK_REF="main"

fail() { echo "$1" >&2; exit 1; }

# Rebond sur le binaire figé (root) pour run / resolve-refs : le jeton n'est pas
# dans l'environnement d'opencode, seulement dans un fichier root 0600.
maybe_sudo() {
  local cmd="${1:-}"
  case "$cmd" in
    run|resolve-refs|status) ;;
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
      EMU_E2E_MODEL) EMU_E2E_MODEL="$v" ;;
      EMU_E2E_TIMEOUT_SEC) EMU_E2E_TIMEOUT_SEC="$v" ;;
      EMU_E2E_POLL_SEC) EMU_E2E_POLL_SEC="$v" ;;
      EMU_LOG_TAIL) EMU_LOG_TAIL="$v" ;;
      EMU_LOG_WIDTH) EMU_LOG_WIDTH="$v" ;;
      EMU_E2E_GH_TIMEOUT_SEC) EMU_E2E_GH_TIMEOUT_SEC="$v" ;;
      *) ;;
    esac
  done < "$f"
}

# En CI (root + état figé) : ignorer les variables d'environnement injectables.
# En test : EMU_E2E_STATE / l'environnement.
load_config() {
  OC_BRANCH="${OC_BRANCH:-${IN_BRANCH:-}}"
  EMU_E2E_MODEL="${EMU_E2E_MODEL:-$DEFAULT_MODEL}"
  EMU_E2E_TIMEOUT_SEC="${EMU_E2E_TIMEOUT_SEC:-$DEFAULT_TIMEOUT_SEC}"
  EMU_E2E_POLL_SEC="${EMU_E2E_POLL_SEC:-$DEFAULT_POLL_SEC}"
  EMU_LOG_TAIL="${EMU_LOG_TAIL:-$DEFAULT_LOG_TAIL}"
  EMU_LOG_WIDTH="${EMU_LOG_WIDTH:-$DEFAULT_LOG_WIDTH}"
  EMU_E2E_GH_TIMEOUT_SEC="${EMU_E2E_GH_TIMEOUT_SEC:-$DEFAULT_GH_TIMEOUT_SEC}"
  if [ "$(id -u)" -eq 0 ] && [ -f "$CANON_STATE" ]; then
    OC_BRANCH=""; EMU_E2E_MODEL="$DEFAULT_MODEL"
    EMU_E2E_TIMEOUT_SEC="$DEFAULT_TIMEOUT_SEC"
    EMU_E2E_POLL_SEC="$DEFAULT_POLL_SEC"
    EMU_LOG_TAIL="$DEFAULT_LOG_TAIL"
    EMU_LOG_WIDTH="$DEFAULT_LOG_WIDTH"
    EMU_E2E_GH_TIMEOUT_SEC="$DEFAULT_GH_TIMEOUT_SEC"
    load_file_vars "$CANON_STATE"
  elif [ -n "${EMU_E2E_STATE:-}" ] && [ -f "$EMU_E2E_STATE" ]; then
    load_file_vars "$EMU_E2E_STATE"
  fi
  [[ "${EMU_E2E_TIMEOUT_SEC}" =~ ^[0-9]+$ ]] || fail "timeout invalide"
  [[ "${EMU_E2E_POLL_SEC}" =~ ^[0-9]+$ ]] || fail "intervalle de sondage invalide"
  [[ "${EMU_LOG_TAIL}" =~ ^[0-9]+$ ]] || fail "taille d'extrait invalide"
  [[ "${EMU_LOG_WIDTH}" =~ ^[0-9]+$ ]] || fail "largeur d'extrait invalide"
  [[ "${EMU_E2E_GH_TIMEOUT_SEC}" =~ ^[0-9]+$ ]] || fail "timeout d'appel gh invalide"
  if [ "$EMU_E2E_GH_TIMEOUT_SEC" -lt 1 ] || [ "$EMU_E2E_GH_TIMEOUT_SEC" -gt 600 ]; then
    fail "timeout d'appel gh hors bornes (1-600)"
  fi
  [ "$EMU_E2E_TIMEOUT_SEC" -ge 1 ] || fail "timeout invalide"
  [ "$EMU_E2E_POLL_SEC" -ge 0 ] || fail "intervalle de sondage invalide"
  if [ "$EMU_LOG_TAIL" -lt 1 ] || [ "$EMU_LOG_TAIL" -gt 200 ]; then
    fail "taille d'extrait hors bornes (1-200)"
  fi
  if [ "$EMU_LOG_WIDTH" -lt 40 ] || [ "$EMU_LOG_WIDTH" -gt 500 ]; then
    fail "largeur d'extrait hors bornes"
  fi
  [ -n "$OC_BRANCH" ] || fail "branche de travail manquante (OC_BRANCH)"
}

normalize_model() {
  local m="$1"
  m="${m#"${m%%[![:space:]]*}"}"
  m="${m%"${m##*[![:space:]]}"}"
  case "$m" in
    opencode/*) printf '%s\n' "$m" ;;
    *) printf 'opencode/%s\n' "$m" ;;
  esac
}

validate_model() {
  local raw="$1" m
  [ -n "$raw" ] || fail "modèle refusé (uniquement opencode/*-free)"
  case "$raw" in
    *freellm*|*FreeLLM*|*[Ff]ree[Ll][Ll][Mm]*)
      fail "modèle refusé (pas de FreeLLM) : $raw"
      ;;
  esac
  m=$(normalize_model "$raw")
  [[ "$m" =~ ^opencode/[a-z0-9][a-z0-9.-]*-free$ ]] \
    || fail "modèle refusé (uniquement opencode/*-free) : $raw"
  printf '%s\n' "$m"
}

gh_bin() {
  printf '%s\n' "${EMU_E2E_GH:-gh}"
}

read_token() {
  local f="${EMU_E2E_TOKEN_FILE:-}"
  if [ "$(id -u)" -eq 0 ] && [ -f "$CANON_TOKEN" ]; then
    f="$CANON_TOKEN"
  fi
  [ -n "$f" ] || f="$CANON_TOKEN"
  [ -r "$f" ] || fail "jeton GALASS_TOKEN inaccessible (fichier d'outil figé)"
  # une seule ligne, sans l'afficher
  IFS= read -r token < "$f" || true
  [ -n "${token:-}" ] || fail "jeton GALASS_TOKEN vide"
}

urlenc() {
  python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

branch_exists() {
  local repo="$1" ref="$2" enc
  enc=$(urlenc "$ref")
  gh_cmd api --silent "repos/${EMU_OWNER}/${repo}/branches/${enc}"
}

resolve_one() {
  local repo="$1" ref
  if branch_exists "$repo" "$OC_BRANCH"; then
    printf '%s\n' "$OC_BRANCH"
  else
    printf '%s\n' "$FALLBACK_REF"
  fi
}

resolve_refs() {
  load_config
  read_token
  rider_ref=$(resolve_one "$RIDER_REPO")
  driver_ref=$(resolve_one "$DRIVER_REPO")
  # emu_ref : branche de galass-emu-actions-pub lui-même (le harnais e2e), pas
  # seulement Rider/Driver — revue : sans elle, `gh workflow run` tournait toujours
  # sur le harnais de main, même quand la branche de travail le modifiait.
  emu_ref=$(resolve_one "$EMU_REPO_NAME")
  echo "rider_ref=${rider_ref}"
  echo "driver_ref=${driver_ref}"
  echo "emu_ref=${emu_ref}"
  if [ "$rider_ref" = "$FALLBACK_REF" ] && [ "$OC_BRANCH" != "$FALLBACK_REF" ]; then
    echo "note : ${RIDER_REPO} n'a pas la branche ${OC_BRANCH} sur GitHub ; fallback ${FALLBACK_REF}."
  fi
  if [ "$driver_ref" = "$FALLBACK_REF" ] && [ "$OC_BRANCH" != "$FALLBACK_REF" ]; then
    echo "note : ${DRIVER_REPO} n'a pas la branche ${OC_BRANCH} sur GitHub ; fallback ${FALLBACK_REF}."
  fi
  if [ "$emu_ref" = "$FALLBACK_REF" ] && [ "$OC_BRANCH" != "$FALLBACK_REF" ]; then
    echo "note : ${EMU_REPO_NAME} n'a pas la branche ${OC_BRANCH} sur GitHub ; fallback ${FALLBACK_REF}."
  fi
}

prompt_block() {
  cat <<EOF
# Tests e2e via galass-emu-actions-pub (with_emulators)

Les émulateurs ne tournent pas sur ce runner. Pour lancer les tests e2e (vrai staging,
apps Rider et Driver), appelle seulement :

    /opt/fullrun-tools/emu-e2e.sh run

Cet outil déclenche le workflow \`artemis-staging-e2e.yml\` sur
\`LordThiouk/galass-emu-actions-pub\` (les secrets e2e restent dans ce dépôt), attend
la fin (délai borné), puis affiche le verdict et, en cas d'échec, un court extrait
des logs (pas le journal complet). Tu peux corriger le code, commiter, puis relancer
la commande en boucle.

- \`rider_ref\` / \`driver_ref\` : la branche de travail \`\$OC_BRANCH\` si elle existe
  sur le dépôt, sinon \`main\`. Tu ne choisis pas ces refs toi-même.
- Si le script retombe sur \`main\`, la branche de travail n'est pas encore sur GitHub :
  attends le push wip, puis relance.
- Modèle côté emu : uniquement \`opencode/*-free\` (défaut
  \`opencode/deepseek-v4.1-flash-free\`). Le CLI opencode (pas une clé API)
  pilote les émulateurs sur le dépôt emu. Pas de FreeLLM, pas d'appel HTTP
  direct à un modèle. Les modèles FullRun restent \`opencode/*-free\`.
- Lancement : l'outil dure jusqu'à la fin du run (plusieurs dizaines de minutes) ; lance-le en
  tâche de fond détachée, en deux commandes séparées : d'abord \`LOG=/tmp/fullrun/e2e-run.log\`,
  puis \`setsid nohup sudo -n -H -- env GITHUB_ACTIONS=true /opt/fullrun-tools/emu-e2e.sh run
  > "\$LOG" 2>&1 < /dev/null &\`. Jamais \`A && B && nohup … &\` : le sous-shell garde la
  sortie de ton outil ouverte, l'outil est tué au délai et le script avec lui.
- Chaque sondage écrit une ligne datée dans ce log. Ne dors pas plus de 2 cycles sur un log qui
  ne bouge plus : lis l'état réel avec \`sudo -n -H -- /opt/fullrun-tools/emu-e2e.sh status <run_id>\`
  (lecture seule, l'équivalent de \`gh run view\`, sans jeton chez toi) et passe à la suite si le
  run est \`status=completed\` (le verdict est dans \`conclusion=\`), ou signale le blocage.
- Tu n'as aucun jeton : n'utilise pas \`gh\` toi-même, n'invente pas de secret,
  n'écris aucun secret. Passe seulement par le script figé ci-dessus
  (pas une copie dans le workspace).
EOF
}

append_prompt() {
  local p
  [ -n "${OC_WORK:-}" ] || fail "OC_WORK manquant"
  p="${OC_WORK}/prompt.md"
  [ -f "$p" ] || fail "prompt introuvable : $p"
  { printf '\n'; prompt_block; printf '\n'; } >> "$p"
  echo "bloc e2e (emu-e2e) ajouté au prompt"
}

iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

iso_minus() {
  local sec="$1"
  date -u -d "-${sec} seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || python3 -c 'import datetime,sys; s=int(sys.argv[1]); print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=s)).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$sec"
}

redact_stream() {
  # Masque le jeton s'il apparaît, coupe les lignes trop longues, garde un tail court.
  local tok="$1" tailn="$2" width="$3"
  python3 -c '
import sys
tok, tailn, width = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
lines = sys.stdin.read().splitlines()
out = []
for line in lines:
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
' "$tok" "$tailn" "$width"
}

gh_cmd() {
  local gh timeout_sec
  gh=$(gh_bin)
  timeout_sec="${EMU_E2E_GH_TIMEOUT_SEC:-$DEFAULT_GH_TIMEOUT_SEC}"
  # Chaque appel est plafonné : TERM à la limite puis KILL "$GH_KILL_AFTER_SEC" après (rc 124/137).
  # Pas de repli sans plafond : sans `timeout`, on refuse plutôt que de risquer une attente infinie.
  command -v timeout >/dev/null 2>&1 || fail "timeout introuvable : appel gh non borné refusé"
  #
  # Cause CI (run 44272795157) : `timeout -k`, pour atteindre un petit-enfant de "gh" resté bloqué
  # (ex. un appel réseau interne qui pend) après que "gh" lui-même a été tué, doit viser tout le
  # groupe de processus, pas seulement "gh". Cette mise en groupe est faite PAR `timeout` lui-même
  # (setpgid sur son enfant direct avant l'exec) ; en local, ce mécanisme interne fonctionnait à
  # tous les niveaux testés (KILL atteignait bien tout l'arbre, tube de sortie libéré en ~6 s). En
  # CI, le process "gh" direct mourait bien (rc 124 obtenu via le chien de garde global de
  # run_e2e, indépendant de ceci) mais un petit-enfant orphelin gardait le tube de sortie ouvert
  # jusqu'à sa fin naturelle (~30 s) — preuve que CE mécanisme interne, dépendant de
  # l'environnement/version, n'y plaçait pas (ou plus) "gh" et ses descendants dans un groupe que
  # `timeout` pouvait cibler. Plutôt que de dépendre de ce détail d'implémentation non portable
  # (une tentative avec `setsid` en préfixe a été essayée puis écartée : "setsid", invoqué comme
  # enfant d'un `timeout` qui a déjà fait de lui un meneur de groupe, se refork lui-même dans un
  # DEUXIÈME groupe que `timeout` ne surveille plus — pire, pas mieux), on crée nous-mêmes ce
  # groupe, par le contrôle de tâches natif de bash (`set -m`, pur et portable, indépendant de
  # tout binaire externe) : tout processus lancé en arrière-plan sous `set -m` devient le meneur
  # de son propre nouveau groupe (pgid = son pid), que ses descendants héritent tels quels. On
  # revérifie nous-mêmes, après le retour de `timeout`, qu'aucun descendant ne survit dans ce
  # groupe ; si c'est le cas (le scénario CI), on l'achève nous-mêmes par KILL sur le groupe entier
  # (pid négatif) avant de rendre la main — sans jamais dépendre de ce que `timeout` a réussi, ou
  # non, à faire lui-même de son côté.
  (
    set -m
    GH_TOKEN="$token" GH_PROMPT_DISABLED=1 \
      timeout -k "$GH_KILL_AFTER_SEC" "$timeout_sec" "$gh" "$@" &
    pid=$!
    # `set +m` dès le pid capturé : le groupe (créé à l'instant par `set -m` ci-dessus) est déjà
    # fixé, mais le mode moniteur fait aussi imprimer par bash des lignes « [1]+ Done/Exit » sur
    # la sortie de ce job dès que `wait` le voit se terminer — du bruit qui polluerait le JSON lu
    # par l'appelant. On le désactive juste après, avant le `wait`, uniquement pour ce filtrage.
    set +m 2>/dev/null
    wait "$pid"
    rc=$?
    # Filet de sécurité : le groupe créé par `set -m` pour ce job (pgid == $pid) peut encore
    # contenir un descendant orphelin que `timeout` n'a pas réussi à joindre. On l'achève
    # nous-mêmes avant de rendre la main, pour ne jamais laisser le tube de sortie ouvert plus
    # longtemps que "$timeout_sec" + "$GH_KILL_AFTER_SEC".
    kill -KILL -- "-$pid" 2>/dev/null || true
    exit "$rc"
  )
}

find_new_run() {
  # $2 (want_branch) : préfère un run dont headBranch == want_branch, pour ne jamais ramasser à
  # sa place un run déclenché ailleurs (une relance manuelle sur main, un autre FullRun) quand un
  # run sur la bonne branche existe dans la fenêtre. S'il n'en existe aucun sur la bonne branche
  # mais qu'un run existe quand même dans la fenêtre (autre branche), on le retourne tout de même :
  # c'est exactement le scénario du bug d'origine (dispatch sans --ref -> run exécuté sur main), et
  # c'est à l'appelant (run_e2e) de le refuser nommément via la garde head_branch, jamais en silence
  # par un simple timeout générique (sinon, un filtre strict qui exclurait d'emblée tout run sur la
  # mauvaise branche ne retrouverait jamais ce run, et on perdrait le message explicite « mauvais
  # ref » au profit d'un timeout muet). Imprime deux lignes (id, headBranch du run choisi) :
  # l'appelant revérifie la seconde sans refaire d'appel gh — même réponse de `run list` que celle
  # filtrée ici.
  local since="$1" want_branch="$2" json
  json=$(gh_cmd run list -R "$EMU_REPO" --workflow="$EMU_WORKFLOW" \
    --event=workflow_dispatch --limit 10 \
    --json databaseId,createdAt,status,conclusion,url,headBranch) || return 1
  python3 -c '
import json,sys
since=sys.argv[1]
want=sys.argv[3]
rows=json.loads(sys.argv[2])
cands=[r for r in rows if (r.get("createdAt") or "") >= since]
if not cands:
    sys.exit(2)
right=[r for r in cands if (r.get("headBranch") or "") == want]
pool=right if right else cands
pool.sort(key=lambda r: r.get("createdAt") or "", reverse=True)
chosen=pool[0]
print(chosen["databaseId"])
print(chosen.get("headBranch") or "")
' "$since" "$json" "$want_branch"
}

view_run() {
  gh_cmd run view "$1" -R "$EMU_REPO" --json status,conclusion,url,displayTitle,headBranch
}

# Lecture seule d'un run déjà lancé : l'agent n'a pas de jeton, il passe par ici (sudo) au lieu
# de relire un log qui ne bouge plus. Une ligne, rc 0 si lu, 1 sinon.
# Chien de garde : échéance dure = délai + un dernier tour de sondage + deux appels gh plafonnés.
# Passé ce délai, USR1 au processus principal (trap → verdict=timeout, exit 124).
watchdog_start() {
  local hard main=$$
  hard=$(( EMU_E2E_TIMEOUT_SEC + EMU_E2E_POLL_SEC + 2 * (EMU_E2E_GH_TIMEOUT_SEC + GH_KILL_AFTER_SEC) + 30 ))
  (
    sleep "$hard" & sp=$!
    trap 'kill "$sp" 2>/dev/null; exit 0' TERM
    wait "$sp" && kill -USR1 "$main" 2>/dev/null
  ) &
  WATCHDOG_PID=$!
  trap 'kill "$WATCHDOG_PID" 2>/dev/null' EXIT
}

status_run() {
  local id="${1:-}" view
  [[ "$id" =~ ^[0-9]{1,20}$ ]] || fail "status : identifiant de run numérique requis"
  load_config
  read_token
  view=$(view_run "$id" 2>/dev/null) || { echo "status=illisible run=${id}"; return 1; }
  python3 -c '
import json,sys
d=json.loads(sys.argv[1])
print("status=%s conclusion=%s run=%s" % (d.get("status") or "?", d.get("conclusion") or "-", sys.argv[2]))
' "$view" "$id"
}

run_e2e() {
  local since run_id deadline status conclusion url view s_status s_conclusion s_url t_start finds=0
  load_config
  EMU_E2E_MODEL=$(validate_model "$EMU_E2E_MODEL")
  if [ "${GITHUB_ACTIONS:-}" != "true" ] && [ -z "${EMU_E2E_GH:-}" ]; then
    fail "refus : lancer seulement depuis le FullRun (ou un test avec EMU_E2E_GH)"
  fi
  read_token
  t_start=$(date +%s)
  RUN_ID_CUR=""
  # Sortie garantie : un signal (TERM/INT/HUP) ou le chien de garde laisse TOUJOURS une ligne
  # verdict= dans le log, jamais un log muet. SIGKILL ne se piège pas : c'est pourquoi chaque
  # sondage écrit aussi une ligne datée (un log figé = processus mort ou bloqué, détectable).
  trap 'echo "verdict=interrompu signal=TERM run=${RUN_ID_CUR:-?}"; exit 143' TERM
  trap 'echo "verdict=interrompu signal=INT run=${RUN_ID_CUR:-?}"; exit 130' INT
  trap 'echo "verdict=interrompu signal=HUP run=${RUN_ID_CUR:-?}"; exit 129' HUP
  trap 'echo "verdict=timeout watchdog run=${RUN_ID_CUR:-?} (échéance dure dépassée)"; exit 124' USR1
  watchdog_start
  rider_ref=$(resolve_one "$RIDER_REPO")
  driver_ref=$(resolve_one "$DRIVER_REPO")
  # emu_ref : branche du harnais lui-même. Sans --ref, `gh workflow run` exécute
  # TOUJOURS la version du workflow sur la branche par défaut (main) du dépôt
  # emu — jamais celle de la branche de travail, même si rider_ref/driver_ref
  # pointent dessus (revue : l.361, chaque e2e tournait sur le harnais de main).
  emu_ref=$(resolve_one "$EMU_REPO_NAME")
  echo "déclenchement : $EMU_REPO $EMU_WORKFLOW"
  echo "rider_ref=${rider_ref} driver_ref=${driver_ref} emu_ref=${emu_ref} model=${EMU_E2E_MODEL}"
  if [ "$rider_ref" = "$FALLBACK_REF" ] && [ "$OC_BRANCH" != "$FALLBACK_REF" ]; then
    echo "note : ${RIDER_REPO} n'a pas la branche ${OC_BRANCH} sur GitHub ; fallback ${FALLBACK_REF}."
  fi
  if [ "$driver_ref" = "$FALLBACK_REF" ] && [ "$OC_BRANCH" != "$FALLBACK_REF" ]; then
    echo "note : ${DRIVER_REPO} n'a pas la branche ${OC_BRANCH} sur GitHub ; fallback ${FALLBACK_REF}."
  fi
  if [ "$emu_ref" = "$FALLBACK_REF" ] && [ "$OC_BRANCH" != "$FALLBACK_REF" ]; then
    echo "note : ${EMU_REPO_NAME} n'a pas la branche ${OC_BRANCH} sur GitHub ; fallback ${FALLBACK_REF}."
  fi

  resume_id=""
  if [ -f "$EMU_RESUME_FILE" ]; then
    resume_id=$(tr -d '[:space:]' < "$EMU_RESUME_FILE" 2>/dev/null || true)
    rm -f "$EMU_RESUME_FILE"
    [[ "$resume_id" =~ ^[0-9]{1,20}$ ]] || resume_id=""
  fi

  since=$(iso_minus 15)
  # --ref="$emu_ref" : sans lui, le dispatch exécute toujours le harnais (e2e/*.sh, workflow) de la
  # branche par défaut du dépôt emu, même quand rider_ref/driver_ref pointent la branche de travail
  # (run 44238051634 : head_branch=main, échec immédiat sur du code que la branche de travail ne contient
  # plus). --ref ne change pas rider_ref/driver_ref, qui restent des inputs du workflow.
  if [ -n "$resume_id" ]; then
    echo "reprise du run e2e ${resume_id} (lien précédent) : aucun nouveau déclenchement"
  elif ! gh_cmd workflow run "$EMU_WORKFLOW" -R "$EMU_REPO" --ref "$emu_ref" \
      -f "rider_ref=${rider_ref}" -f "driver_ref=${driver_ref}" \
      -f "model=${EMU_E2E_MODEL}"; then
    fail "échec du déclenchement : le jeton GALASS_TOKEN a-t-il le droit actions:write sur ${EMU_REPO} ?"
  fi

  deadline=$(( $(date +%s) + EMU_E2E_TIMEOUT_SEC ))
  run_id=""
  run_branch=""
  if [ -n "$resume_id" ]; then
    # le head_branch est revérifié à chaque lecture par la boucle de sondage plus bas
    run_id="$resume_id"; run_branch="$emu_ref"
  fi
  while [ -z "$resume_id" ] && [ "$(date +%s)" -lt "$deadline" ]; do
    # find_new_run filtre désormais par branche (emu_ref) : un run plus récent
    # mais sur une autre branche (ex. un autre job sur main) ne doit jamais être
    # pris pour celui qu'on vient de déclencher, s'il en existe un sur la bonne.
    if found=$(find_new_run "$since" "$emu_ref" 2>/dev/null); then
      run_id=$(printf '%s\n' "$found" | sed -n '1p')
      run_branch=$(printf '%s\n' "$found" | sed -n '2p')
      [ -n "$run_id" ] && break
    fi
    run_id=""
    finds=$(( finds + 1 ))
    echo "$(date -u +%H:%M:%S) attente du démarrage du run : sondage ${finds} (+$(( $(date +%s) - t_start ))s)"
    [ "$EMU_E2E_POLL_SEC" -gt 0 ] && sleep "$EMU_E2E_POLL_SEC"
    [ "$EMU_E2E_POLL_SEC" -eq 0 ] && sleep 1
  done
  [ -n "$run_id" ] || fail "aucun run e2e trouvé avant le délai sur la branche ${emu_ref} (déclenchement peut-être refusé ou mauvais ref)"
  RUN_ID_CUR="$run_id"
  printf '%s\n' "$run_id" > "$EMU_INFLIGHT_FILE" 2>/dev/null || true
  echo "run=${run_id} https://github.com/${EMU_REPO}/actions/runs/${run_id}"

  # Première garde, bon marché (aucun appel gh : headBranch vient du `run list` déjà fait
  # dans find_new_run) : le run choisi est revérifié avant de laisser son verdict se lire
  # comme un test. Jamais un faux FAIL de test : le message nomme explicitement la cause
  # (« mauvais ref »). Elle ne suffit pas seule : `run list` et `run view` peuvent diverger
  # (API en retard, run réutilisé) — c'est pourquoi la boucle d'attente plus bas revérifie
  # aussi le head_branch sur chaque lecture via `run view`, sans appel gh supplémentaire ni
  # changement des bornes déjà calibrées (done/flaky/broken).
  if [ -z "$run_branch" ] || [ "$run_branch" != "$emu_ref" ]; then
    echo "verdict=FAIL ref_erronee run=${run_id} attendu=${emu_ref} obtenu=${run_branch:-?}"
    fail "mauvais ref : run ${run_id} déclenché sur head_branch=${run_branch:-?} au lieu de ${emu_ref} (jamais lu comme un échec de test)"
  fi

  # Attente bornée de l'état du run : on sort dès que status=completed (ou qu'une
  # conclusion existe), sans dormir de plus. Trois bornes indépendantes : l'échéance
  # horloge, un nombre maximal de lectures, et MAX_VIEW_FAILS lectures consécutives en
  # échec (les erreurs transitoires sont tolérées, pas indéfiniment).
  status=""
  conclusion=""
  url=""
  local polls=0 view_fails=0 poll_step max_polls
  poll_step="$EMU_E2E_POLL_SEC"
  [ "$poll_step" -ge 1 ] || poll_step=1
  max_polls=$(( EMU_E2E_TIMEOUT_SEC / poll_step + 5 ))
  while [ "$(date +%s)" -lt "$deadline" ] && [ "$polls" -lt "$max_polls" ]; do
    polls=$(( polls + 1 ))
    if view=$(view_run "$run_id" 2>/dev/null); then
      view_fails=0
      eval "$(python3 -c '
import json,sys,shlex
d=json.loads(sys.argv[1])
for k in ("status","conclusion","url","headBranch"):
    print("s_%s=%s" % (k.lower(), shlex.quote(str(d.get(k) or ""))))
' "$view")"
      status="$s_status"
      conclusion="$s_conclusion"
      url="$s_url"
      # Régression (revue) : find_new_run filtre par headBranch via `run list`, mais `run
      # list` et `run view` peuvent diverger (API en retard, run réutilisé) — la fusion avec
      # main avait retiré la revérification indépendante du head_branch via `run view` que
      # PR #11 ajoutait, en se fiant seulement à `run list`. Preuve du retrait : avec un faux
      # gh où list=feat/multi mais view=main, l'ancien code lisait « e2e : succès » (rc=0).
      # On revérifie ici sur CHAQUE lecture réussie (le head_branch d'un run ne change pas
      # pendant sa vie, donc la première lecture suffit à trancher) — sans appel gh
      # supplémentaire ni modification des bornes d'attente (deadline/max_polls/MAX_VIEW_FAILS
      # inchangées), pour ne pas rouvrir les comptages déjà calibrés des scénarios done/
      # flaky/broken juste au-dessous. Un headBranch absent (API qui ne le renverrait pas)
      # n'est pas traité comme une erreur : seule une divergence avérée doit FAIL.
      if [ -n "$s_headbranch" ] && [ "$s_headbranch" != "$emu_ref" ]; then
        echo "verdict=FAIL ref_erronee run=${run_id} attendu=${emu_ref} obtenu=${s_headbranch}"
        fail "mauvais ref : run ${run_id} sur head_branch=${s_headbranch} (attendu ${emu_ref}) — divergence list/view, jamais lu comme un succès de test"
      fi
      echo "$(date -u +%H:%M:%S) sondage ${polls}/${max_polls} (+$(( $(date +%s) - t_start ))s) run=${run_id} status=${status:-?} conclusion=${conclusion:--}"
      if [ "$status" = "completed" ] || [ "$status" = "cancelled" ] || [ -n "$conclusion" ]; then
        [ "$status" = "completed" ] || status="completed"
        break
      fi
    else
      view_fails=$(( view_fails + 1 ))
      echo "$(date -u +%H:%M:%S) sondage ${polls}/${max_polls} (+$(( $(date +%s) - t_start ))s) run=${run_id} lecture en échec (${view_fails}/${MAX_VIEW_FAILS})"
      [ "$view_fails" -lt "$MAX_VIEW_FAILS" ] \
        || fail "impossible de lire le run ${run_id} (${view_fails} échecs consécutifs)"
    fi
    sleep "$poll_step"
  done

  if [ "$status" != "completed" ] && [ "$status" != "cancelled" ]; then
    echo "verdict=timeout status=${status:-?} run=${run_id}" >&2
    echo "timeout : le run ${run_id} n'a pas fini en ${EMU_E2E_TIMEOUT_SEC}s" >&2
    exit 124
  fi

  rm -f "$EMU_INFLIGHT_FILE" 2>/dev/null || true
  echo "verdict=${conclusion:-$status} status=${status} run=${run_id}"
  [ -n "$url" ] && echo "url=${url}"

  if [ "$conclusion" = "success" ]; then
    echo "e2e : succès"
    return 0
  fi

  echo "e2e : échec (${conclusion:-$status})"
  echo "extrait des logs (tail, pas le journal complet) :"
  if ! gh_cmd run view "$run_id" -R "$EMU_REPO" --log-failed 2>/dev/null \
      | redact_stream "$token" "$EMU_LOG_TAIL" "$EMU_LOG_WIDTH"; then
    echo "(extrait indisponible)"
  fi
  return 1
}

cmd="${1:-}"
case "$cmd" in
  run|resolve-refs|status) maybe_sudo "$@" ;;
esac

case "$cmd" in
  run) run_e2e ;;
  resolve-refs) resolve_refs ;;
  status) shift; status_run "${1:-}" ;;
  prompt-block) prompt_block ;;
  append-prompt) append_prompt ;;
  *) fail "commande inconnue : ${cmd:-<vide>}" ;;
esac
