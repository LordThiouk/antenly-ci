#!/usr/bin/env bash
# Lance opencode run sans jamais écrire sa sortie dans le log public du job, sous un moniteur :
#  - silence : si le run ne montre plus aucune activité pendant OC_IDLE_MIN minutes, arrêt propre
#    (code 125). L'activité n'est pas que la croissance de $OC_LOG : les fichiers de session
#    comptent aussi (un sous-agent travaille sans écrire dans le flux principal) ; le CPU ne
#    compte pas (un opencode figé garde un petit CPU de boucle d'événements).
#  - erreur agent puis silence : dès qu'une ligne `[agent-error] type=timeout|empty|provider` paraît
#    dans la passe, l'absence d'activité pendant OC_ERROR_IDLE_SEC (240 s par défaut) coupe la passe
#    et déclenche le MÊME repli que le silence (même MAX_RESUMES, même `fallback=`). Indispensable en
#    chaîne : le seuil normal de 20 min y consomme tout le temps restant avant le push. type=429 est
#    exclu — le quota garde son comportement (repli au code de sortie, jamais une coupure anticipée).
#  - plafond : à OC_DEADLINE_EPOCH (heure absolue, marge de push prise par le workflow), arrêt
#    propre (code 124).
# Reprise après un arrêt :
#  - un `--continue` n'est plus cru sur parole : on sonde la session OC_CONTINUE_PROBE_SEC
#    secondes (3 min par défaut). Si aucun token utile n'en sort, la piste est abandonnée et une
#    session NEUVE (sans --continue) reprend avec un message qui rappelle l'état ISA / FullRun ;
#  - le secours est une CHAÎNE (OC_MODEL_CHAIN, séparée par des virgules, renseignée par le garde du
#    workflow). À la reprise n° i, m = chaîne[(i-1) % longueur], passé en `--model` ET en OC_MODEL_MAIN,
#    puis réécrit dans $OC_AGENT_DIR/*.md pour que les sous-agents changent aussi ; chaque élément
#    doit être `opencode/...-free` et différer du principal (sinon code 90) ;
#  - sous-agent muet : le seuil de base est OC_IDLE_MIN*60 (le plafond OC_SUBAGENT_IDLE_SEC, ex. 480 s,
#    ne s'applique que s'il est posé explicitement et le raccourcit alors) ; un seuil PAR AGENT plus long
#    (OC_AGENT_IDLE_MIN, défaut Forge=40) prolonge l'attente de l'agent en cours, jamais l'inverse ; la
#    coupure écrit `type=timeout` + `subagent_timeout=1` (verdict MANQUANT, jamais un pass) ;
#  - fin anticipée : done_check.sh (copie figée /opt/fullrun-tools) vérifie Max PASS réel,
#    hooks.log, vérificateurs OC_DONE_VERIFY, arbre propre et REPORT.md ; si ok et session inactive
#    depuis OC_DONE_IDLE_SEC (180 s) : `arret=max_pass`, exit 0, aucune reprise ;
#  - fin de tour : un `rc=0` d'opencode signifie « le tour est fini », PAS « le run est terminé ».
#    Sans PASS de Max vérifié par done_check.sh, la passe est une reprise (`arret=tour-fini`) :
#    une session neuve relit l'ISA et continue au lieu d'attendre une réponse humaine ;
#  - reprises épuisées sans PASS : exit 127, jamais 0 ;
#  - chaque échec écrit une ligne `[agent-error] type=timeout|empty|provider|429` (comptée par le
#    workflow) ; jamais de secret ni de texte brut du modèle dans ces lignes.
# Arrêt propre = SIGINT au groupe de processus d'opencode et à tous ses descendants, puis SIGKILL
# après OC_KILL_GRACE secondes. La raison est décidée ici (code de sortie), jamais lue dans un
# fichier qu'opencode pourrait écrire.
# Codes : 0 ok (dont `arret=max_pass`), 124 plafond, 125 silence ou sous-agent muet, 126 réponses
# vides épuisées, 127 fin de tour sans PASS (reprises épuisées), 90 environnement, 130 annulation ;
# sinon code d'opencode (124/125 d'opencode lui-même deviennent 1 pour ne pas être confondus avec
# une décision du moniteur).
#
# Variables obligatoires : ANTENLY_DIR, OC_PROMPT_FILE, OC_LOG, OC_MODEL_MAIN, OC_DEADLINE_EPOCH,
# OC_IDLE_MIN. Optionnelles : OC_BIN, OC_POLL_SEC, OC_KILL_GRACE, OC_IDLE_SEC (tests),
# OC_ERROR_IDLE_SEC, OC_SUBAGENT_IDLE_SEC, OC_STALL_RESUMES, OC_CONTINUE_PROBE_SEC, OC_MODEL_CHAIN,
# OC_STORE_DIR, OC_AGENT_DIR, OC_INTERNAL_LOG,
# OC_INTERNAL_LOG_DIR, OC_HOOKS_LOG, OC_DONE_VERIFY, OC_ISA/OC_ISA_PATH, OC_REPORT,
# OC_DONE_CHECK_SEC, OC_DONE_IDLE_SEC, OC_DONE_CHECK_BIN, OC_IDLE_CPU.
# Statut ($OC_LOG.status) : main_rc, stall_resume, fallback=<modèle>, stall_rc, new_session,
# new_rc, error=<type>, subagent_timeout, done_check=ok,
# arret=max_pass|tour-fini|plafond|silence|vide|annulation.
#
# Signal « vrai FullRun » : le wrapper exporte LIFEOS_FULLRUN=1 dans son propre environnement
# avant de lancer opencode. Ce signal n'est pas falsifiable par l'agent : il vit dans l'env du
# processus opencode démarré ici, pas dans un fichier ni dans un `export` d'outil bash (le plugin
# est déjà chargé). Un job qui n'appelle pas ce wrapper ne l'a donc pas. On ne pose jamais
# FULLRUN_OFF. LIFEOS_HOOK_PROFILE=fullrun est posé par défaut s'il est absent.
set +x
set -uo pipefail
export LIFEOS_FULLRUN=1
export LIFEOS_HOOK_PROFILE="${LIFEOS_HOOK_PROFILE:-fullrun}"
: "${ANTENLY_DIR:?}" "${OC_PROMPT_FILE:?}" "${OC_LOG:?}" "${OC_MODEL_MAIN:?}" \
  "${OC_DEADLINE_EPOCH:?}" "${OC_IDLE_MIN:?}"
