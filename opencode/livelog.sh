#!/usr/bin/env bash
# Journal en direct d'un FullRun : instantané du journal opencode, masqué, poussé sur la branche
# PRIVÉE fullrun-logs/<job>-<run> d'antenly (jamais la branche de travail, jamais main, jamais de
# force). Si gitleaks (ou la clé ISA) trouve encore quelque chose après masquage, l'instantané
# part chiffré avec age (destinataire de log-recipient.txt) au lieu du clair.
#   livelog.sh snapshot   un instantané (tests, et appelé par daemon)
#   livelog.sh daemon     instantané toutes les LIVE_INTERVAL s jusqu'à SIGTERM
# En CI, le démon tourne en root (lancé avant opencode) : son état, ses outils et le jeton sont
# hors de portée d'opencode sans sudo. Le jeton (ANTENLY_PUSH_TOKEN) arrive sur stdin quand
# LIVE_TOKEN_STDIN=1, reste dans une variable non exportée, n'est jamais écrit dans un fichier,
# une URL, un argument ni la sortie ; il ne passe à git que par son environnement (process root).
# Un échec d'envoi ne casse rien : essais bornés (LIVE_TRIES × LIVE_TIMEOUT s), puis on passe.
# Sortie : seulement des lignes d'état (heure, mode, résultat), aussi ajoutées à $LIVE_STATE/status.
set +x
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${LIVE_STATE:?}" "${LIVE_LOG:?}" "${LIVE_JOB:?}" "${LIVE_RUN:?}"
REMOTE="${LIVE_REMOTE:-https://github.com/LordThiouk/antenly.git}"
GL="${LIVE_GITLEAKS:-gitleaks}"
INTERVAL="${LIVE_INTERVAL:-600}"; FIRST="${LIVE_FIRST:-60}"
TRIES="${LIVE_TRIES:-2}"; TMO="${LIVE_TIMEOUT:-60}"
[[ "$INTERVAL" =~ ^[0-9]{1,5}$ && "$INTERVAL" -ge 1 ]] || INTERVAL=600
[[ "$FIRST" =~ ^[0-9]{1,5}$ ]] || FIRST=60
[[ "$TRIES" =~ ^[1-5]$ ]] || TRIES=2
[[ "$TMO" =~ ^[0-9]{1,3}$ && "$TMO" -ge 5 ]] || TMO=60
[[ "$LIVE_JOB" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { echo "job invalide" >&2; exit 2; }
[[ "$LIVE_RUN" =~ ^[0-9]{1,20}$ ]] || { echo "run invalide" >&2; exit 2; }
BR="fullrun-logs/${LIVE_JOB}-${LIVE_RUN}"
PLAIN=".fullrun/logs/${LIVE_JOB}-${LIVE_RUN}.log"
ENC=".fullrun/logs/${LIVE_JOB}-${LIVE_RUN}.age"
REPO="$LIVE_STATE/repo.git"
TOKEN=""
umask 022
mkdir -p "$LIVE_STATE" || exit 3
[ -d "$REPO" ] || git init -q --bare "$REPO" >/dev/null 2>&1 || exit 3

# git sans config système ni globale ni hooks ; jamais de prompt.
g() {
  env -i PATH="${PATH}" HOME="$LIVE_STATE" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false GIT_DIR="$REPO" \
    GIT_AUTHOR_NAME=Nix GIT_AUTHOR_EMAIL=nix@antenly.local GIT_COMMITTER_NAME=Nix GIT_COMMITTER_EMAIL=nix@antenly.local \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
    git "$@" 2>/dev/null
}
say() {
  local m; m="[journal en direct] $(TZ=Africa/Dakar date '+%H:%M') Dakar · $*"
  printf '%s\n' "$m"; printf '%s\n' "$m" >> "$LIVE_STATE/status" 2>/dev/null || true
}

# push <sha> : non forcé, essais bornés. Jeton passé à git par l'environnement du seul process
# git (en-tête http.extraheader limité à https://github.com/), jamais en argument ni dans l'URL.
push() {
  local sha="$1" i auth="" n=1
  [ -n "$TOKEN" ] && auth=$(printf 'x-access-token:%s' "$TOKEN" | base64 -w0)
  for (( i = 1; i <= TRIES; i++ )); do
    if [ -n "$auth" ]; then
      env -i PATH="${PATH}" HOME="$LIVE_STATE" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false GIT_DIR="$REPO" GIT_CONFIG_COUNT=2 \
        GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
        GIT_CONFIG_KEY_1=http.https://github.com/.extraheader GIT_CONFIG_VALUE_1="AUTHORIZATION: basic $auth" \
        timeout -k 5 "$TMO" git push --no-verify --porcelain "$REMOTE" "$sha:refs/heads/$BR" >/dev/null 2>&1 && return 0
    else
      timeout -k 5 "$TMO" env -i PATH="${PATH}" HOME="$LIVE_STATE" GIT_CONFIG_GLOBAL=/dev/null \
        GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false GIT_DIR="$REPO" \
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
        git push --no-verify --porcelain "$REMOTE" "$sha:refs/heads/$BR" >/dev/null 2>&1 && return 0
    fi
    [ "$i" -lt "$TRIES" ] && sleep $(( n * 5 )) && n=$(( n + 1 ))
  done
  return 1
}

# Copie du journal brut avec les droits de l'utilisateur du run (LIVE_READ_UID/GID) : opencode
# pourrait remplacer le fichier par un lien vers un fichier réservé à root.
read_log() {
  if [ "$(id -u)" = 0 ]; then
    [[ "${LIVE_READ_UID:-}" =~ ^[1-9][0-9]{0,6}$ && "${LIVE_READ_GID:-}" =~ ^[0-9]{1,7}$ ]] || return 1
    setpriv --reuid="$LIVE_READ_UID" --regid="$LIVE_READ_GID" --clear-groups --no-new-privs \
      cat -- "$LIVE_LOG" > "$1" 2>/dev/null
  else
    cat -- "$LIVE_LOG" > "$1" 2>/dev/null
  fi
}

snapshot() {
  local w raw red mode file f blob tree parent="" sha rc key="${LIVE_ISA_KEY_FILE:-/dev/null}" cfg=()
  w=$(mktemp -d "$LIVE_STATE/work.XXXXXX") || { say "échec (dossier de travail)"; return 0; }
  chmod 0700 "$w"
  raw="$w/raw.log"; red="$w/snap.log"
  if ! read_log "$raw" || [ ! -s "$raw" ]; then rm -rf "$w"; say "rien à envoyer (journal vide ou illisible)"; return 0; fi
  if ! OC_ISA_KEY_FILE="$key" OC_LOG_MAX="${LIVE_MAX:-5242880}" "$here/redact-log.sh" "$raw" "$red"; then
    rm -rf "$w"; say "échec (masquage)"; return 0
  fi
  rm -f "$raw"
  # gitleaks en mode fichier, valeurs masquées dans le rapport ; tout code ≠ 0 = chiffrer.
  [ -n "${LIVE_GL_CONFIG:-}" ] && [ -s "$LIVE_GL_CONFIG" ] && cfg=(--config "$LIVE_GL_CONFIG")
  rc=0
  "$GL" dir "${cfg[@]}" --no-banner --redact --exit-code 1 --report-path "$w/gitleaks.json" "$red" \
    >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && [ -s "$key" ] && [ "$(tr -d ' \t\r\n' < "$key" | wc -c)" -ge 32 ] \
     && grep -qiF -- "$(tr -d ' \t\r\n' < "$key")" "$red"; then rc=2; fi
  if [ "$rc" -eq 0 ]; then
    mode="clair"; file="$PLAIN"
    blob=$(g hash-object -w --no-filters "$red") || { rm -rf "$w"; say "échec (git)"; return 0; }
  else
    mode="chiffré"; file="$ENC"
    if ! f=$("$here/leaklog.sh" "$red" "$w/gitleaks.json" "$LIVE_JOB" "$LIVE_RUN" "$w/out" \
               "live-gitleaks" "" "" "" 2>/dev/null) || [ ! -s "$f" ]; then
      rm -rf "$w"; say "instantané non envoyé (secret probable et chiffrement impossible)"; return 0
    fi
    blob=$(g hash-object -w --no-filters "$f") || { rm -rf "$w"; say "échec (git)"; return 0; }
  fi
  rm -f "$red"
  # Un seul fichier par commit : l'instantané remplace le précédent (clair ou chiffré).
  if ! { tree=$(printf '100644 blob %s\t%s\n' "$blob" "${file##*/}" | g mktree) \
         && tree=$(printf '040000 tree %s\tlogs\n' "$tree" | g mktree) \
         && tree=$(printf '040000 tree %s\t.fullrun\n' "$tree" | g mktree); }; then
    rm -rf "$w"; say "échec (arbre git)"; return 0
  fi
  [ -s "$LIVE_STATE/tip" ] && parent=$(tr -dc '0-9a-f' < "$LIVE_STATE/tip")
  if ! [[ "$parent" =~ ^[0-9a-f]{40}$ ]] || ! g cat-file -e "$parent^{commit}" 2>/dev/null; then parent=""; fi
  sha=$(g commit-tree "$tree" ${parent:+-p "$parent"} \
        -m "chore(ci): journal en direct du run $LIVE_JOB ($LIVE_RUN), $(TZ=Africa/Dakar date '+%H:%M') Dakar, $mode — branche à supprimer après lecture") \
    || { rm -rf "$w"; say "échec (commit)"; return 0; }
  g update-ref refs/heads/live "$sha" >/dev/null 2>&1 || true
  printf '%s\n' "$sha" > "$LIVE_STATE/tip.tmp" && mv -f "$LIVE_STATE/tip.tmp" "$LIVE_STATE/tip"
  # Paquet lisible par l'étape de contrôle (non root) : le journal de fin se pose dessus.
  g bundle create "$LIVE_STATE/live.bundle.tmp" refs/heads/live >/dev/null 2>&1 \
    && chmod 0644 "$LIVE_STATE/live.bundle.tmp" && mv -f "$LIVE_STATE/live.bundle.tmp" "$LIVE_STATE/live.bundle"
  rm -rf "$w"
  if push "$sha"; then say "envoyé ($mode) sur $BR"; else say "envoi impossible ($mode), on réessaie au prochain passage"; fi
  return 0
}

case "${1:-}" in
  snapshot)
    if [ "${LIVE_TOKEN_STDIN:-0}" = 1 ]; then IFS= read -r TOKEN || true; exec 0</dev/null; fi
    snapshot ;;
  daemon)
    if [ "${LIVE_TOKEN_STDIN:-0}" = 1 ]; then IFS= read -r TOKEN || true; exec 0</dev/null; fi
    stop=0; sp=""
    trap 'stop=1; [ -n "$sp" ] && kill "$sp" 2>/dev/null' TERM INT HUP
    printf '%s\n' "$$" > "$LIVE_STATE/pid"
    say "démarré (toutes les ${INTERVAL} s) → $BR"
    delay="$FIRST"
    while [ "$stop" = 0 ]; do
      sleep "$delay" & sp=$!; wait "$sp" 2>/dev/null; sp=""
      [ "$stop" = 0 ] || break
      snapshot
      delay="$INTERVAL"
    done
    say "arrêté" ;;
  *) echo "usage: livelog.sh snapshot|daemon" >&2; exit 2 ;;
esac
