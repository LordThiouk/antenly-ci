#!/usr/bin/env bash
# Sous-agents en échec « timed out » (côté opencode) : le principal continue avec le MÊME modèle, peut-être saturé.
# Au bout de OC_SUBAGENT_FAIL_MAX échecs dans une passe, run-fullrun.sh coupe la passe et la reprise change de
# modèle pour TOUS les agents (réécriture des `model:`), comme pour un silence. 0 = désactivé.
#   opencode/tests/subagent-fail-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R="$HERE/../run-fullrun.sh"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { echo "OK   $*"; }; ko() { echo "FAIL $*"; fail=1; }
DIRVAR=$(grep -q 'TARGET_DIR:?' "$R" && echo TARGET_DIR || echo ANTENLY_DIR)

cat >"$T/done_check" <<S
#!/usr/bin/env bash
[ -f "$T/done" ] && echo done_check=ok || echo done_check=ko raison=a:none
S
chmod +x "$T/done_check"
# Appel 1 : deux sous-agents échouent en timeout puis le principal « continue » (reste actif, jamais muet).
# Appels suivants : la reprise conclut. $T/mode : tick = 1 échec seulement puis fin de tour.
cat >"$T/oc" <<S
#!/usr/bin/env bash
n=\$(cat "$T/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"$T/n"
printf 'call %s: %s | agent=%s\n' "\$n" "\$*" "\$(sed -n 's/^model: //p' "$T/agents/Max.md")" >>"$T/calls"
if [ "\$n" -eq 1 ]; then
  for i in 1 2; do echo "Error: Subagent failed (task_id: ses_\$i): The operation timed out."; [ "\$(cat "$T/mode")" = one ] && break; done
  [ "\$(cat "$T/mode")" = one ] && { echo "Tour fini."; exit 0; }
  for i in \$(seq 1 120); do echo "le principal continue \$i"; sleep 1; done
  exit 0
fi
echo "Repris et terminé."; : >"$T/done"; exit 0
S
chmod +x "$T/oc"
run() { # $1 = mode ; reste = variables d'environnement
  local mode="$1"; shift
  rm -rf "$T/n" "$T/done" "$T/log"* "$T/calls" "$T/store" "$T/agents" "$T/internals"; mkdir -p "$T/a" "$T/store" "$T/agents" "$T/internals"
  printf -- '---\nmodel: opencode/a-free\n---\n' >"$T/agents/Max.md"; echo p >"$T/p"; echo "$mode" >"$T/mode"
  env "$@" "$DIRVAR=$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=opencode/a-free \
    OC_MODEL_CHAIN=opencode/b-free,opencode/c-free OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) \
    OC_IDLE_MIN=20 OC_IDLE_SEC=60 OC_POLL_SEC=1 OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC=5 \
    OC_STORE_DIR="$T/store" OC_BIN="$T/oc" OC_STALL_RESUMES=2 OC_AGENT_DIR="$T/agents" \
    OC_DONE_CHECK_BIN="$T/done_check" OC_INTERNAL_LOG="$T/log.internal" \
    OC_INTERNAL_LOG_DIR="$T/internals" bash "$R" >/dev/null 2>&1
}
st() { cat "$T/log.status" 2>/dev/null | tr '\n' ' '; }

# 1. Deux échecs de sous-agent : coupure rapide, reprise sur le modèle suivant, tous les agents réécrits.
start=$(date +%s); run both; el=$(( $(date +%s) - start ))
if grep -q 'subagent_fail=2' "$T/log.status" && grep -q 'subagent_timeout=1' "$T/log.status" \
   && grep -q 'fallback=opencode/b-free' "$T/log.status" && [ "$el" -lt 60 ]; then
  ok "2 sous-agents en échec : passe coupée en ${el}s, reprise sur opencode/b-free"
else ko "coupure : $(st) (${el}s)"; fi
grep -q 'call 2: .*--model opencode/b-free' "$T/calls" 2>/dev/null && ok "la reprise passe --model opencode/b-free" || ko "reprise : $(cat "$T/calls" 2>/dev/null)"
grep -q '^model: opencode/b-free' "$T/agents/Max.md" && ok "le modèle des sous-agents (Max.md) est réécrit" || ko "Max.md : $(cat "$T/agents/Max.md")"
grep -q 'arret=max_pass' "$T/log.status" && ok "la reprise conclut (PASS vérifié)" || ko "fin : $(st)"
grep -c '\[agent-error\] type=timeout' "$T/log" | grep -qx '[1-9]' && ok "l'échec est tracé (agent-error timeout)" || ko "agent-error absent"

# 2. Un seul échec : rien n'est coupé (pas de rotation inutile).
run one
! grep -q 'subagent_fail' "$T/log.status" && ok "1 seul échec de sous-agent : pas de coupure par ce motif" || ko "coupé à tort : $(st)"

# 3. Désactivé (0) : aucun effet, même avec deux échecs (la passe se termine d'elle-même ou au silence).
start=$(date +%s); run both OC_SUBAGENT_FAIL_MAX=0 OC_IDLE_SEC=8; 
! grep -q 'subagent_fail' "$T/log.status" && ok "OC_SUBAGENT_FAIL_MAX=0 : désactivé" || ko "0 ignoré : $(st)"

# 4. Valeur invalide : refus (90), opencode jamais lancé.
run both OC_SUBAGENT_FAIL_MAX=abc; rc=$?
[ "$rc" -eq 90 ] && [ ! -e "$T/n" ] && ok "valeur invalide refusée (90)" || ko "invalide accepté (rc=$rc)"
exit $fail