OC_BIN="${OC_BIN:-opencode}"
POLL="${OC_POLL_SEC:-30}"; GRACE="${OC_KILL_GRACE:-60}"
# Sous-agents qui échouent en « timed out » côté opencode : le principal continue, mais avec le MÊME modèle
# (peut-être saturé ou sans quota). Au bout de OC_SUBAGENT_FAIL_MAX échecs dans une passe (défaut 2 ; 0 =
# désactivé), la passe est coupée et la reprise change de modèle pour tous les agents, comme pour un silence.
SUBFAIL_MAX="${OC_SUBAGENT_FAIL_MAX:-2}"
[[ "$SUBFAIL_MAX" =~ ^[0-9]{1,2}$ ]] || { echo "OC_SUBAGENT_FAIL_MAX invalide" >&2; exit 90; }
SUBFAIL_RE='Subagent failed[^[:cntrl:]]*(timed out|timeout)'
[[ "$OC_DEADLINE_EPOCH" =~ ^[0-9]{9,11}$ ]] || { echo "OC_DEADLINE_EPOCH invalide" >&2; exit 90; }
[[ "$OC_IDLE_MIN" =~ ^[0-9]{1,3}$ ]] || { echo "OC_IDLE_MIN invalide" >&2; exit 90; }
# Clé de porte : start_step demandé (input du workflow), transmis à LifeOS par l'environnement d'opencode,
# que l'agent ne peut pas modifier. C'est une demande : LifeOS ne l'ouvre que si les étapes avant sont
# prouvées. Valeur inconnue (ou deploy) = refus ici ; vide = rien n'est exporté, comportement habituel.
unset FULLRUN_START_STEP
if [ -n "${OC_START_STEP:-}" ]; then
  [[ "$OC_START_STEP" =~ ^(scaffold|completeness_pre|vera|serena|build|verify|max|close|[0-7])$ ]] \
    || { echo "OC_START_STEP invalide" >&2; exit 90; }
  export FULLRUN_START_STEP="$OC_START_STEP"
fi
# Même convention que start_step ci-dessus, pour un seul step (et un seul agent sur verify) à la
# fois : la skill FullRunWorkflow (LordThiouk/lifeos) lit ces deux variables et les passe à
# `FullRunPipeline.ts unit` via --stop-after-step/--agent. Vide = rien n'est exporté (run complet).
unset FULLRUN_STOP_AFTER_STEP FULLRUN_TARGET_AGENT
# Job borné à UNE étape : aucune reprise ne doit dérouler les étapes suivantes. La variable est
# aussi transmise à LifeOS (FullRunWorkflow lit FULLRUN_STOP_AFTER_STEP), mais la garde CI ne peut
# pas dépendre d'un agent : si la première passe ne rend pas le PASS de l'étape, le job s'arrête
# (127, tour-fini) au lieu de relancer une session qui continuerait le pipeline.
STOP_AFTER="${OC_STOP_AFTER_STEP:-}"
if [ -n "$STOP_AFTER" ]; then
  [[ "$STOP_AFTER" =~ ^(scaffold|completeness_pre|vera|serena|build|verify|max|close|[0-7])$ ]] \
    || { echo "OC_STOP_AFTER_STEP invalide" >&2; exit 90; }
  export FULLRUN_STOP_AFTER_STEP="$STOP_AFTER"
fi
if [ -n "${OC_TARGET_AGENT:-}" ]; then
  [[ "$OC_TARGET_AGENT" =~ ^[A-Za-z][A-Za-z0-9_-]{0,39}$ ]] \
    || { echo "OC_TARGET_AGENT invalide" >&2; exit 90; }
  export FULLRUN_TARGET_AGENT="$OC_TARGET_AGENT"
