#!/usr/bin/env bash
# Au lancement d'opencode, run-fullrun.sh écrit dans le journal (donc le livelog)
# une ligne [memcap] mécanisme=<systemd-run|cgroupv2|prlimit> limite=10G.
#   opencode/tests/memcap-livelog-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"

R="$here/run-fullrun.sh"
[ -x "$R" ] || ko "run-fullrun.sh absent ou non exécutable"

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/oc" <<'S'
#!/usr/bin/env bash
echo fini
exit 0
S
chmod +x "$tmp/oc"
mkdir -p "$tmp/a" "$tmp/store" "$tmp/agents" "$tmp/internals"
echo p >"$tmp/p"

ANTENLY_DIR="$tmp/a" OC_PROMPT_FILE="$tmp/p" OC_LOG="$tmp/log" \
  OC_MODEL_MAIN=m OC_MODEL_CHAIN=opencode/fb-free \
  OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 \
  OC_IDLE_SEC=3 OC_POLL_SEC=1 OC_KILL_GRACE=1 \
  OC_CONTINUE_PROBE_SEC=0 OC_STORE_DIR="$tmp/store" \
  OC_BIN="$tmp/oc" OC_STALL_RESUMES=0 \
  OC_AGENT_DIR="$tmp/agents" OC_INTERNAL_LOG="$tmp/log.internal" \
  OC_INTERNAL_LOG_DIR="$tmp/internals" \
  bash "$R" >/dev/null 2>"$tmp/err" || true

[ -f "$tmp/log" ] || ko "journal opencode absent"
if ! grep -qE '^\[memcap\] mécanisme=(systemd-run|cgroupv2|prlimit) limite=10G$' "$tmp/log"; then
  ko "ligne [memcap] absente ou mal formée dans le journal : $(grep '\[memcap\]' "$tmp/log" "$tmp/err" 2>/dev/null || echo rien)"
fi
ok "journal : $(grep -E '^\[memcap\] ' "$tmp/log")"

# Même ligne sur stderr (log de job), pour le diagnostic.
if ! grep -qE '\[memcap\] mécanisme=(systemd-run|cgroupv2|prlimit) limite=10G' "$tmp/err"; then
  ko "ligne [memcap] absente de stderr : $(cat "$tmp/err")"
fi
ok "stderr contient la même ligne [memcap]"

# Limite dérivée de MEMCAP_BYTES (défaut 10G déjà couvert).
rm -f "$tmp/log" "$tmp/log.status"
MEMCAP_BYTES=2147483648 ANTENLY_DIR="$tmp/a" OC_PROMPT_FILE="$tmp/p" OC_LOG="$tmp/log" \
  OC_MODEL_MAIN=m OC_MODEL_CHAIN=opencode/fb-free \
  OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 \
  OC_IDLE_SEC=3 OC_POLL_SEC=1 OC_KILL_GRACE=1 \
  OC_CONTINUE_PROBE_SEC=0 OC_STORE_DIR="$tmp/store" \
  OC_BIN="$tmp/oc" OC_STALL_RESUMES=0 \
  OC_AGENT_DIR="$tmp/agents" OC_INTERNAL_LOG="$tmp/log.internal" \
  OC_INTERNAL_LOG_DIR="$tmp/internals" \
  bash "$R" >/dev/null 2>"$tmp/err" || true
if ! grep -qE '^\[memcap\] mécanisme=(systemd-run|cgroupv2|prlimit) limite=2G$' "$tmp/log"; then
  ko "limite=2G attendue pour MEMCAP_BYTES=2G : $(grep '\[memcap\]' "$tmp/log" 2>/dev/null || echo rien)"
fi
ok "MEMCAP_BYTES=2G → limite=2G"

echo "PASS memcap-livelog : ligne [memcap] dans le journal et sur stderr"
