#!/usr/bin/env bash
# Lance opencode run sans jamais écrire sa sortie dans le log public du job, sous un moniteur :
#  - silence : si le run ne montre plus aucune activité pendant OC_IDLE_MIN minutes, arrêt propre
#    (code 125). L'activité n'est pas que la croissance de $OC_LOG : les fichiers de session
#    comptent aussi (un sous-agent travaille sans écrire dans le flux principal) ; le CPU ne
#    compte pas (un opencode figé garde un petit CPU de boucle d'événements).
#  - plafond : à OC_DEADLINE_EPOCH (heure absolue, marge de push prise par le workflow), arrêt
#    propre (code 124).
# Reprise après un arrêt :
#  - un `--continue` n'est plus cru sur parole : on sonde la session OC_CONTINUE_PROBE_SEC
#    secondes (3 min par défaut). Si aucun token utile n'en sort, la piste est abandonnée et une
#    session NEUVE (sans --continue) reprend avec un message qui rappelle l'état ISA / FullRun ;
#  - toute non-réponse (silence, réponse vide, erreur fournisseur, 429) bascule la reprise sur
#    OC_MODEL_FALLBACK ;
#  - chaque échec écrit une ligne `[agent-error] type=timeout|empty|provider|429` (comptée par le
#    workflow) ; jamais de secret ni de texte brut du modèle dans ces lignes.
# Arrêt propre = SIGINT au groupe de processus d'opencode et à tous ses descendants, puis SIGKILL
# après OC_KILL_GRACE secondes. La raison est décidée ici (code de sortie), jamais lue dans un
# fichier qu'opencode pourrait écrire.
# Codes : 0 ok, 124 plafond, 125 silence, 126 réponses vides épuisées, 90 environnement, sinon
# code d'opencode (124/125 d'opencode lui-même deviennent 1 pour ne pas être confondus avec une
# décision du moniteur).
set +x
set -uo pipefail
: "${ANTENLY_DIR:?}" "${OC_PROMPT_FILE:?}" "${OC_LOG:?}" "${OC_MODEL_MAIN:?}" \
  "${OC_DEADLINE_EPOCH:?}" "${OC_IDLE_MIN:?}"