fi
[[ "$POLL" =~ ^[0-9]{1,3}$ && "$POLL" -ge 1 ]] || POLL=30
[[ "$GRACE" =~ ^[0-9]{1,3}$ ]] || GRACE=60
# OC_STALL_RESUMES : nombre de reprises après un arrêt (défaut min(chaîne, 6)).
# OC_CONTINUE_PROBE_SEC : durée de la sonde `--continue` (défaut 180 ; 0 = session neuve directe).
PROBE_SEC="${OC_CONTINUE_PROBE_SEC:-180}"
[[ "$PROBE_SEC" =~ ^[0-9]{1,4}$ ]] || PROBE_SEC=180
# OC_MODEL_CHAIN : liste ordonnée de modèles de secours (« opencode/...-free », séparés par des
# virgules) ; renseignée par le garde du workflow (défaut vert : mimo/iceman/nemotron/beam/hy4 si
# l'input model_chain est vide — model_fallback, l'ancien input de repli, a été retiré). Chaque
# élément doit être gratuit et différent du principal ; une chaîne vide après filtrage est une
# erreur d'environnement (90). À la reprise n° i (1-based), m = chaîne[(i-1) % longueur].
MODEL_CHAIN_RAW="${OC_MODEL_CHAIN:-}"
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
# OC_ERROR_IDLE_SEC : délai court APRÈS une erreur agent (timeout/empty/provider) sans activité ;
# 0 désactive. Seul ce délai est raccourci : le seuil de silence normal (IDLE_SEC/EFFECTIVE_IDLE) et
# le repli 429 restent intacts. Valeur invalide = environnement refusé (90), jamais avalée.
ERROR_IDLE_SEC="${OC_ERROR_IDLE_SEC:-240}"
[[ "$ERROR_IDLE_SEC" =~ ^[0-9]{1,5}$ ]] || { echo "OC_ERROR_IDLE_SEC invalide" >&2; exit 90; }
# Activité d'un sous-agent ou d'un outil lancé par l'agent : elle compte comme celle du parent
# (voir active() : fichiers de session qui bougent ; CPU des processus ENFANTS de l'agent). La
# coupure n'a donc lieu qu'après OC_IDLE_MIN minutes sans AUCUNE activité du parent ni des enfants :
# un vrai blocage reste coupé, simplement plus tard (avant : min(OC_IDLE_MIN, 8 min) quoi qu'il
# arrive, ce qui tuait un sous-agent ou un banc encore au travail). OC_SUBAGENT_IDLE_SEC reste un
# plafond OPTIONNEL : posé explicitement, il raccourcit le seuil, mais l'activité continue de
# remettre le compteur à zéro.
EFFECTIVE_IDLE="$IDLE_SEC"
SUBAGENT_IDLE_SEC="${OC_SUBAGENT_IDLE_SEC:-}"
if [[ "$SUBAGENT_IDLE_SEC" =~ ^[0-9]{1,5}$ && "$SUBAGENT_IDLE_SEC" -ge 1 && "$SUBAGENT_IDLE_SEC" -lt "$EFFECTIVE_IDLE" ]]; then
  EFFECTIVE_IDLE="$SUBAGENT_IDLE_SEC"
