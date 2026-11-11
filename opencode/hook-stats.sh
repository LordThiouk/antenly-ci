#!/usr/bin/env bash
# Bilan déterministe des hooks LifeOS rejoués par le plugin (hooks.log / hook-failures.log),
# comparé aux hooks configurés dans ~/.claude/settings.json. Écrit du Markdown sur stdout.
set -uo pipefail
HL="$HOME/.local/state/opencode-lifeos"
S="$HOME/.claude/settings.json"
fired=$(mktemp); conf=$(mktemp)
if [ -s "$HL/hooks.log" ]; then
  grep -oE ' [A-Za-z]+ (\(exit-sync\) )?(tool=[^ ]+ )?hook=[^ ]+ exit=[0-9-]+' "$HL/hooks.log" \
    | awk '{ev=$1; h=""; e=""; for(i=2;i<=NF;i++){if($i~/^hook=/)h=substr($i,6); if($i~/^exit=/)e=substr($i,6)} print ev"|"h"|"e}' \
    | sort | uniq -c | awk '{print $2"|"$1}' > "$fired"
fi
jq -r '.hooks | to_entries[] | .key as $e | .value[] | .hooks[] | select(.command) | "\($e)|\(.command | split("/")[-1] | split(" ")[0])"' "$S" 2>/dev/null \
  | sort -u > "$conf"
echo "## Hooks LifeOS (compté par le workflow, pas par l'agent)"
echo
echo "| événement | hook | exit | appels |"
echo "|---|---|---|---|"
if [ -s "$fired" ]; then awk -F'|' '{printf "| %s | %s | %s | %s |\n",$1,$2,$3,$4}' "$fired"; else echo "| (hooks.log absent ou vide) | | | |"; fi
echo
echo "### Hooks configurés jamais déclenchés"
echo
n=0
while IFS='|' read -r ev h; do
  grep -qF "$ev|$h|" "$fired" || { echo "- $ev · $h"; n=$((n+1)); }
done < "$conf"
[ "$n" -eq 0 ] && echo "- aucun"
echo
echo "### Échecs (hook-failures.log, 60 dernières lignes, 240 car.)"
echo
if [ -s "$HL/hook-failures.log" ]; then echo '```'; tail -n 60 "$HL/hook-failures.log" | cut -c1-240; echo '```'; else echo "aucun"; fi
rm -f "$fired" "$conf"