OC_BIN="${OC_BIN:-opencode}"
POLL="${OC_POLL_SEC:-30}"; GRACE="${OC_KILL_GRACE:-60}"
[[ "$OC_DEADLINE_EPOCH" =~ ^[0-9]{9,11}$ ]] || { echo "OC_DEADLINE_EPOCH invalide" >&2; exit 90; }
[[ "$OC_IDLE_MIN" =~ ^[0-9]{1,3}$ ]] || { echo "OC_IDLE_MIN invalide" >&2; exit 90; }
[[ "$POLL" =~ ^[0-9]{1,3}$ && "$POLL" -ge 1 ]] || POLL=30
[[ "$GRACE" =~ ^[0-9]{1,3}$ ]] || GRACE=60
# OC_STALL_RESUMES : nombre de reprises après un arrêt (défaut min(chaîne, 6)).
# OC_CONTINUE_PROBE_SEC : durée de la sonde `--continue` (défaut 180 ; 0 = session neuve directe).
PROBE_SEC="${OC_CONTINUE_PROBE_SEC:-180}"
[[ "$PROBE_SEC" =~ ^[0-9]{1,4}$ ]] || PROBE_SEC=180
# OC_MODEL_CHAIN : liste ordonnée de modèles de secours (« opencode/...-free », séparés par des
# virgules). Compat : OC_MODEL_FALLBACK seul forme une chaîne d'un élément. Chaque élément doit
# être gratuit et différent du principal ; une chaîne vide après filtrage est une erreur
# d'environnement (90). À la reprise n° i (1-based), m = chaîne[(i-1) % longueur].
MODEL_CHAIN_RAW="${OC_MODEL_CHAIN:-${OC_MODEL_FALLBACK:-}}"
CHAIN=()
if [ -n "$MODEL_CHAIN_RAW" ]; then
  IFS=',' read -r -a _chain_raw <<<"$MODEL_CHAIN_RAW"
  for _m in "${_chain_raw[@]}"; do
    _m="${_m#"${_m%%[![:space:]]*}"}"; _m="${_m%"${_m##*[![:space:]]}"}"
    [ -n "$_m" ] || continue
    [ "$_m" = "$OC_MODEL_MAIN" ] && continue          # le secours diffère toujours du principal
    [[ "$_m" =~ ^opencode/[a-z0-9.-]+-free$ ]] || { echo "modèle de secours refusé : $_m" >&2; exit 90; }
    CHAIN+=("$_m")
  done
  unset _chain_raw _m
fi
[ "${#CHAIN[@]}" -ge 1 ] || { echo "OC_MODEL_CHAIN vide (ou réduite au principal) : aucun secours" >&2; exit 90; }
if [[ "${OC_STALL_RESUMES:-}" =~ ^[0-9]{1,2}$ ]]; then
  MAX_RESUMES="${OC_STALL_RESUMES}"
else
  MAX_RESUMES="${#CHAIN[@]}"; [ "$MAX_RESUMES" -gt 6 ] && MAX_RESUMES=6
fi
# OC_IDLE_SEC : uniquement pour les tests locaux (délai court) ; en CI, OC_IDLE_MIN fait foi.
IDLE_SEC=$(( OC_IDLE_MIN * 60 ))
[[ "${OC_IDLE_SEC:-}" =~ ^[0-9]{1,5}$ ]] && IDLE_SEC="$OC_IDLE_SEC"
# OC_SUBAGENT_IDLE_SEC : seuil propre quand un sous-agent (`task`) est en cours (défaut 480 s).
# Le flux d'opencode ne donne aucun marqueur de dispatch fiable (mesuré dans les journaux du
# 2026-11-12) : on applique donc TOUJOURS le plus court des deux seuils (documenté dans PLAN A,
# étape 1). Le motif de la dernière ligne utile ne sert plus qu'à étiqueter la cause.
SUBAGENT_IDLE_SEC="${OC_SUBAGENT_IDLE_SEC:-480}"
[[ "$SUBAGENT_IDLE_SEC" =~ ^[0-9]{1,5}$ && "$SUBAGENT_IDLE_SEC" -ge 1 ]] || SUBAGENT_IDLE_SEC=480
EFFECTIVE_IDLE="$IDLE_SEC"
[ "$SUBAGENT_IDLE_SEC" -lt "$EFFECTIVE_IDLE" ] && EFFECTIVE_IDLE="$SUBAGENT_IDLE_SEC"
cd "$ANTENLY_DIR" || exit 90
# opencode ne reçoit pas les fichiers de commandes du runner : il ne peut ni poser de variables
# ou de PATH pour les steps suivants, ni écrire dans le Summary public, ni de sorties de step.
unset GITHUB_ENV GITHUB_PATH GITHUB_OUTPUT GITHUB_STATE GITHUB_STEP_SUMMARY
PROMPT=$(cat "$OC_PROMPT_FILE")
mkdir -p "$(dirname "$OC_LOG")"
: >>"$OC_LOG"
: >>"$OC_LOG.status"
remaining() { echo $(( OC_DEADLINE_EPOCH - $(date +%s) )); }
size() { stat -c %s "$OC_LOG" 2>/dev/null || echo 0; }

# Horodatage partagé de la dernière activité (lu par progress.sh pour la colonne « silence »)
# et stockage des sessions opencode (sous-agents compris).
OC_ACT="${OC_ACT:-$OC_LOG.act}"
OC_STORE_DIR="${OC_STORE_DIR:-$HOME/.local/share/opencode}"
# Journaux internes (opencode + hooks LifeOS) : collectés après chaque passe, AJOUTÉS à
# OC_INTERNAL_LOG (défaut $OC_LOG.internal), jamais affichés. Le workflow les masque et les
# chiffre avec le même pipeline que le journal principal. OC_INTERNAL_LOG_DIR surchargeable
# pour les tests ; dossier absent = rien à collecter.
OC_INTERNAL_LOG="${OC_INTERNAL_LOG:-$OC_LOG.internal}"
OC_INTERNAL_LOG_DIR="${OC_INTERNAL_LOG_DIR:-$HOME/.local/share/opencode/log}"
OC_INTERNAL_STAMP="${OC_INTERNAL_STAMP:-$OC_LOG.internal.stamp}"
mkdir -p "$(dirname "$OC_INTERNAL_LOG")" 2>/dev/null || true
: >>"$OC_INTERNAL_LOG"
: >"$OC_INTERNAL_STAMP"
collect_internal_logs() {
  local f
  [ -d "$OC_INTERNAL_LOG_DIR" ] || return 0
  for f in "$OC_INTERNAL_LOG_DIR"/*.log; do
    [ -f "$f" ] || continue
    [ "$f" -nt "$OC_INTERNAL_STAMP" ] || continue
    { printf '\n=== %s ===\n' "$(basename "$f")"; cat "$f"; } >>"$OC_INTERNAL_LOG" 2>/dev/null || true
  done
  touch "$OC_INTERNAL_STAMP" 2>/dev/null || true
}

# Écrit une sortie ajoutée au journal depuis l'octet $1 dans le fichier $2.
delta_from() {
  local off="$1" out="$2"
  tail -c +"$(( off + 1 ))" "$OC_LOG" >"$out" 2>/dev/null || : >"$out"
}

# Vrai si la sortie ajoutée depuis l'octet $1 contient autre chose que du blanc et la bannière
# du modèle. Après un `--continue` infructueux, le journal ne contient que cette bannière
# (`> Nix/LifeOS · <modèle>`, F5/FR-14 du 2026-11-12) : ce n'est pas un token utile.
useful_from() {
  local off="$1" tmp="${OC_LOG}.delta.$$" rc
  delta_from "$off" "$tmp"
  # ANSI CSI/OSC, retours chariot, blancs et bannière retirés : reste-t-il un caractère ?
  sed -e 's/\x1b\][^\x07]*\x07//g' -e 's/\x1b\[[0-9;?]*[ -\/]*[@-~]//g' -e 's/\r//g' "$tmp" 2>/dev/null \
    | grep -vE '^[[:space:]]*>?[[:space:]]*Nix/LifeOS([[:space:]]|·|$)' \
    | grep '[^[:space:]]' >/dev/null
  # Pas de `grep -q` : sous pipefail, il sort au premier caractère, sed reçoit SIGPIPE et le
  # pipeline rend 141 dès que la sortie dépasse ~64 Ko (F5 43232258066 : succès jugé « vide »).
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

# Trace courte, sans secret ni texte du modèle, d'un échec agent. Le workflow compte ces lignes
# par type exact (timeout|empty|provider|429) dans le statut final et le JSON opencode-notify.
log_error() {
  case "$1" in timeout|empty|provider|429) ;; *) return 0 ;; esac
  printf '[agent-error] type=%s\n' "$1" >>"$OC_LOG"
  printf 'error=%s\n' "$1" >>"$OC_LOG.status"
}

# utime+stime d'un PID : champs 14 et 15 de /proc/<pid>/stat, donc indices 12 et 13 après le
# « ) » qui termine le nom de la commande.
cpu_of() {
  local s
  s=$(cat "/proc/$1/stat" 2>/dev/null) || { echo 0; return; }
  # shellcheck disable=SC2086 # champs volontairement découpés
  set -- ${s##*) }
  echo $(( ${12} + ${13} ))
}
# CPU cumulé de tout l'arbre (PID inclus) ; les processus disparus comptent 0.
cpu_tree() {
  local p total=0
  for p in "$1" $(tree "$1"); do total=$(( total + $(cpu_of "$p") )); done
  echo "$total"
}
# Activité réelle : journal qui grossit, ou fichier de session modifié depuis le dernier passage.
# Toute activité rafraîchit $OC_ACT.
active() {
  local pid="$1" cur cur_cpu
  cur=$(size); cur_cpu=$(cpu_tree "$pid")
  # Le CPU ne compte que si OC_IDLE_CPU=1 : un opencode figé (sous-agent qui ne revient pas)
  # garde un petit CPU de boucle d'événements, ce qui masquait le blocage (F5/FR-14, 2026-11-12).
  if [ "$cur" != "${LAST_SIZE:-}" ] \
     || { [ "${OC_IDLE_CPU:-0}" = 1 ] && [ "$cur_cpu" != "${LAST_CPU:-}" ]; } \
     || [ -n "$(find "$OC_STORE_DIR" -newer "$OC_ACT" -print -quit 2>/dev/null)" ]; then
    LAST_SIZE="$cur"; LAST_CPU="$cur_cpu"
    touch "$OC_ACT" 2>/dev/null
    return 0
  fi
  return 1
}

# Descendants (récursifs) d'un PID, y compris ceux qui ont changé de groupe ou de session.
tree() {
  local p c
  for p in "$@"; do
    for c in $(pgrep -P "$p" 2>/dev/null); do echo "$c"; tree "$c"; done
  done
}
# Signal au groupe d'opencode + à chaque descendant connu (instantané pris avant le signal).
sig() {
  local s="$1" pid="$2" pgid="$3"; shift 3
  [ -n "$pgid" ] && kill -s "$s" -- "-$pgid" 2>/dev/null
  # shellcheck disable=SC2068 # liste de PID volontairement découpée
  for p in "$pid" $@; do kill -s "$s" "$p" 2>/dev/null; done
  return 0
}
alive() {
  local pgid="$1" p; shift
  [ -n "$pgid" ] && pgrep -g "$pgid" >/dev/null 2>&1 && return 0
  for p in "$@"; do kill -0 "$p" 2>/dev/null && return 0; done
  return 1
}
stop_tree() {
  local pid="$1" pgid="$2" kids t
  kids=$(tree "$pid" | sort -u | tr '\n' ' ')
  # shellcheck disable=SC2086
  sig INT "$pid" "$pgid" $kids
  t=0
  # shellcheck disable=SC2086
  while [ "$t" -lt "$GRACE" ] && alive "$pgid" "$pid" $kids; do sleep 1; t=$((t + 1)); done
  # Nouveaux descendants nés pendant la grâce compris.
  kids="$kids $(tree "$pid" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  sig KILL "$pid" "$pgid" $kids
}

# Réécrit la ligne `model:` de chaque agent opencode (Max.md compris) vers $1. Les agents lisent
# leur modèle au démarrage : sans cette réécriture, une reprise changerait Nix mais pas ses
# sous-agents. OC_AGENT_DIR surchargeable pour les tests ; dossier absent = rien à faire.
OC_AGENT_DIR="${OC_AGENT_DIR:-$HOME/.config/opencode/agent}"
rewrite_agent_models() {
  local m="$1" f
  [ -d "$OC_AGENT_DIR" ] || return 0
  for f in "$OC_AGENT_DIR"/*.md; do
    [ -f "$f" ] || continue
    sed -i -E "0,/^model: .*/s##model: ${m}#" "$f" 2>/dev/null || true
  done
}

# OC_DONE_CHECK_SEC : période des contrôles de fin (défaut 60 s). OC_DONE_IDLE_SEC : inactivité
# exigée avant de conclure « Max PASS vérifié » (défaut 180 s). OC_DONE_CHECK_BIN : chemin du
# validateur (défaut : done_check.sh à côté de ce script).
DONE_CHECK_SEC="${OC_DONE_CHECK_SEC:-60}"
[[ "$DONE_CHECK_SEC" =~ ^[0-9]{1,4}$ && "$DONE_CHECK_SEC" -ge 1 ]] || DONE_CHECK_SEC=60
DONE_IDLE_SEC="${OC_DONE_IDLE_SEC:-180}"
[[ "$DONE_IDLE_SEC" =~ ^[0-9]{1,4}$ ]] || DONE_IDLE_SEC=180
DONE_CHECK_BIN="${OC_DONE_CHECK_BIN:-}"
if [ -z "$DONE_CHECK_BIN" ]; then
  # Copie figée (root, avant opencode) prioritaire pour le moniteur ; repli local en test.
  if [ -f /opt/fullrun-tools/done_check.sh ]; then DONE_CHECK_BIN=/opt/fullrun-tools/done_check.sh
  else DONE_CHECK_BIN="$(cd "$(dirname "$0")" && pwd)/done_check.sh"; fi
fi
DONE_OK=0

# Déclenche la fin anticipée quand le validateur indépendant confirme le PASS de Max. Jamais un
# pass déduit d'un verdict manquant : c'est done_check.sh qui décide, pas la sortie du modèle.
done_check() {
  [ -f "$DONE_CHECK_BIN" ] || return 1
  OC_STORE_DIR="$OC_STORE_DIR" \
  OC_HOOKS_LOG="${OC_HOOKS_LOG:-$HOME/.local/state/opencode-lifeos/hooks.log}" \
  OC_REPORT="${OC_REPORT:-}" OC_DONE_REPO="$ANTENLY_DIR" \
  OC_ISA="${OC_ISA:-${OC_ISA_PATH:-}}" OC_DONE_VERIFY="${OC_DONE_VERIFY:-}" \
  OC_MAX_SUBAGENT="${OC_MAX_SUBAGENT:-Max}" \
    bash "$DONE_CHECK_BIN" 2>/dev/null | grep -qx 'done_check=ok'
}
maybe_finish() {
  if [ "${DONE_OK:-0}" -eq 1 ] || done_check; then
    DONE_OK=1
    echo "done_check=ok" >>"$OC_LOG.status"
    echo "arret=max_pass" >>"$OC_LOG.status"
    exit 0
  fi
}

# Lance "$@" (sortie ajoutée à $OC_LOG) dans sa propre session, surveille silence et plafond.
# Pose WATCH_RC (code d'opencode, ou 124 plafond / 125 silence) et WATCH_REASON.
# Si WATCH_PROBE_SEC > 0, la passe est aussi coupée au bout de ce délai tant qu'aucun token utile
# n'est apparu (reason=probe) : c'est la sonde qui décide si `--continue` vaut la peine.
run_watched() {
  local pid pgid last_act now reason="" LAST_SIZE LAST_CPU probe_end=0 last_done=0
  WATCH_RC=0; WATCH_REASON=""
  if [[ "${WATCH_PROBE_SEC:-0}" =~ ^[0-9]{1,4}$ ]] && [ "$WATCH_PROBE_SEC" -ge 1 ]; then
    probe_end=$(( $(date +%s) + WATCH_PROBE_SEC ))
  fi
  # --wait : si setsid devait forker, $! reste le parent qui attend opencode (jamais de faux « fini »).
  setsid --wait "$@" >>"$OC_LOG" 2>&1 </dev/null &
  pid=$!; CUR_PID=$pid; CUR_PGID=""
  # setsid exécute la commande en place (pas leader de groupe en arrière-plan) : pgid = pid.
  sleep 0.2
  pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
  [[ "$pgid" =~ ^[0-9]+$ && "$pgid" -gt 1 && "$pgid" != "$(ps -o pgid= -p $$ | tr -d ' ')" ]] || pgid=""
  CUR_PGID=$pgid
  : >>"$OC_ACT"
  LAST_SIZE=$(size); LAST_CPU=$(cpu_tree "$pid"); last_act=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    now=$(date +%s)
    if active "$pid"; then last_act="$now"; fi
    # Validateur indépendant, périodique : Max a-t-il rendu un PASS vérifiable (a/b/c/d) ?
    if [ $(( now - last_done )) -ge "$DONE_CHECK_SEC" ]; then
      last_done=$now
      if [ "${DONE_OK:-0}" -eq 0 ] && done_check; then DONE_OK=1; fi
    fi
    # PASS vérifié et session inactive : la passe s'arrête là, sans attendre le seuil de silence.
    if [ "${DONE_OK:-0}" -eq 1 ] && [ $(( now - last_act )) -ge "$DONE_IDLE_SEC" ]; then
      reason=max_pass
      break
    fi
    if [ "$probe_end" -gt 0 ]; then
      # Des tokens sont sortis : la continuation est vivante, on repasse au garde-fou normal.
      if useful_from "${ATTEMPT_START:-0}"; then
        probe_end=0
      elif [ "$now" -ge "$probe_end" ]; then
        reason=probe; break
      fi
    fi
    if [ "$now" -ge "$OC_DEADLINE_EPOCH" ]; then reason=plafond; break; fi
    if [ $(( now - last_act )) -ge "$EFFECTIVE_IDLE" ]; then
      # Étiquette seulement : le seuil appliqué est déjà le plus court des deux.
      if tail -n 20 "$OC_LOG" 2>/dev/null | grep -Eqi '(^|[^[:alnum:]_])(task|subagent|@agent)([^[:alnum:]_]|$)'; then
        reason=subagent
      else
        reason=silence
      fi
      break
    fi
    sleep "$POLL" & wait $! 2>/dev/null
  done
  if [ -n "$reason" ]; then
    WATCH_REASON="$reason"
    stop_tree "$pid" "$pgid"
    wait "$pid" 2>/dev/null
    if [ "$reason" = max_pass ]; then WATCH_RC=0
    elif [ "$reason" = plafond ]; then WATCH_RC=124
    else WATCH_RC=125; fi
    return 0
  fi
  wait "$pid"; WATCH_RC=$?
  case "$WATCH_RC" in 124|125) WATCH_RC=1 ;; esac
  # Processus laissés en fond par opencode dans son groupe : arrêtés aussi.
  [ -n "$pgid" ] && pgrep -g "$pgid" >/dev/null 2>&1 && stop_tree "$pid" "$pgid"
  return 0
}