fi
# Seuil de silence PAR AGENT (OC_AGENT_IDLE_MIN="Forge=40,Max=30", minutes) : quand le seuil de base
# (OC_IDLE_MIN) est atteint et que l'agent en cours (task « running » dans le stockage opencode) a un seuil plus
# long, la coupure attend ce seuil. Défaut : Forge=40 (un audit sur un gros delta est plus long que 20 min).
# Les agents sans entrée gardent le seuil de base ; une valeur plus courte que la base est sans effet (le seuil
# de base reste un plancher) ; un plafond OC_SUBAGENT_IDLE_SEC posé explicitement reste maître (aucune
# extension) ; l'activité remet toujours le compteur à zéro ; le plafond du job (deadline) passe avant tout.
# Valeur invalide, doublon, agent mal nommé ou hors 1..720 min : refus (90). Variable définie mais vide =
# aucune entrée. OC_AGENT_IDLE_SEC (mêmes entrées en secondes) : uniquement pour les tests locaux.
declare -A AGENT_IDLE=()
AGENT_IDLE_UNIT=60; AGENT_IDLE_MAX=720
AGENT_IDLE_RAW="${OC_AGENT_IDLE_MIN-Forge=40}"
if [ -n "${OC_AGENT_IDLE_SEC:-}" ]; then AGENT_IDLE_RAW="$OC_AGENT_IDLE_SEC"; AGENT_IDLE_UNIT=1; AGENT_IDLE_MAX=43200; fi
if [ -n "$AGENT_IDLE_RAW" ]; then
  _agent_re='[A-Za-z][A-Za-z0-9_-]{0,39}=[0-9]{1,5}'
  [[ "$AGENT_IDLE_RAW" =~ ^${_agent_re}(,${_agent_re}){0,9}$ ]] || { echo "OC_AGENT_IDLE_MIN invalide" >&2; exit 90; }
  IFS=',' read -r -a _agent_idle <<<"$AGENT_IDLE_RAW"
  for _e in "${_agent_idle[@]}"; do
    _n="${_e%%=*}"; _v=$(( 10#${_e#*=} ))
    { [ "$_v" -ge 1 ] && [ "$_v" -le "$AGENT_IDLE_MAX" ]; } || { echo "OC_AGENT_IDLE_MIN hors limites : $_e" >&2; exit 90; }
    [ -z "${AGENT_IDLE[$_n]+x}" ] || { echo "OC_AGENT_IDLE_MIN : doublon $_n" >&2; exit 90; }
    AGENT_IDLE[$_n]=$(( _v * AGENT_IDLE_UNIT ))
  done
  unset _agent_re _agent_idle _e _n _v
fi
AGENT_RUNNING=""; AGENT_LOOKUP_AT=0; AGENT_LIMIT="$EFFECTIVE_IDLE"; AGENT_NOTED=""
# Seuil de CPU (ticks, 1/100 s) gagné par les processus enfants entre deux sondes pour compter
# comme « actifs » ; un enfant bloqué (sleep, attente réseau) n'en gagne pas.
CHILD_CPU_MIN="${OC_CHILD_CPU_MIN:-10}"
[[ "$CHILD_CPU_MIN" =~ ^[0-9]{1,6}$ ]] || CHILD_CPU_MIN=10
cd "$ANTENLY_DIR" || exit 90
# opencode ne reçoit pas les fichiers de commandes du runner : il ne peut ni poser de variables
# ou de PATH pour les steps suivants, ni écrire dans le Summary public, ni de sorties de step.
unset GITHUB_ENV GITHUB_PATH GITHUB_OUTPUT GITHUB_STATE GITHUB_STEP_SUMMARY
PROMPT=$(cat "$OC_PROMPT_FILE")
mkdir -p "$(dirname "$OC_LOG")"
: >>"$OC_LOG"
: >>"$OC_LOG.status"
for _n in "${!AGENT_IDLE[@]}"; do echo "agent_idle=$_n:${AGENT_IDLE[$_n]}" >>"$OC_LOG.status"; done; unset _n
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
# Au plus UNE ligne error= par passe : le `log_error empty` générique (sortie vide) ne doit pas
# s'ajouter à un type déjà tracé (silence, sous-agent, error_idle, 429/provider).
ERR_WRITTEN=0
log_error() {
  case "$1" in timeout|empty|provider|429) ;; *) return 0 ;; esac
  [ "$ERR_WRITTEN" -eq 0 ] || return 0
  ERR_WRITTEN=1
  printf '[agent-error] type=%s\n' "$1" >>"$OC_LOG"
  printf 'error=%s\n' "$1" >>"$OC_LOG.status"
}
# error_idle : le marqueur [agent-error] est déjà dans la passe (écrit par le plugin), on ne le
# duplique pas — seul le type réel est porté au statut, une seule fois.
log_error_status() {
  case "$1" in timeout|empty|provider|429) ;; *) return 0 ;; esac
  [ "$ERR_WRITTEN" -eq 0 ] || return 0
  ERR_WRITTEN=1
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
# PID du processus opencode réel : celui dont la ligne de commande contient le binaire et qui n'a
# aucun descendant dans ce cas (les enveloppes setsid / systemd-run / prlimit n'en sont pas).
agent_pid() {
  local root="$1" base p q cmd found
  base=$(basename "$OC_BIN")
  for p in "$root" $(tree "$root"); do
    cmd=$(tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null) || continue
    case "$cmd" in *"$base"*" run"*) ;; *) continue ;; esac
    found=0
    for q in $(tree "$p"); do
      cmd=$(tr '\0' ' ' <"/proc/$q/cmdline" 2>/dev/null) || continue
      case "$cmd" in *"$base"*" run"*) found=1; break ;; esac
    done
    [ "$found" -eq 0 ] && { echo "$p"; return 0; }
  done
  return 1
}
# CPU cumulé des seuls ENFANTS de l'agent (outils, bancs, scripts) ; le CPU d'opencode lui-même ne
# compte pas (sa boucle d'événements en garde un peu même figé).
child_cpu() {
  local a p total=0
  a=$(agent_pid "$1") || { echo 0; return; }
  for p in $(tree "$a"); do total=$(( total + $(cpu_of "$p") )); done
  echo "$total"
}
# Activité réelle : journal qui grossit, fichier de session modifié depuis le dernier passage
# (sous-agents compris), ou processus enfants de l'agent qui consomment du CPU. Toute activité
# rafraîchit $OC_ACT.
active() {
  local pid="$1" cur cur_cpu cc
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
  cc=$(child_cpu "$pid")
  if [ "$cc" -ge $(( ${LAST_CHILD_CPU:-0} + CHILD_CPU_MIN )) ]; then
    LAST_CHILD_CPU="$cc"
    touch "$OC_ACT" 2>/dev/null
    return 0
  fi
  LAST_CHILD_CPU="$cc"
  return 1
}

# --- Enveloppe mémoire ---------------------------------------------------------------
# Borne l'ensemble du processus opencode et de ses descendants à MEMCAP_BYTES (10 Go par défaut).
# Trois paliers, testés dans l'ordre : systemd-run --scope (préféré, cgroup v2 natif, MemorySwapMax=0),
# cgroup v2 direct (créé sous /sys/fs/cgroup), prlimit --as (dernier recours, par processus uniquement).
# Les démons wip/livelog tournent HORS de cette enveloppe (lancés par le workflow en root).
MEMCAP_BYTES="${MEMCAP_BYTES:-10737418240}"  # 10 Go
MEMCAP_CMD=()
MEMCAP_TYPE=""
MEMCAP_CGROUP=""

_memcap_cleanup() {
  if [ "$MEMCAP_TYPE" = "cgroup2" ] && [ -n "$MEMCAP_CGROUP" ] && [ -d "$MEMCAP_CGROUP" ]; then
    # Déplacer les processus restants vers le parent avant suppression.
    local parent; parent=$(dirname "$MEMCAP_CGROUP")
    while read -r p 2>/dev/null; do
      echo "$p" | sudo -n tee "$parent/cgroup.procs" >/dev/null 2>&1 || true
    done < "$MEMCAP_CGROUP/cgroup.procs" 2>/dev/null
    sudo -n rmdir "$MEMCAP_CGROUP" 2>/dev/null || true
  fi
}

