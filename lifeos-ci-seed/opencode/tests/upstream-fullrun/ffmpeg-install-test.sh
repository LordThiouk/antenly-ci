#!/usr/bin/env bash
# L'installation ffmpeg/ffprobe de opencode-fullrun.yml suit ci.yml (setup-ffmpeg
# épinglé + secours apt) et échoue si command -v ffmpeg ne trouve rien, avant
# l'étape opencode run.
#   opencode/tests/ffmpeg-install-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/opencode/tests/lib.sh"

yml="$here/.github/workflows/opencode-fullrun.yml"
ci="$here/.github/workflows/ci.yml"
[ -f "$yml" ] || ko "opencode-fullrun.yml absent"
[ -f "$ci" ] || ko "ci.yml absent"

pin=$(grep -oE 'FedericoCarboni/setup-ffmpeg@[0-9a-f]{40}' "$ci" | head -1)
[ -n "$pin" ] || ko "pin setup-ffmpeg introuvable dans ci.yml"
grep -q -F "$pin" "$yml" || ko "opencode-fullrun.yml doit utiliser le même setup-ffmpeg que ci.yml ($pin)"
ok "même pin setup-ffmpeg que ci.yml"

grep -q 'apt-get install -y ffmpeg' "$yml" || ko "secours apt ffmpeg manquant dans opencode-fullrun.yml"
ok "secours apt ffmpeg présent"

grep -q 'command -v ffmpeg' "$yml" || ko "contrôle command -v ffmpeg manquant"
grep -q 'command -v ffprobe' "$yml" || ko "contrôle command -v ffprobe manquant"
grep -q 'ffmpeg absent' "$yml" || ko "le workflow doit échouer explicitement si ffmpeg est absent"
ok "contrôles command -v ffmpeg et ffprobe, échec si absent"

lineno() { grep -n -E "$1" "$yml" | head -1 | cut -d: -f1; }
ff=$(lineno 'FedericoCarboni/setup-ffmpeg@')
apt=$(lineno 'apt-get install -y ffmpeg')
chk=$(lineno 'command -v ffmpeg')
oc=$(grep -n 'name: opencode run' "$yml" | head -1 | cut -d: -f1)
[ -n "$ff" ] && [ -n "$apt" ] && [ -n "$chk" ] && [ -n "$oc" ] \
  || ko "lignes ffmpeg ou opencode run introuvables (ff=$ff apt=$apt chk=$chk oc=$oc)"
[ "$ff" -lt "$oc" ] || ko "setup-ffmpeg doit précéder opencode run ($ff >= $oc)"
[ "$apt" -lt "$oc" ] || ko "secours apt doit précéder opencode run ($apt >= $oc)"
[ "$chk" -lt "$oc" ] || ko "contrôle command -v ffmpeg doit précéder opencode run ($chk >= $oc)"
ok "ffmpeg/ffprobe installés et vérifiés avant opencode run"

echo "PASS ffmpeg-install : pin, secours apt, contrôle avant opencode"