# Une passe complète : lance opencode, mesure la sortie réellement utile et trace les échecs.
# Pose A_RC, A_USEFUL (0/1) et A_REASON. $1 = durée de sonde (0 = aucune), le reste = arguments.
run_pass() {
  local probe="$1"; shift
  local delta="${OC_LOG}.last"
  ATTEMPT_START=$(size)
  WATCH_PROBE_SEC="$probe"
  run_watched "$@"
  A_RC=$WATCH_RC; A_REASON=$WATCH_REASON
  if useful_from "$ATTEMPT_START"; then A_USEFUL=1; else A_USEFUL=0; fi
  case "$A_REASON" in
    silence) log_error timeout ;;
    subagent)
      log_error timeout
      # Un sous-agent n'a plus rien écrit : la passe est coupée au seuil court (8 min par défaut).
      printf 'subagent_timeout=1\n' >>"$OC_LOG.status"
      ;;
    probe) ;; # coupure volontaire : l'absence de token est le constat (type empty ci-dessous)
    max_pass) ;; # fin anticipée : pass confirmé par done_check.sh, pas par le modèle
  esac
  if [ "$A_USEFUL" -eq 0 ] && [ "$A_REASON" != max_pass ]; then
    log_error empty
  fi
  # 429 / limite d'usage : uniquement dans la sortie de CETTE passe (pas un 429 périmé).
  if [ "$A_RC" -ne 0 ] && [ "$A_RC" -ne 124 ] && [ "$A_RC" -ne 125 ]; then
    delta_from "$ATTEMPT_START" "$delta"
    if grep -qiE '\b429\b|too many requests|rate.?limit|usage limit' "$delta"; then
      log_error 429
    else
      log_error provider
    fi
    rm -f "$delta"
  fi
  collect_internal_logs
  return 0
}