_memcap_move_pid() {
  # Déplace $1 dans le cgroup2 de l'enveloppe (appelé juste après le fork).
  [ "$MEMCAP_TYPE" = "cgroup2" ] && [ -n "$MEMCAP_CGROUP" ] && \
    echo "$1" | sudo -n tee "$MEMCAP_CGROUP/cgroup.procs" >/dev/null 2>&1 || true
}

# Sonde : tier 1 — systemd-run --scope
if [ -z "$MEMCAP_TYPE" ]; then
  _probe=$(timeout 10 systemd-run --scope --quiet \
    -p "MemoryMax=$MEMCAP_BYTES" -p MemorySwapMax=0 \
    -- /bin/sh -c 'echo memcap_ok' 2>/dev/null || true)
  if [ "$_probe" = "memcap_ok" ]; then
    MEMCAP_CMD=(systemd-run --scope --quiet -p "MemoryMax=$MEMCAP_BYTES" -p MemorySwapMax=0 --)
    MEMCAP_TYPE="systemd"
  fi
fi
# Sonde : tier 2 — cgroup v2 direct
if [ -z "$MEMCAP_TYPE" ] && [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  _cg="/sys/fs/cgroup/fullrun-oc-$$"
  if sudo -n mkdir -p "$_cg" 2>/dev/null && \
     echo "$MEMCAP_BYTES" | sudo -n tee "$_cg/memory.max" >/dev/null 2>&1 && \
     echo 0 | sudo -n tee "$_cg/memory.swap.max" >/dev/null 2>&1; then
    MEMCAP_CGROUP="$_cg"
    MEMCAP_TYPE="cgroup2"
  else
    sudo -n rmdir "$_cg" 2>/dev/null || true
  fi
fi
# Sonde : tier 3 — prlimit --as (dernier recours, pas de swap control)
if [ -z "$MEMCAP_TYPE" ] && command -v prlimit >/dev/null 2>&1; then
  _probe=$(prlimit "--as=$MEMCAP_BYTES" -- /bin/sh -c 'echo memcap_ok' 2>/dev/null || true)
  if [ "$_probe" = "memcap_ok" ]; then
    MEMCAP_CMD=(prlimit "--as=$MEMCAP_BYTES" --)
    MEMCAP_TYPE="prlimit"
  fi
fi
# Ligne visible dans le livelog (journal $OC_LOG) et sur stderr (log de job).
_memcap_limit=""
if [ $(( MEMCAP_BYTES % 1073741824 )) -eq 0 ]; then
  _memcap_limit="$(( MEMCAP_BYTES / 1073741824 ))G"
else
  _memcap_limit="${MEMCAP_BYTES}"
fi
_memcap_mech=""
case "$MEMCAP_TYPE" in
  systemd) _memcap_mech=systemd-run ;;
  cgroup2) _memcap_mech=cgroupv2 ;;
  prlimit) _memcap_mech=prlimit ;;
esac
if [ -n "$_memcap_mech" ]; then
  printf '[memcap] mécanisme=%s limite=%s\n' "$_memcap_mech" "$_memcap_limit" | tee -a "$OC_LOG" >&2
else
  echo "[memcap] aucune enveloppe disponible (systemd-run / cgroupv2 / prlimit)" | tee -a "$OC_LOG" >&2
fi
unset _memcap_limit _memcap_mech

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
# Point d'appel unique et purgé de done_check.sh (copie figée root prioritaire, repli local en test).
if [ -f /opt/fullrun-tools/done-check-call.sh ]; then DC_CALL_LIB=/opt/fullrun-tools/done-check-call.sh
else DC_CALL_LIB="$(cd "$(dirname "$0")" && pwd)/done-check-call.sh"; fi
# shellcheck source=done-check-call.sh
# shellcheck disable=SC1091
. "$DC_CALL_LIB"
DONE_OK=0

# Déclenche la fin anticipée quand le validateur indépendant confirme le PASS de Max. Jamais un
# pass déduit d'un verdict manquant : c'est done_check.sh qui décide, pas la sortie du modèle.
done_check() {
  [ -f "$DONE_CHECK_BIN" ] || return 1
  OC_STORE_DIR="$OC_STORE_DIR" \
  OC_HOOKS_LOG="${OC_HOOKS_LOG:-$HOME/.local/state/opencode-lifeos/hooks.log}" \
  OC_REPORT="${OC_REPORT:-}" OC_DONE_REPO="$ANTENLY_DIR" \
  OC_ISA="${OC_ISA:-${OC_ISA_PATH:-}}" OC_DONE_VERIFY="${OC_DONE_VERIFY:-}" \
  OC_MAX_SUBAGENT="${OC_MAX_SUBAGENT:-Max}" OC_DONE_AGENTS="${OC_DONE_AGENTS:-}" \
  OC_DONE_AGENTS_ANY="${OC_DONE_AGENTS_ANY:-}" \
  OC_DONE_VALIDATE_ONLY="${OC_DONE_VALIDATE_ONLY:-}" \
    fullrun_done_check "$DONE_CHECK_BIN" 2>/dev/null | grep -qx 'done_check=ok'
}
maybe_finish() {
  if [ "${DONE_OK:-0}" -eq 1 ] || done_check; then
    DONE_OK=1
    echo "done_check=ok" >>"$OC_LOG.status"
    echo "arret=max_pass" >>"$OC_LOG.status"
    exit 0
  fi
}

