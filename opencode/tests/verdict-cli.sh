# shellcheck shell=bash
# Sourcé par les tests qui font tourner le vrai done_check.sh : localise le CLI de verdict lifeos
# (LIFEOS/TOOLS/FullRunVerdict.ts, source unique du verdict) et l'exporte en OC_VERDICT_CLI.
# Ordre : OC_VERDICT_CLI déjà posé, copie ~/.claude (reconstituée en CI), checkout voisin ../lifeos.
find_verdict_cli() {
  local c root; root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  for c in "${OC_VERDICT_CLI:-}" "$HOME/.claude/LIFEOS/TOOLS/FullRunVerdict.ts" \
           "$root/../lifeos/LIFEOS/TOOLS/FullRunVerdict.ts" "$root/lifeos/LIFEOS/TOOLS/FullRunVerdict.ts" \
           "${GITHUB_WORKSPACE:-/nonexistent}/lifeos/LIFEOS/TOOLS/FullRunVerdict.ts"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}
command -v bun >/dev/null 2>&1 || [ -x "$HOME/.bun/bin/bun" ] || { echo "ko bun introuvable (requis par done_check.sh)"; exit 1; }
OC_VERDICT_CLI=$(find_verdict_cli) || { echo "ko FullRunVerdict.ts introuvable : pose OC_VERDICT_CLI (lifeos >= fix/build-gate-scope)"; exit 1; }
export OC_VERDICT_CLI
