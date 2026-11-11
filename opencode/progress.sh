#!/usr/bin/env bash
# Suivi en direct d'un run opencode, écrit dans le log PUBLIC du job (et $GITHUB_STEP_SUMMARY).
# N'émet que des valeurs filtrées : heure, durée, phase et agent pris dans une liste blanche,
# compteurs numériques, booléen 429. Jamais de texte du modèle, de chemin ni de code ; tout
# ce qui ne passe pas le filtre devient « ? ».
#   progress.sh start | once [fin [ok|silence|plafond|erreur|annulation]] | loop | isc
set +x
set -uo pipefail
: "${OC_LOG:?}" "${ANTENLY_DIR:?}" "${OC_START:?}"
INTERVAL="${OC_PROGRESS_INTERVAL:-600}"
[[ "$INTERVAL" =~ ^[0-9]{2,5}$ ]] || INTERVAL=600

PHASES="Observe Think Plan Build Execute Verify Learn Marking Ascending Anchoring Camped Cairn Traverse Idle"
AGENTS="Nix Algorithm Anvil Architect Arthur Artist BrowserAgent Cato Designer Engineer Forge Max QATester \
Silas UIReviewer Serena Vera Rea Explore General ClaudeResearcher CodexResearcher GeminiResearcher \
GrokResearcher PerplexityResearcher Code-Reviewer Code-Architect Code-Explorer Code-Simplifier \
Comment-Analyzer Pr-Test-Analyzer Silent-Failure-Hunter Type-Design-Analyzer"

# Rend le mot de la liste blanche (forme canonique) s'il correspond, sinon « ? ».
pick() {
  local v="${1,,}" w
  for w in $2; do [ "$v" = "${w,,}" ] && { printf '%s' "$w"; return; }; done
  printf '?'
}
num() { [[ "${1:-}" =~ ^[0-9]{1,7}$ ]] && printf '%s' "$1" || printf '?'; }

isa_file() {
  local re='^MEMORY/WORK/[A-Za-z0-9._-]+/ISA\.md$' c
  if [ -n "${OC_ISA_PATH:-}" ]; then
    [[ "$OC_ISA_PATH" =~ $re && "$OC_ISA_PATH" != *..* ]] && printf '%s' "$OC_ISA_PATH"; return
  fi
  # ISA citée par le prompt (une seule), sinon ISA modifiée par le run (une seule).
  c=$(grep -aoE 'MEMORY/WORK/[A-Za-z0-9._-]+/ISA\.md' "${OC_PROMPT_FILE:-/dev/null}" 2>/dev/null | sort -u)
  if [ "$(printf '%s' "$c" | grep -c .)" != 1 ] && [ -n "${BASE_SHA:-}" ]; then
    c=$( { GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -C "$ANTENLY_DIR" diff --name-only "$BASE_SHA" 2>/dev/null
           GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -C "$ANTENLY_DIR" ls-files --others --exclude-standard 2>/dev/null; } \
         | grep -E "$re" | sort -u)
  fi
  [ "$(printf '%s' "$c" | grep -c .)" = 1 ] && [[ "$c" =~ $re && "$c" != *..* ]] && printf '%s' "$c"
}

# Raison d'arrêt (code de liste blanche décidé par le step) -> libellé public.
reason_label() {
  local n; n=$(num "${OC_IDLE_MIN:-}")
  case "${1:-}" in
    ok) printf 'terminé' ;;
    silence) printf 'bloqué (silence %s min)' "$n" ;;
    plafond) printf 'plafond atteint' ;;
    annulation) printf 'annulé' ;;
    erreur) printf 'erreur opencode' ;;
    *) printf '' ;;
  esac
}