# Agent dont une tâche (`task`) est en cours dans le stockage opencode : le plus récemment démarré. Vide si
# inconnu — alors le seuil de base s'applique, jamais une extension.
running_agent() {
  timeout 20 python3 - "$OC_STORE_DIR" <<'PY' 2>/dev/null
import glob, json, os, re, sqlite3, sys
store = sys.argv[1]
best = (-1, '')
def consider(raw):
    global best
    try:
        o = json.loads(raw)
    except Exception:
        return
    if not isinstance(o, dict) or o.get('tool') != 'task':
        return
    st = o.get('state') or {}
    if st.get('status') not in ('running', 'pending'):
        return
    a = (st.get('input') or {}).get('subagent_type')
    try:
        t = int((st.get('time') or {}).get('start') or 0)
    except Exception:
        t = 0
    if isinstance(a, str) and re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]{0,39}', a) and t >= best[0]:
        best = (t, a)
for db in glob.glob(os.path.join(store, '*.db')):
    try:
        con = sqlite3.connect('file:%s?mode=ro' % db, uri=True)
        for (data,) in con.execute('select data from part'):
            consider(data)
    except Exception:
        pass
for base in (os.path.join(store, 'storage', 'part'), os.path.join(store, 'part')):
    for f in glob.glob(os.path.join(base, '*', '*.json')):
        try:
            consider(open(f, encoding='utf-8', errors='replace').read())
        except Exception:
            pass
print(best[1])
PY
}
# Pose AGENT_LIMIT : seuil de silence applicable à cet instant (>= EFFECTIVE_IDLE, jamais plus court).
agent_limit() {
  AGENT_LIMIT="$EFFECTIVE_IDLE"
  [ "${#AGENT_IDLE[@]}" -gt 0 ] || return 0
  [ "$EFFECTIVE_IDLE" -eq "$IDLE_SEC" ] || return 0   # plafond OC_SUBAGENT_IDLE_SEC explicite : maître
  if [ $(( $1 - AGENT_LOOKUP_AT )) -ge 30 ]; then AGENT_LOOKUP_AT=$1; AGENT_RUNNING=$(running_agent | head -n1 | tr -d '\r'); fi
  [ -n "$AGENT_RUNNING" ] && [ -n "${AGENT_IDLE[$AGENT_RUNNING]+x}" ] || return 0
  if [ "${AGENT_IDLE[$AGENT_RUNNING]}" -gt "$AGENT_LIMIT" ]; then
    AGENT_LIMIT="${AGENT_IDLE[$AGENT_RUNNING]}"
    if [ "$AGENT_NOTED" != "$AGENT_RUNNING" ]; then
      AGENT_NOTED="$AGENT_RUNNING"
      echo "agent_idle_extended=$AGENT_RUNNING:$AGENT_LIMIT" >>"$OC_LOG.status"
    fi
  fi
}

