#!/usr/bin/env bash
# Push périodique des commits wip pendant un FullRun : un commit local n'est plus perdu si le run
# est annulé ou si le contrôle final refuse le push. Modèle du journal en direct (livelog.sh) :
# démon root lancé AVANT opencode, jeton sur stdin (jamais dans l'environnement d'opencode, un
# fichier, une URL ou un argument), outils figés en root.
#   wippush.sh once    un passage (tests, et appelé par daemon)
#   wippush.sh daemon  passages toutes les IN_WIP_PUSH_MIN minutes (défaut 30) jusqu'à SIGTERM
# Chaque passage : si la branche de travail a de nouveaux commits depuis le dernier push, scanner
# la plage dernier-poussé..HEAD avec gitleaks (copie figée, config et ignores du BASE_SHA) puis avec
# le contrôle de clé ISA ; si propre, pousser la branche seulement (jamais main, jamais force, un
# non-fast-forward est refusé par git) ; sinon écrire une ligne [suivi] et réessayer au passage
# suivant. Ne sort jamais de valeur de secret. N'échoue jamais le run : tout échec est une ligne
# [suivi] et le prochain passage rattrape.
# Sortie : uniquement des lignes [suivi] (heure, SHA court, nom de fichier assaini), ajoutées à
# $WIP_STATE/status pour l'étape de contrôle.
set +x
set -uo pipefail
: "${WIP_STATE:?}" "${WIP_REPO:?}" "${WIP_BRANCH:?}" "${WIP_JOB:?}" "${WIP_RUN:?}"
REMOTE="${WIP_REMOTE:-https://github.com/LordThiouk/antenly.git}"
GL="${WIP_GITLEAKS:-gitleaks}"
MIN="${IN_WIP_PUSH_MIN:-30}"
TRIES="${WIP_TRIES:-2}"; TMO="${WIP_TIMEOUT:-60}"
[[ "$MIN" =~ ^[0-9]{1,3}$ && "$MIN" -ge 1 && "$MIN" -le 720 ]] || MIN=30
INTERVAL=$(( MIN * 60 ))
# Tests locaux seulement (comme LIVE_INTERVAL de livelog.sh) : intervalle en secondes.
if [[ "${WIP_INTERVAL_SEC:-}" =~ ^[0-9]{1,4}$ ]] && [ "${WIP_INTERVAL_SEC}" -ge 1 ]; then
  INTERVAL="$WIP_INTERVAL_SEC"
