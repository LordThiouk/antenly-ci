#!/usr/bin/env bash
# Clé de porte côté CI (Lot B) : les inputs stop_after_step et target_agent (vides par défaut)
# sont validés par la garde du workflow puis transmis à LifeOS par l'environnement d'opencode
# (FULLRUN_STOP_AFTER_STEP, FULLRUN_TARGET_AGENT), via le wrapper. Une valeur inconnue (ou deploy
# pour stop_after_step) est refusée ; vide = rien n'est exporté (comportement habituel).
#   opencode/tests/stop-step-target-agent-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R="$HERE/../run-fullrun.sh"
WF="$HERE/../../.github/workflows/opencode-fullrun.yml"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { echo "OK   $*"; }; ko() { echo "FAIL $*"; fail=1; }

# --- workflow : inputs vides par défaut, validés, jamais deploy pour stop_after_step ------------
python3 - "$WF" <<'PY' || fail=1
import sys, yaml
y = yaml.safe_load(open(sys.argv[1]))
i = (y.get("on") or y.get(True))["workflow_dispatch"]["inputs"]
for name in ("stop_after_step", "target_agent"):
    assert name in i, f"input {name} absent"
    assert i[name].get("default") == "" and not i[name].get("required"), f"{name} doit être vide par défaut"
print("OK   workflow : inputs stop_after_step et target_agent, vides par défaut")
PY
grep -q 'IN_STOP_AFTER_STEP: \${{ inputs.stop_after_step }}' "$WF" && ok "workflow : stop_after_step transmis à la garde" || ko "IN_STOP_AFTER_STEP absent"
grep -q 'IN_TARGET_AGENT: \${{ inputs.target_agent }}' "$WF" && ok "workflow : target_agent transmis à la garde" || ko "IN_TARGET_AGENT absent"
grep -q 'echo "OC_STOP_AFTER_STEP=\$stop_step" >> "\$GITHUB_ENV"' "$WF" && ok "workflow : valeur normalisée vers OC_STOP_AFTER_STEP" || ko "OC_STOP_AFTER_STEP non exporté"
grep -q 'echo "OC_TARGET_AGENT=\$IN_TARGET_AGENT" >> "\$GITHUB_ENV"' "$WF" && ok "workflow : target_agent exporté vers OC_TARGET_AGENT" || ko "OC_TARGET_AGENT non exporté"

# --- wrapper : faux opencode qui rapporte l'environnement reçu -------------------------------------
cat >"$T/done_check" <<S
#!/usr/bin/env bash
[ -f "$T/done" ] && echo done_check=ok || echo done_check=ko raison=a:none
S
chmod +x "$T/done_check"
cat >"$T/oc" <<S
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "\${FULLRUN_STOP_AFTER_STEP+set}" "\${FULLRUN_STOP_AFTER_STEP:-}" \
  "\${FULLRUN_TARGET_AGENT+set}" "\${FULLRUN_TARGET_AGENT:-}" >"$T/seen"
echo "Tout est fait, PASS rendu."; : >"$T/done"; exit 0
S
chmod +x "$T/oc"
run() { # variables d'environnement passées en arguments
  rm -rf "$T/seen" "$T/done" "$T/log"* "$T/store" "$T/agents" "$T/internals"; mkdir -p "$T/a" "$T/store" "$T/agents" "$T/internals"; echo p >"$T/p"
  env "$@" TARGET_DIR="$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=m \
    OC_MODEL_CHAIN=opencode/fb-free OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) \
    OC_IDLE_MIN=20 OC_IDLE_SEC=3 OC_POLL_SEC=1 OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC=5 \
    OC_STORE_DIR="$T/store" OC_BIN="$T/oc" OC_STALL_RESUMES=1 OC_AGENT_DIR="$T/agents" \
    OC_DONE_CHECK_BIN="$T/done_check" OC_INTERNAL_LOG="$T/log.internal" \
    OC_INTERNAL_LOG_DIR="$T/internals" bash "$R" >/dev/null 2>&1
}
run OC_STOP_AFTER_STEP=verify OC_TARGET_AGENT=Silas
[ "$(cat "$T/seen" 2>/dev/null)" = "set|verify|set|Silas" ] && ok "wrapper : stop_after_step=verify + target_agent=Silas transmis" || ko "verify/Silas non transmis : $(cat "$T/seen" 2>/dev/null)"
run OC_STOP_AFTER_STEP= OC_TARGET_AGENT=
[ "$(cat "$T/seen" 2>/dev/null)" = "|||" ] && ok "wrapper : vide = rien d'exporté (comportement habituel)" || ko "vide : $(cat "$T/seen" 2>/dev/null)"
run FULLRUN_STOP_AFTER_STEP=max FULLRUN_TARGET_AGENT=Forge
[ "$(cat "$T/seen" 2>/dev/null)" = "|||" ] && ok "wrapper : une variable héritée sans l'input n'est pas reprise" || ko "héritage : $(cat "$T/seen" 2>/dev/null)"
for bad in deploy 8 ../x 'verify;x' "n'importe"; do
  run "OC_STOP_AFTER_STEP=$bad"; rc=$?
  [ "$rc" -eq 90 ] && [ ! -e "$T/seen" ] && ok "wrapper : OC_STOP_AFTER_STEP='$bad' refusé (90), opencode jamais lancé" || ko "'$bad' accepté (rc=$rc)"
done
for bad in '1Silas' 'Silas;x' '../x' "n'importe quoi"; do
  run "OC_TARGET_AGENT=$bad"; rc=$?
  [ "$rc" -eq 90 ] && [ ! -e "$T/seen" ] && ok "wrapper : OC_TARGET_AGENT='$bad' refusé (90), opencode jamais lancé" || ko "'$bad' accepté (rc=$rc)"
done
exit $fail