# Lance "$@" (sortie ajoutée à $OC_LOG) dans sa propre session, surveille silence et plafond.
# Pose WATCH_RC (code d'opencode, ou 124 plafond / 125 silence) et WATCH_REASON.
# Si WATCH_PROBE_SEC > 0, la passe est aussi coupée au bout de ce délai tant qu'aucun token utile
# n'est apparu (reason=probe) : c'est la sonde qui décide si `--continue` vaut la peine.
run_watched() {
  local pid pgid last_act now reason="" LAST_SIZE LAST_CPU LAST_CHILD_CPU=0 probe_end=0 last_done=0 error_at=0 err
  WATCH_RC=0; WATCH_REASON=""
  if [[ "${WATCH_PROBE_SEC:-0}" =~ ^[0-9]{1,4}$ ]] && [ "$WATCH_PROBE_SEC" -ge 1 ]; then
    probe_end=$(( $(date +%s) + WATCH_PROBE_SEC ))
  fi
  # --wait : si setsid devait forker, $! reste le parent qui attend opencode (jamais de faux « fini »).
  # MEMCAP_CMD (vide si aucune enveloppe) interpose systemd-run/prlimit entre setsid et la commande.
  setsid --wait "${MEMCAP_CMD[@]}" "$@" >>"$OC_LOG" 2>&1 </dev/null &
  pid=$!; CUR_PID=$pid; CUR_PGID=""
  _memcap_move_pid "$pid"
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
    # Erreur agent écrite DANS cette passe (timeout/empty/provider — jamais 429), puis plus rien :
    # on arme un délai court, indépendant du seuil de silence normal. Une activité postérieure
    # réarme le compteur : on ne coupe que si RIEN ne suit l'erreur.
    if [ "$ERROR_IDLE_SEC" -ge 1 ]; then
      err=$(tail -c +"$(( ${ATTEMPT_START:-0} + 1 ))" "$OC_LOG" 2>/dev/null \
            | grep -a -E -m1 '^\[agent-error\] type=(timeout|empty|provider)$' || true)
      if [ -z "$err" ]; then
        error_at=0
      elif [ "$error_at" -eq 0 ] || [ "$last_act" -gt "$error_at" ]; then
        error_at="$now"
      fi
    fi
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
    if [ "$SUBFAIL_MAX" -gt 0 ] \
      && [ "$(tail -c +"$(( ${ATTEMPT_START:-0} + 1 ))" "$OC_LOG" 2>/dev/null | grep -aEc "$SUBFAIL_RE")" -ge "$SUBFAIL_MAX" ]; then
      reason=subagent_fail
      break
    fi
    # Coupure courte sur erreur agent suivie de silence : WATCH_RC=125 comme un silence, donc
    # exactement la même reprise (même MAX_RESUMES, même `fallback=<modèle>`). Le 429 n'atteint
    # jamais cette branche : son repli reste lié au code de sortie d'opencode.
    if [ "$error_at" -gt 0 ] && [ $(( now - error_at )) -ge "$ERROR_IDLE_SEC" ] \
       && [ "$last_act" -le "$error_at" ]; then
      reason=error_idle
      break
    fi
    if [ $(( now - last_act )) -ge "$EFFECTIVE_IDLE" ]; then agent_limit "$now"; fi
    if [ $(( now - last_act )) -ge "$AGENT_LIMIT" ] && [ $(( now - last_act )) -ge "$EFFECTIVE_IDLE" ]; then
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
  local delta="${OC_LOG}.last" err_type=""
  ERR_WRITTEN=0
  A_ERR_TYPE=""                 # type d'erreur de CETTE passe, lu par le message de reprise
  ATTEMPT_START=$(size)
  WATCH_PROBE_SEC="$probe"
  run_watched "$@"
  A_RC=$WATCH_RC; A_REASON=$WATCH_REASON
  if useful_from "$ATTEMPT_START"; then A_USEFUL=1; else A_USEFUL=0; fi
  case "$A_REASON" in
    silence) log_error timeout ;;
    error_idle)
      # Le marqueur est déjà dans la passe : ne pas dupliquer la ligne [agent-error]. Le statut
      # porte le type réel lu dans le journal, pour rester lisible comme une reprise sur silence.
      err_type=$(tail -c +"$(( ATTEMPT_START + 1 ))" "$OC_LOG" 2>/dev/null \
                 | grep -a -E -o -m1 'type=(timeout|empty|provider)' | cut -d= -f2 || true)
      A_ERR_TYPE="$err_type"
      [ -n "$err_type" ] && log_error_status "$err_type"
      ;;
    subagent)
      log_error timeout
      # Un sous-agent n'a plus rien écrit : la passe est coupée au seuil court (8 min par défaut).
      printf 'subagent_timeout=1\n' >>"$OC_LOG.status"
      ;;
    subagent_fail)
      log_error timeout
      printf 'subagent_timeout=1\nsubagent_fail=%s\n' "$SUBFAIL_MAX" >>"$OC_LOG.status"
      ;;
    probe) ;; # coupure volontaire : l'absence de token est le constat (type empty ci-dessous)
    max_pass) ;; # fin anticipée : pass confirmé par done_check.sh, pas par le modèle
  esac
  # 429 / limite d'usage : uniquement dans la sortie de CETTE passe (pas un 429 périmé). Classé
  # AVANT le vide générique pour que le vrai motif gagne si la passe est aussi jugée « vide ».
  if [ "$A_RC" -ne 0 ] && [ "$A_RC" -ne 124 ] && [ "$A_RC" -ne 125 ]; then
    delta_from "$ATTEMPT_START" "$delta"
    if grep -qiE '\b429\b|too many requests|rate.?limit|usage limit' "$delta"; then
      log_error 429
    else
      log_error provider
    fi
    rm -f "$delta"
  fi
  # Vide générique : seulement si aucun type n'a déjà été tracé pour cette passe (unicité error=).
  if [ "$A_USEFUL" -eq 0 ] && [ "$A_REASON" != max_pass ]; then
    log_error empty
  fi
  collect_internal_logs
  return 0
}

# Annulation du run (SIGINT/SIGTERM du runner) : opencode est dans sa propre session, on
# l'arrête donc nous-mêmes pour que les steps de rapport et de push trouvent un dépôt stable.
CUR_PID=""; CUR_PGID=""
# shellcheck disable=SC2317,SC2329 # appelée par trap
on_cancel() {
  trap '' INT TERM HUP
  # Le runner envoie SIGKILL ~10 s après l'annulation : grâce courte.
  GRACE=5
  [ -n "$CUR_PID" ] && stop_tree "$CUR_PID" "$CUR_PGID"
  _memcap_cleanup
  echo "arret=annulation" >>"$OC_LOG.status"
  exit 130
}
trap on_cancel INT TERM HUP

# Bloc injecté dans le prompt de reprise : lu à chaque reprise (le fichier évolue pendant le run).
# Copie figée (root) prioritaire, repli local en test. Jamais bloquant : sans checkpoint, texte neutre.
resume_context() {
  local bin="${OC_CHECKPOINT_BIN:-}"
  if [ -z "$bin" ]; then
    if [ -f /opt/fullrun-tools/checkpoint.sh ]; then bin=/opt/fullrun-tools/checkpoint.sh
    else bin="$(cd "$(dirname "$0")" && pwd)/checkpoint.sh"; fi
  fi
  [ -f "$bin" ] && bash "$bin" resume-text --job "${OC_JOB:-fullrun}" --repo "$ANTENLY_DIR" 2>/dev/null \
    | head -c 6000 || true
}

WATCH_RC=0
WATCH_REASON=""
ATTEMPT_START=0
A_ERR_TYPE=""