fi
FIRST="${WIP_FIRST:-120}"
[[ "$FIRST" =~ ^[0-9]{1,4}$ ]] || FIRST=120
[[ "$TRIES" =~ ^[1-5]$ ]] || TRIES=2
[[ "$TMO" =~ ^[0-9]{1,3}$ && "$TMO" -ge 5 ]] || TMO=60
[[ "$WIP_JOB" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { echo "job invalide" >&2; exit 2; }
[[ "$WIP_RUN" =~ ^[0-9]{1,20}$ ]] || { echo "run invalide" >&2; exit 2; }

# Mêmes règles que la garde d'entrée du workflow : une seule branche de fonctionnalité.
valid_branch() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] || return 1
  case "${1,,}" in
    main|master|head|refs/*|*..*|*/|*.lock|fullrun-logs/*|fullrun-prompts|fullrun-prompts/*) return 1 ;;
  esac
  return 0
}
valid_branch "$WIP_BRANCH" || { echo "branche interdite (main, refs, logs) : rien à faire" >&2; exit 2; }
[ -d "$WIP_REPO/.git" ] || { echo "dépôt de travail absent" >&2; exit 2; }

PUSHED="$WIP_STATE/pushed"
STATUS="$WIP_STATE/status"
TOKEN=""
umask 022
mkdir -p "$WIP_STATE" || exit 3
: >>"$STATUS" 2>/dev/null || true

say() {
  local m; m="[suivi] $* · $(TZ=Africa/Dakar date '+%H:%M') Dakar"
  printf '%s\n' "$m"
  printf '%s\n' "$m" >> "$STATUS" 2>/dev/null || true
}

# git sur le dépôt de travail : lecture seule, propriétaire différent (root en CI).
repo_git() {
  env -i PATH="${PATH}" HOME="$WIP_STATE" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' \
    git -C "$WIP_REPO" "$@" 2>/dev/null
}

# Premier fichier cité par le rapport gitleaks (valeur déjà masquée par --redact) : un nom de
# fichier assaini, jamais un secret. Repli sans jq sur la forme JSON connue.
secret_file() {
  local j="$1" f=""
  if [ -s "$j" ] && command -v jq >/dev/null 2>&1; then
    f=$(jq -r 'if type=="array" then (.[0].File // "") else ((.Findings // [])[0].File // "") end' "$j" 2>/dev/null)
  fi
  if [ -z "$f" ] && [ -s "$j" ]; then
    f=$(grep -oE '"File"[[:space:]]*:[[:space:]]*"[^"]*"' "$j" 2>/dev/null | head -n1 \
        | sed -E 's/.*"File"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/')
  fi
  f=$(basename -- "${f:-}" 2>/dev/null)
  f=$(printf '%s' "$f" | tr -cd 'A-Za-z0-9._ -' | cut -c1-80)
  printf '%s' "${f:-inconnu}"
}

# push <dépôt nu> <sha> : non forcé, essais bornés. Un refus (non fast-forward, jeton sans droit)
# n'est jamais contourné par --force. Jeton passé à git par l'environnement du seul process git
# (en-tête http.extraheader limité à https://github.com/), jamais en argument ni dans l'URL.
push() {
  local B="$1" sha="$2" i auth="" n=1
  valid_branch "$WIP_BRANCH" || return 1
  [ -n "$TOKEN" ] && auth=$(printf 'x-access-token:%s' "$TOKEN" | base64 -w0)
  for (( i = 1; i <= TRIES; i++ )); do
    if [ -n "$auth" ]; then
      timeout -k 5 "$TMO" env -i PATH="${PATH}" HOME="$WIP_STATE" GIT_CONFIG_GLOBAL=/dev/null \
        GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false GIT_DIR="$B" GIT_CONFIG_COUNT=2 \
        GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
        GIT_CONFIG_KEY_1=http.https://github.com/.extraheader GIT_CONFIG_VALUE_1="AUTHORIZATION: basic $auth" \
        git push --no-verify --porcelain "$REMOTE" "$sha:refs/heads/$WIP_BRANCH" >/dev/null 2>&1 && return 0
    else
      timeout -k 5 "$TMO" env -i PATH="${PATH}" HOME="$WIP_STATE" GIT_CONFIG_GLOBAL=/dev/null \
        GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false GIT_DIR="$B" GIT_CONFIG_COUNT=1 \
        GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
        git push --no-verify --porcelain "$REMOTE" "$sha:refs/heads/$WIP_BRANCH" >/dev/null 2>&1 && return 0
    fi
    [ "$i" -lt "$TRIES" ] && sleep $(( n * 5 )) && n=$(( n + 1 ))
  done
  return 1
}

once() {
  local w B head last base range rc=0 f keylen=0
  w=$(mktemp -d "$WIP_STATE/work.XXXXXX") || { say "wip non poussé : échec (dossier de travail)"; return 0; }
  chmod 0700 "$w"
  B="$w/repo.git"
  head=$(repo_git rev-parse -q --verify "refs/heads/$WIP_BRANCH")
  if ! [[ "$head" =~ ^[0-9a-f]{40}$ ]]; then
    rm -rf "$w"; say "wip non poussé : branche $WIP_BRANCH introuvable, on réessaie"; return 0
  fi
  last=""
  [ -s "$PUSHED" ] && last=$(tr -dc '0-9a-f' < "$PUSHED" 2>/dev/null)
  [[ "$last" =~ ^[0-9a-f]{40}$ ]] || last=""
  # Aucun nouveau commit depuis le dernier push : rien à dire, rien à faire.
  if [ -n "$last" ] && [ "$head" = "$last" ]; then rm -rf "$w"; return 0; fi
  git init -q --bare "$B" >/dev/null 2>&1 || { rm -rf "$w"; say "wip non poussé : échec (dépôt de contrôle)"; return 0; }
  # Copie dans un dépôt nu neuf : ni .git/config ni attributs du run (diff.external, textconv…)
  # ne peuvent masquer un contenu au scan. safe.directory=* ne vaut que pour cette lecture.
  if ! timeout -k 5 "$TMO" env -i PATH="${PATH}" HOME="$WIP_STATE" GIT_CONFIG_GLOBAL=/dev/null \
         GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false GIT_CONFIG_COUNT=1 \
         GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' \
         git -C "$B" fetch -q --no-tags "file://$WIP_REPO" \
           "+refs/heads/$WIP_BRANCH:refs/heads/$WIP_BRANCH" >/dev/null 2>&1 \
     || [ "$(git -C "$B" rev-parse -q --verify "refs/heads/$WIP_BRANCH")" != "$head" ]; then
    rm -rf "$w"; say "wip non poussé : copie de contrôle impossible, on réessaie"; return 0
  fi
  # Base du scan : le dernier SHA poussé s'il est bien un ancêtre ; sinon le SHA de départ du run.
  base=""
  if [ -n "$last" ] && git -C "$B" cat-file -e "$last^{commit}" 2>/dev/null \
     && git -C "$B" merge-base --is-ancestor "$last" "$head" 2>/dev/null; then
    base="$last"
  fi
  if [ -z "$base" ] && [[ "${WIP_BASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]]; then
    git -C "$B" cat-file -e "$WIP_BASE_SHA^{commit}" 2>/dev/null \
      && git -C "$B" merge-base --is-ancestor "$WIP_BASE_SHA" "$head" 2>/dev/null \
      && base="$WIP_BASE_SHA"
  fi
  # Branche revenue au dernier point connu (ou aucun commit du run) : pas de push inutile.
  if [ -n "$base" ] && [ "$base" = "$head" ]; then rm -rf "$w"; return 0; fi
  range="$head"
  [ -n "$base" ] && range="$base..$head"
  # Secrets : gitleaks figé, config et ignores pris au SHA de départ.
  cfg=(); [ -n "${WIP_GL_CONFIG:-}" ] && [ -s "$WIP_GL_CONFIG" ] && cfg=(--config "$WIP_GL_CONFIG")
  ign=(); [ -n "${WIP_GL_IGNORE:-}" ] && [ -d "$WIP_GL_IGNORE" ] && ign=(--gitleaks-ignore-path "$WIP_GL_IGNORE")
  timeout -k 5 180 "$GL" git "${cfg[@]}" "${ign[@]}" --log-opts="$range" --redact --no-banner \
    --report-path "$w/gitleaks.json" "$B" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) ;;
    1) f=$(secret_file "$w/gitleaks.json"); rm -rf "$w"
       say "wip non poussé : secret probable dans $f"; return 0 ;;
    *) rm -rf "$w"; say "wip non poussé : contrôle gitleaks impossible (code $rc)"; return 0 ;;
  esac
  # Clé ISA : même contrôle que l'étape finale, jamais la valeur en sortie.
  if [ -n "${WIP_ISA_KEY_FILE:-}" ] && [ -s "$WIP_ISA_KEY_FILE" ]; then
    keylen=$(tr -d ' \t\r\n' < "$WIP_ISA_KEY_FILE" | wc -c)
    if [ "$keylen" -ge 32 ]; then
      git -C "$B" log -p --binary --no-ext-diff --no-textconv --format= "$range" > "$w/run.diff" 2>/dev/null || true
      if grep -qiF -- "$(tr -d ' \t\r\n' < "$WIP_ISA_KEY_FILE")" "$w/run.diff" 2>/dev/null; then
        rm -rf "$w"; say "wip non poussé : la clé ISA apparaît dans les commits"; return 0
      fi
    fi
  fi
  if push "$B" "$head"; then
    printf '%s\n' "$head" > "$PUSHED.tmp" 2>/dev/null && mv -f "$PUSHED.tmp" "$PUSHED" 2>/dev/null || true
    rm -rf "$w"
    say "wip poussé ${head:0:7}"
  else
    rm -rf "$w"
    say "wip non poussé : envoi refusé (branche avancée ailleurs ou jeton sans droit)"
  fi
  return 0
}

case "${1:-}" in
  once)
    if [ "${WIP_TOKEN_STDIN:-0}" = 1 ]; then IFS= read -r TOKEN || true; exec 0</dev/null; fi
    once ;;
  daemon)
    if [ "${WIP_TOKEN_STDIN:-0}" = 1 ]; then IFS= read -r TOKEN || true; exec 0</dev/null; fi
    stop=0; sp=""
    trap 'stop=1; [ -n "$sp" ] && kill "$sp" 2>/dev/null' TERM INT HUP
    printf '%s\n' "$$" > "$WIP_STATE/pid"
    say "démarré (toutes les ${INTERVAL} s) → $WIP_BRANCH"
    delay="$FIRST"
    while [ "$stop" = 0 ]; do
      sleep "$delay" & sp=$!; wait "$sp" 2>/dev/null; sp=""
      [ "$stop" = 0 ] || break
      once
      delay="$INTERVAL"
    done
    say "arrêté" ;;
  *) echo "usage: wippush.sh once|daemon" >&2; exit 2 ;;
esac