# ISC cochés/total de l'ISA suivie : « n/m » ou « ?/? ».
isc() {
  local isa real ok='?' total='?'
  isa=$(isa_file)
  real=""
  [ -n "$isa" ] && real=$(realpath -e "$ANTENLY_DIR/$isa" 2>/dev/null)
  case "$real" in
    "$(realpath "$ANTENLY_DIR")"/MEMORY/WORK/*/ISA.md)
      ok=$(grep -cE '^[[:space:]]*[-*] \[[xX]\]' "$real")
      total=$(( ok + $(grep -cE '^[[:space:]]*[-*] \[ \]' "$real") )) ;;
  esac
  printf '%s/%s' "$(num "$ok")" "$(num "$total")"
}

line() {
  local tag="${1:-}" why now el clean phase agent ok total commits='?' lim='?' idle='?' mt stamp
  why=$(reason_label "${2:-}")
  now=$(TZ=Africa/Dakar date '+%H:%M')
  el=$(( ( $(date +%s) - OC_START ) / 60 ))
  # Minutes depuis la dernière activité réelle du run, telle que mesurée par run-fullrun.sh
  # (journal, CPU de l'arbre opencode, fichiers de session) ; repli sur la mtime du journal.
  stamp="${OC_ACT:-$OC_LOG.act}"; [ -f "$stamp" ] || stamp="$OC_LOG"
  mt=$(stat -c %Y "$stamp" 2>/dev/null) && [[ "$mt" =~ ^[0-9]+$ ]] && idle=$(( ( $(date +%s) - mt ) / 60 ))
  [[ "$idle" =~ ^[0-9]+$ && "$idle" -lt 0 ]] && idle=0
  clean=$(mktemp)
  [ -f "$OC_LOG" ] && perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\r//g' "$OC_LOG" > "$clean" 2>/dev/null
  phase=$(grep -aoE 'LifeOS \| Algorithm \| [^|]{0,40}' "$clean" | tail -n1 | grep -oE '[A-Za-z]+' | tail -n1)
  agent=$(sed -nE 's/^• .* ([A-Za-z][A-Za-z-]{1,40}) Agent[[:space:]]*$/\1/p' "$clean" | tail -n1)
  # Vraie erreur d'API seulement : un « 429 » isolé matche des numéros et le texte du prompt.
  if grep -qaiE '"status_?code"[[:space:]]*:[[:space:]]*429|status.?code.?429|rate limit exceeded|free usage limit reached|too many requests' "$clean"; then
    lim=oui
  elif [ -f "$OC_LOG" ]; then lim=non; fi
  rm -f "$clean"
  IFS=/ read -r ok total <<<"$(isc)"
  [ -n "${BASE_SHA:-}" ] && commits=$(GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -C "$ANTENLY_DIR" rev-list --count "$BASE_SHA..HEAD" 2>/dev/null)
  phase=$(pick "${phase:-}" "$PHASES"); agent=$(pick "${agent:-}" "$AGENTS")
  ok=$(num "$ok"); total=$(num "$total"); commits=$(num "$commits"); el=$(num "$el"); idle=$(num "$idle")
  if [ "$tag" = fin ]; then tag="fin${why:+ : $why} · "; else tag=""; fi
  echo "[suivi] ${tag}${now} Dakar · +${el} min · phase ${phase} · agent ${agent} · ISC ${ok}/${total} · commits ${commits} · silence ${idle} min · 429/limite ${lim}"
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && \
    echo "| ${tag}${now} | ${el} | ${idle} | ${phase} | ${agent} | ${ok}/${total} | ${commits} | ${lim} |" >> "$GITHUB_STEP_SUMMARY"
  return 0
}

case "${1:-}" in
  start)
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      { echo "### Suivi opencode (toutes les $((INTERVAL / 60)) min, valeurs filtrées)"; echo
        echo "| heure (Dakar) | min | silence (min) | phase | dernier agent | ISC cochés | commits | 429/limite |"
        echo "|---|---|---|---|---|---|---|---|"; } >> "$GITHUB_STEP_SUMMARY"
    fi
    line ;;
  once) line "${2:-}" "${3:-}" ;;
  isc) isc; echo ;;
  loop)
    sp=""
    trap '[ -n "$sp" ] && kill "$sp" 2>/dev/null; exit 0' TERM INT HUP
    parent="${OC_PARENT_PID:-$PPID}"
    while kill -0 "$parent" 2>/dev/null; do
      sleep "$INTERVAL" & sp=$!; wait "$sp"; sp=""
      kill -0 "$parent" 2>/dev/null || break
      line
    done ;;
  *) echo "usage: progress.sh start|once [fin [raison]]|loop|isc" >&2; exit 2 ;;
esac