# --- Passe principale ---
run_pass 0 "$OC_BIN" run --model "$OC_MODEL_MAIN" --title "${OC_JOB:-fullrun}" "$PROMPT"
rc=$A_RC; useful=$A_USEFUL
echo "main_rc=$rc" >>"$OC_LOG.status"
maybe_finish

need_resume=0
case "$rc" in
  124|130) ;;                      # plafond / annulation : pas de reprise
  # rc 0 = « opencode a fini son tour », pas « le run a atteint son but ». Sans PASS de Max
  # vérifié par done_check.sh (maybe_finish ci-dessus), c'est une reprise : la boucle relance
  # une session qui relit l'ISA et continue, au lieu d'attendre une réponse humaine.
  0) need_resume=1 ;;
  *) need_resume=1 ;;               # 125 silence, 429, provider…
esac

# --- Reprises : sonde --continue puis session neuve, modèle de repli ---
STALLS=0
if [ -n "$STOP_AFTER" ] && [ "$need_resume" -eq 1 ]; then
  # Une reprise repartirait du point de reprise et pourrait ouvrir l'étape SUIVANTE : un job
  # borné ne le fait jamais. Le premier tour est le seul ; sans PASS de l'étape, échec nommé.
  printf '[stall] job borné à l'\''étape %s : aucune reprise (pas d'\''étape suivante)\n' "$STOP_AFTER" >>"$OC_LOG"
  echo "stop_after_no_resume=$STOP_AFTER" >>"$OC_LOG.status"
fi
while [ "$need_resume" -eq 1 ] && [ -z "$STOP_AFTER" ] && [ "$STALLS" -lt "$MAX_RESUMES" ] && [ "$(remaining)" -gt 900 ]; do
  STALLS=$((STALLS + 1))
  m="${CHAIN[$(( (STALLS - 1) % ${#CHAIN[@]} ))]}"
  printf '\n[stall] fin de tour ou silence, reprise %s/%s\n' "$STALLS" "$MAX_RESUMES" >>"$OC_LOG"
  echo "stall_resume=$STALLS" >>"$OC_LOG.status"
  echo "fallback=$m" >>"$OC_LOG.status"
  rewrite_agent_models "$m"
  # Cause réelle de la coupure : une erreur agent suivie de OC_ERROR_IDLE_SEC secondes sans
  # activité n'a RIEN à voir avec le seuil de silence normal (20 min par défaut). Le modèle doit
  # relire le bon diagnostic, sinon il cherche un blocage qui n'a pas eu lieu.
  if [ "${A_REASON:-}" = error_idle ]; then
    probe_msg="Reprends exactement où tu t'es arrêté. Le dernier agent lancé a signalé une erreur de type ${A_ERR_TYPE:-inconnu}, puis est resté sans activité ${ERROR_IDLE_SEC} s (OC_ERROR_IDLE_SEC) ; il a été coupé ; son verdict est MANQUANT (jamais un pass). Relis le contexte CI ci-dessus et ${OC_REPORT:-le rapport} s'il existe, puis continue le FullRun dans l'ordre des étapes, sans sauter de porte."
  else
    probe_msg="Reprends exactement où tu t'es arrêté. Le dernier agent lancé n'a rien rendu pendant $(( EFFECTIVE_IDLE / 60 )) min et a été coupé ; son verdict est MANQUANT (jamais un pass). Relis le contexte CI ci-dessus et ${OC_REPORT:-le rapport} s'il existe, puis continue le FullRun dans l'ordre des étapes, sans sauter de porte."
  fi
  new_msg="Reprise FullRun après blocage — ceci est une NOUVELLE session, ne t'appuie pas sur la session précédente. Relis le contexte CI, ${OC_REPORT:-le rapport} s'il existe, l'état ISA / FullRun et l'étape courante, puis reprends le FullRun dans l'ordre, sans sauter de porte : un verdict manquant n'est jamais un pass."
  # Point de reprise : étape suivante et verdicts déjà obtenus (voir checkpoint.sh). Une reprise
  # repart de là ; elle ne refait ni les étapes validées ni les verdicts encore valables.
  ctx=$(resume_context)
  probe_msg="$probe_msg

$ctx"
  new_msg="$new_msg

$ctx"
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
    0) need_resume=1 ;;              # tour fini sans PASS vérifié : encore une reprise
    *) need_resume=1 ;;
  esac
done

# Une chaîne de réponses vides ne doit jamais rendre 0 (verdict manquant ≠ pass).
if [ "$rc" -eq 0 ] && [ "$useful" -eq 0 ]; then rc=126; fi
# Une fin de tour sans PASS ne doit jamais rendre 0, même après épuisement des reprises :
# « terminé » exige done_check=ok, et cet exit 0 court-circuitait toute la chaîne de reprise.
if [ "$rc" -eq 0 ] && [ "$need_resume" -eq 1 ]; then rc=127; fi
case "$rc" in
  124) echo "arret=plafond" >>"$OC_LOG.status" ;;
  125) echo "arret=silence" >>"$OC_LOG.status" ;;
  126) echo "arret=vide" >>"$OC_LOG.status" ;;
  127) echo "arret=tour-fini" >>"$OC_LOG.status" ;;
  130) echo "arret=annulation" >>"$OC_LOG.status" ;;
esac
_memcap_cleanup
exit "$rc"
