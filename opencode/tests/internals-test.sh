#!/usr/bin/env bash
# Journaux internes : collectés après chaque passe (ajoutés, jamais affichés) puis masqués par
# redact-log.sh comme le journal principal. Canaris générés au runtime : aucune valeur en dur.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R="$HERE/../run-fullrun.sh"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

canary="ghp_$(openssl rand -hex 18)"
canary2="sk-$(openssl rand -hex 16)"

mkdir -p "$T/a" "$T/internals" "$T/store" "$T/agents"
echo p >"$T/p"
cat >"$T/oc" <<S
#!/usr/bin/env bash
printf 'timestamp=2026-11-12T12:00:00.000Z level=INFO message=probe token=$canary\\n' >>"\$OC_INTERNAL_LOG_DIR/fake.log"
printf 'timestamp=2026-11-12T12:00:01.000Z level=INFO message=hook token=$canary2\\n' >>"\$OC_INTERNAL_LOG_DIR/fake.log"
echo fini
exit 0
S
chmod +x "$T/oc"

ANTENLY_DIR="$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=m \
OC_MODEL_FALLBACK=opencode/fb-free OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 \
OC_IDLE_SEC=3 OC_POLL_SEC=1 OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC=0 OC_STORE_DIR="$T/store" \
OC_BIN="$T/oc" OC_STALL_RESUMES=0 OC_AGENT_DIR="$T/agents" \
OC_INTERNAL_LOG="$T/log.internal" OC_INTERNAL_LOG_DIR="$T/internals" bash "$R"; rc=$?

if [ "$rc" -eq 0 ] && grep -qF "$canary" "$T/log.internal" && grep -qF "$canary2" "$T/log.internal" \
   && grep -q '^=== fake.log ===' "$T/log.internal"; then
  echo "ok 1 journaux internes collectés (ajoutés, canaris présents avant masquage)"
else
  echo "FAIL 1 rc=$rc"; ls -l "$T"; tail -n 5 "$T/log.internal" 2>/dev/null; fail=1
fi

# Même masquage que le journal principal : les deux canaris doivent ressortir masqués.
if OC_ISA_KEY_FILE=/dev/null "$HERE/../redact-log.sh" "$T/log.internal" "$T/redacted" \
   && ! grep -qF "$canary" "$T/redacted" && ! grep -qF "$canary2" "$T/redacted" \
   && grep -q '\[REDACTED:github-token\]' "$T/redacted" \
   && grep -q '\[REDACTED:sk-key\]' "$T/redacted"; then
  echo "ok 2 canaris masqués par redact-log.sh"
else
  echo "FAIL 2 masquage"; head -c 400 "$T/redacted" 2>/dev/null; fail=1
fi

# Dossier absent = aucune erreur, aucune collecte.
rm -rf "$T/internals"
ANTENLY_DIR="$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log2" OC_MODEL_MAIN=m \
OC_MODEL_FALLBACK=opencode/fb-free OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 \
OC_IDLE_SEC=3 OC_POLL_SEC=1 OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC=0 OC_STORE_DIR="$T/store" \
OC_BIN="$T/oc" OC_STALL_RESUMES=0 OC_AGENT_DIR="$T/agents" \
OC_INTERNAL_LOG="$T/log2.internal" OC_INTERNAL_LOG_DIR="$T/internals" bash "$R" 2>/dev/null; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "ok 3 dossier de journaux internes absent -> run normal"
else
  echo "FAIL 3 rc=$rc"; fail=1
fi

exit $fail