# Annulation du run (SIGINT/SIGTERM du runner) : opencode est dans sa propre session, on
# l'arrête donc nous-mêmes pour que les steps de rapport et de push trouvent un dépôt stable.
CUR_PID=""; CUR_PGID=""
# shellcheck disable=SC2317 # appelée par trap
on_cancel() {
  trap '' INT TERM HUP
  # Le runner envoie SIGKILL ~10 s après l'annulation : grâce courte.
  GRACE=5
  [ -n "$CUR_PID" ] && stop_tree "$CUR_PID" "$CUR_PGID"
  echo "arret=annulation" >>"$OC_LOG.status"
  exit 130
}
trap on_cancel INT TERM HUP

WATCH_RC=0
WATCH_REASON=""
ATTEMPT_START=0

# --- Passe principale ---
run_pass 0 "$OC_BIN" run --model "$OC_MODEL_MAIN" --title "${OC_JOB:-fullrun}" "$PROMPT"
rc=$A_RC; useful=$A_USEFUL
echo "main_rc=$rc" >>"$OC_LOG.status"
maybe_finish

need_resume=0
case "$rc" in
  124|130) ;;                      # plafond / annulation : pas de reprise
  0) [ "$useful" -eq 1 ] || need_resume=1 ;;  # rc 0 mais aucun token : réponse vide
  *) need_resume=1 ;;               # 125 silence, 429, provider…
