#!/usr/bin/env bash
# Clé de porte côté CI : l'input start_step (vide par défaut) est validé par la garde du workflow puis transmis
# à LifeOS par l'environnement d'opencode (FULLRUN_START_STEP), via le wrapper. Une valeur inconnue ou deploy
# est refusée ; vide = rien n'est exporté (comportement habituel) ; une variable déjà présente n'est pas reprise.
#   opencode/tests/start-step-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R="$HERE/../../run-fullrun.sh"
WF="$HERE/../../../.github/workflows/opencode-fullrun.yml"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { echo "OK   $*"; }; ko() { echo "FAIL $*"; fail=1; }

# --- workflow : input vide par défaut, validé, jamais deploy ------------------------------------
python3 - "$WF" <<'PY' || fail=1
import sys, yaml
y = yaml.safe_load(open(sys.argv[1]))
i = (y.get("on") or y.get(True))["workflow_dispatch"]["inputs"]
assert "start_step" in i, "input start_step absent"
assert i["start_step"].get("default") == "" and not i["start_step"].get("required"), "start_step doit être vide par défaut"
print("OK   workflow : input start_step, vide par défaut")
PY
grep -q 'IN_START_STEP: \${{ inputs.start_step }}' "$WF" && ok "workflow : transmis à la garde" || ko "IN_START_STEP absent"
grep -q 'echo "OC_START_STEP=\$start" >> "\$GITHUB_ENV"' "$WF" && ok "workflow : valeur normalisée vers OC_START_STEP" || ko "OC_START_STEP non exporté"
grep -E '\^\(scaffold\|completeness_pre\|vera\|serena\|build\|verify\|max\|close\|\[0-7\]\)\$' "$WF" | grep -q deploy && ko "deploy accepté par la garde" || ok "workflow : deploy n'est pas une valeur acceptée"

# --- wrapper : faux opencode qui rapporte l'environnement reçu -------------------------------------
cat >"$T/done_check" <<S
#!/usr/bin/env bash
[ -f "$T/done" ] && echo done_check=ok || echo done_check=ko raison=a:none
S
chmod +x "$T/done_check"
cat >"$T/oc" <<S
#!/usr/bin/env bash
printf '%s|%s\n' "\${FULLRUN_START_STEP+set}" "\${FULLRUN_START_STEP:-}" >"$T/seen"
echo "Tout est fait, PASS rendu."; : >"$T/done"; exit 0
S
chmod +x "$T/oc"
run() { # variables d'environnement passées en arguments
  rm -rf "$T/seen" "$T/done" "$T/log"* "$T/store" "$T/agents" "$T/internals"; mkdir -p "$T/a" "$T/store" "$T/agents" "$T/internals"; echo p >"$T/p"
  env "$@" ANTENLY_DIR="$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=m \
    OC_MODEL_CHAIN=opencode/fb-free OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) \
    OC_IDLE_MIN=20 OC_IDLE_SEC=3 OC_POLL_SEC=1 OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC=5 \
    OC_STORE_DIR="$T/store" OC_BIN="$T/oc" OC_STALL_RESUMES=1 OC_AGENT_DIR="$T/agents" \
    OC_DONE_CHECK_BIN="$T/done_check" OC_INTERNAL_LOG="$T/log.internal" \
    OC_INTERNAL_LOG_DIR="$T/internals" bash "$R" >/dev/null 2>&1
}
run OC_START_STEP=verify; [ "$(cat "$T/seen" 2>/dev/null)" = "set|verify" ] && ok "wrapper : start_step=verify transmis à opencode" || ko "verify non transmis : $(cat "$T/seen" 2>/dev/null)"
run OC_START_STEP=; [ "$(cat "$T/seen" 2>/dev/null)" = "|" ] && ok "wrapper : vide = rien d'exporté (comportement habituel)" || ko "vide : $(cat "$T/seen" 2>/dev/null)"
run FULLRUN_START_STEP=max; [ "$(cat "$T/seen" 2>/dev/null)" = "|" ] && ok "wrapper : une variable héritée sans l'input n'est pas reprise" || ko "héritage : $(cat "$T/seen" 2>/dev/null)"
for bad in deploy 8 ../x 'verify;x' "n'importe"; do
  run "OC_START_STEP=$bad"; rc=$?
  [ "$rc" -eq 90 ] && [ ! -e "$T/seen" ] && ok "wrapper : OC_START_STEP='$bad' refusé (90), opencode jamais lancé" || ko "'$bad' accepté (rc=$rc)"
done
exit $fail
