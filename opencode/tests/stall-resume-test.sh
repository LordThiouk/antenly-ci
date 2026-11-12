#!/usr/bin/env bash
# Agent figé : silence -> reprise --continue (bornée), jamais un arrêt définitif tant qu'il reste du temps.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R="$HERE/../run-fullrun.sh"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { # $1 = comportement : "hang-then-ok" ou "hang-always"
  cat >"$T/oc" <<S
#!/usr/bin/env bash
n=\$(cat "$T/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"$T/n"
echo "call \$n: \$*"
if [ "$1" = hang-then-ok ] && [ \$n -ge 2 ]; then echo fini; exit 0; fi
# boucle qui brûle du CPU sans rien écrire (cas F5/FR-14)
end=\$((SECONDS+30)); while [ \$SECONDS -lt \$end ]; do :; done
S
  chmod +x "$T/oc"; rm -f "$T/n" "$T/log"*; mkdir -p "$T/a" "$T/store"; echo p >"$T/p"
}
run() {
  ANTENLY_DIR="$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=m OC_MODEL_FALLBACK=f \
  OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 OC_IDLE_SEC=3 OC_POLL_SEC=1 OC_KILL_GRACE=1 \
  OC_STORE_DIR="$T/store" OC_BIN="$T/oc" OC_STALL_RESUMES="${1:-3}" bash "$R"
}
mk hang-then-ok; run; rc=$?
[ "$rc" -eq 0 ] && grep -q '^\[stall\] .*reprise 1/3' "$T/log" && grep -q 'call 2: run --continue' "$T/log" \
  && grep -q 'agent-error' "$T/log" && echo "ok 1 silence puis reprise réussie" || { echo "FAIL 1 rc=$rc"; fail=1; }
mk hang-always; run 2; rc=$?
[ "$rc" -eq 125 ] && [ "$(cat "$T/n")" -eq 3 ] && grep -q 'arret=silence' "$T/log.status" \
  && echo "ok 2 reprises bornées puis arrêt silence" || { echo "FAIL 2 rc=$rc n=$(cat "$T/n")"; fail=1; }
exit $fail