esac

# --- Reprises : sonde --continue puis session neuve, modèle de repli ---
STALLS=0
while [ "$need_resume" -eq 1 ] && [ "$STALLS" -lt "$MAX_RESUMES" ] && [ "$(remaining)" -gt 900 ]; do
  STALLS=$((STALLS + 1))
  m="${CHAIN[$(( (STALLS - 1) % ${#CHAIN[@]} ))]}"
  printf '\n[stall] silence %s min, reprise %s/%s\n' "$(( EFFECTIVE_IDLE / 60 ))" "$STALLS" "$MAX_RESUMES" >>"$OC_LOG"
  echo "stall_resume=$STALLS" >>"$OC_LOG.status"
  echo "fallback=$m" >>"$OC_LOG.status"
  rewrite_agent_models "$m"
  probe_msg="Reprends exactement où tu t'es arrêté. Le dernier agent lancé n'a rien rendu pendant $(( EFFECTIVE_IDLE / 60 )) min et a été coupé ; son verdict est MANQUANT (jamais un pass). Relis le contexte CI ci-dessus et ${OC_REPORT:-le rapport} s'il existe, puis continue le FullRun dans l'ordre des étapes, sans sauter de porte."
  new_msg="Reprise FullRun après blocage — ceci est une NOUVELLE session, ne t'appuie pas sur la session précédente. Relis le contexte CI, ${OC_REPORT:-le rapport} s'il existe, l'état ISA / FullRun et l'étape courante, puis reprends le FullRun dans l'ordre, sans sauter de porte : un verdict manquant n'est jamais un pass."
  if [ "$PROBE_SEC" -ge 1 ]; then
    OC_MODEL_MAIN="$m" run_pass "$PROBE_SEC" "$OC_BIN" run --continue --model "$m" "$probe_msg"
    rc=$A_RC; useful=$A_USEFUL
    echo "stall_rc=$rc" >>"$OC_LOG.status"
  else
    printf '[stall] sonde --continue désactivée, session neuve directe\n' >>"$OC_LOG"
    rc=125; useful=0
  fi
  # `--continue` reste muet (bannière seule, aucun token utile) : on abandonne cette piste et
  # on ouvre une session neuve avec le message de reprise complet.
  if [ "$useful" -eq 0 ]; then
    printf '[stall] --continue sans token utile, nouvelle session\n' >>"$OC_LOG"
    echo "new_session=$STALLS" >>"$OC_LOG.status"
    OC_MODEL_MAIN="$m" run_pass 0 "$OC_BIN" run --model "$m" \
      --title "${OC_JOB:-fullrun}-reprise-$STALLS" "$new_msg"
    rc=$A_RC; useful=$A_USEFUL
    echo "new_rc=$rc" >>"$OC_LOG.status"
  fi
  maybe_finish
  need_resume=0
  case "$rc" in
    124|130) ;;
    0) [ "$useful" -eq 1 ] || need_resume=1 ;;
    *) need_resume=1 ;;
  esac
done

# Une chaîne de réponses vides ne doit jamais rendre 0 (verdict manquant ≠ pass).
if [ "$rc" -eq 0 ] && [ "$useful" -eq 0 ]; then rc=126; fi
case "$rc" in
  124) echo "arret=plafond" >>"$OC_LOG.status" ;;
  125) echo "arret=silence" >>"$OC_LOG.status" ;;
  126) echo "arret=vide" >>"$OC_LOG.status" ;;
  130) echo "arret=annulation" >>"$OC_LOG.status" ;;
esac
exit "$rc"
