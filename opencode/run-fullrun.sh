#!/usr/bin/env bash
# Lance opencode run sans jamais écrire sa sortie dans le log public du job, sous un moniteur :
#  - silence : si le run ne montre plus aucune activité pendant OC_IDLE_MIN minutes, arrêt propre
#    (code 125). L'activité n'est pas que la croissance de $OC_LOG : le CPU cumulé de l'arbre
#    d'opencode et les fichiers de session comptent aussi (un sous-agent travaille sans écrire
#    dans le flux principal) ;
#  - plafond : à OC_DEADLINE_EPOCH (heure absolue, marge de push prise par le workflow), arrêt
#    propre (code 124).
# Arrêt propre = SIGINT au groupe de processus d'opencode et à tous ses descendants, puis SIGKILL
# après OC_KILL_GRACE secondes. La raison est décidée ici (code de sortie), jamais lue dans un
# fichier qu'opencode pourrait écrire.
# Repli sur $OC_MODEL_FALLBACK seulement si la passe principale échoue d'elle-même sur un 429 /
# limite d'usage (jamais après un arrêt silence ou plafond).
# Codes : 0 ok, 124 plafond, 125 silence, 90 environnement, sinon code d'opencode (124/125 d'opencode
# lui-même deviennent 1 pour ne pas être confondus avec une décision du moniteur).
set +x
set -uo pipefail
: "${ANTENLY_DIR:?}" "${OC_PROMPT_FILE:?}" "${OC_LOG:?}" "${OC_MODEL_MAIN:?}" "${OC_MODEL_FALLBACK:?}" \
  "${OC_DEADLINE_EPOCH:?}" "${OC_IDLE_MIN:?}"
OC_BIN="${OC_BIN:-opencode}"
POLL="${OC_POLL_SEC:-30}"; GRACE="${OC_KILL_GRACE:-60}"
[[ "$OC_DEADLINE_EPOCH" =~ ^[0-9]{9,11}$ ]] || { echo "OC_DEADLINE_EPOCH invalide" >&2; exit 90; }
[[ "$OC_IDLE_MIN" =~ ^[0-9]{1,3}$ ]] || { echo "OC_IDLE_MIN invalide" >&2; exit 90; }
[[ "$POLL" =~ ^[0-9]{1,3}$ && "$POLL" -ge 1 ]] || POLL=30
[[ "$GRACE" =~ ^[0-9]{1,3}$ ]] || GRACE=60
# OC_IDLE_SEC : uniquement pour les tests locaux (délai court) ; en CI, OC_IDLE_MIN fait foi.
IDLE_SEC=$(( OC_IDLE_MIN * 60 ))
[[ "${OC_IDLE_SEC:-}" =~ ^[0-9]{1,5}$ ]] && IDLE_SEC="$OC_IDLE_SEC"
cd "$ANTENLY_DIR" || exit 90
# opencode ne reçoit pas les fichiers de commandes du runner : il ne peut ni poser de variables
# ou de PATH pour les steps suivants, ni écrire dans le Summary public, ni de sorties de step.
unset GITHUB_ENV GITHUB_PATH GITHUB_OUTPUT GITHUB_STATE GITHUB_STEP_SUMMARY
PROMPT=$(cat "$OC_PROMPT_FILE")
mkdir -p "$(dirname "$OC_LOG")"
: >>"$OC_LOG"
remaining() { echo $(( OC_DEADLINE_EPOCH - $(date +%s) )); }
size() { stat -c %s "$OC_LOG" 2>/dev/null || echo 0; }

# Horodatage partagé de la dernière activité (lu par progress.sh pour la colonne « silence »)
# et stockage des sessions opencode (sous-agents compris).
OC_ACT="${OC_ACT:-$OC_LOG.act}"
OC_STORE_DIR="${OC_STORE_DIR:-$HOME/.local/share/opencode}"

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
# Activité réelle : journal qui grossit, CPU de l'arbre qui bouge, ou fichier de session modifié
# depuis le dernier passage. Toute activité rafraîchit $OC_ACT.
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

# Lance "$@" (sortie ajoutée à $OC_LOG) dans sa propre session, surveille silence et plafond.
# Pose WATCH_RC (code d'opencode, ou 124 plafond / 125 silence).
run_watched() {
  local pid pgid last_act now reason="" LAST_SIZE LAST_CPU
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
    if [ "$now" -ge "$OC_DEADLINE_EPOCH" ]; then reason=plafond; break; fi
    if [ $(( now - last_act )) -ge "$IDLE_SEC" ]; then reason=silence; break; fi
    sleep "$POLL" & wait $! 2>/dev/null
  done
  if [ -n "$reason" ]; then
    stop_tree "$pid" "$pgid"
    wait "$pid" 2>/dev/null
    if [ "$reason" = plafond ]; then WATCH_RC=124; else WATCH_RC=125; fi
    return 0
  fi
  wait "$pid"; WATCH_RC=$?
  case "$WATCH_RC" in 124|125) WATCH_RC=1 ;; esac
  # Processus laissés en fond par opencode dans son groupe : arrêtés aussi.
  [ -n "$pgid" ] && pgrep -g "$pgid" >/dev/null 2>&1 && stop_tree "$pid" "$pgid"
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
run_watched "$OC_BIN" run --model "$OC_MODEL_MAIN" --title "${OC_JOB:-fullrun}" "$PROMPT"
rc=$WATCH_RC
echo "main_rc=$rc" >"$OC_LOG.status"

if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 125 ] && [ "$(remaining)" -gt 600 ] \
   && grep -qiE '\b429\b|too many requests|rate.?limit|usage limit' "$OC_LOG"; then
  echo "fallback=1" >>"$OC_LOG.status"
  run_watched "$OC_BIN" run --continue --model "$OC_MODEL_FALLBACK" \
    "Reprends exactement où tu t'es arrêté (le modèle précédent a reçu un 429). Relis le contexte CI ci-dessus et ${OC_REPORT:-le rapport} si présent."
  rc=$WATCH_RC
  echo "fallback_rc=$rc" >>"$OC_LOG.status"
fi
# Agent figé : silence -> on coupe et on reprend la même session (au plus OC_STALL_RESUMES fois),
# en disant à l'agent principal que le dernier agent lancé n'a pas répondu. Jamais compté comme verdict.
STALLS=0
while [ "$rc" -eq 125 ] && [ "$STALLS" -lt "${OC_STALL_RESUMES:-3}" ] && [ "$(remaining)" -gt 900 ]; do
  STALLS=$((STALLS + 1))
  printf '\n[stall] silence %s min, reprise %s/%s\n' "$(( IDLE_SEC / 60 ))" "$STALLS" "${OC_STALL_RESUMES:-3}" >>"$OC_LOG"
  echo "stall_resume=$STALLS" >>"$OC_LOG.status"
  run_watched "$OC_BIN" run --continue --model "$OC_MODEL_MAIN" \
    "[agent-error] type=timeout : le dernier agent lancé n'a rien rendu pendant $(( IDLE_SEC / 60 )) min, il a été coupé. Son verdict est MANQUANT (jamais un pass). Relance cette même tâche une fois ; si elle se bloque encore, note le verdict manquant dans le rapport et continue le FullRun dans l'ordre des étapes, sans sauter de porte."
  rc=$WATCH_RC
  echo "stall_rc=$rc" >>"$OC_LOG.status"
done
case "$rc" in 124) echo "arret=plafond" >>"$OC_LOG.status" ;; 125) echo "arret=silence" >>"$OC_LOG.status" ;; esac
exit "$rc"
