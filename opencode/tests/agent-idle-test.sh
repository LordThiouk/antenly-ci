#!/usr/bin/env bash
# Seuil de silence PAR AGENT (OC_AGENT_IDLE_MIN, défaut Forge=40) : un agent qui a une entrée plus longue que le
# seuil de base garde sa tâche jusqu'à ce seuil ; les autres gardent le seuil de base ; le plafond explicite
# OC_SUBAGENT_IDLE_SEC reste maître ; une valeur invalide est refusée (90). Le watchdog n'est jamais affaibli.
#   opencode/tests/agent-idle-test.sh
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
# Appel 1 : reste muet 60 s (le moniteur doit le couper) ; mode quick : conclut tout de suite.
# Appel 2 : la reprise conclut. Chaque appel note l'heure.
cat >"$T/oc" <<S
#!/usr/bin/env bash
n=\$(cat "$T/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"$T/n"
date +%s >>"$T/calls"
if [ "\$(cat "$T/mode")" = quick ]; then echo "fini"; : >"$T/done"; exit 0; fi
if [ "\$n" -eq 1 ]; then echo "démarre"; sleep 60; exit 0; fi
echo "repris"; : >"$T/done"; exit 0
S
chmod +x "$T/oc"
mkrunning() { # $1 = agent ou vide : une tâche `task` en cours dans le stockage
  rm -rf "$T/store"; mkdir -p "$T/store"
  python3 - "$T/store" "$1" <<'PY'
import json, sqlite3, sys
d, agent = sys.argv[1], sys.argv[2]
con = sqlite3.connect(d + '/opencode.db')
con.execute('create table part(session_id text, data text)')
if agent:
    con.execute('insert into part values(?,?)', ('s1', json.dumps({'type': 'tool', 'tool': 'task',
        'state': {'status': 'running', 'input': {'subagent_type': agent}, 'time': {'start': 1700000000000}}})))
con.commit()
PY
}
run() { # $1 = mode ; $2 = agent en cours ; reste = variables d'environnement
  local mode="$1" agent="$2"; shift 2
  rm -rf "$T/n" "$T/done" "$T/log"* "$T/calls" "$T/agents" "$T/internals"; mkdir -p "$T/a" "$T/agents" "$T/internals"
  mkrunning "$agent"; printf -- '---\nmodel: opencode/a-free\n---\n' >"$T/agents/Max.md"; echo p >"$T/p"; echo "$mode" >"$T/mode"
  env "$@" "$DIRVAR=$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=opencode/a-free \
    OC_MODEL_CHAIN=opencode/b-free,opencode/c-free OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) \
    OC_POLL_SEC=1 OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC=0 OC_SUBAGENT_FAIL_MAX=0 \
    OC_STORE_DIR="$T/store" OC_BIN="$T/oc" OC_STALL_RESUMES=1 OC_AGENT_DIR="$T/agents" \
    OC_DONE_CHECK_BIN="$T/done_check" OC_INTERNAL_LOG="$T/log.internal" \
    OC_INTERNAL_LOG_DIR="$T/internals" bash "$R" >/dev/null 2>&1
}
st() { tr '\n' ' ' <"$T/log.status" 2>/dev/null; }
gap() { # secondes entre l'appel 1 et l'appel 2 d'opencode (= durée avant coupure)
  local a b; a=$(sed -n 1p "$T/calls" 2>/dev/null); b=$(sed -n 2p "$T/calls" 2>/dev/null)
  [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] && echo $(( b - a )) || echo -1
}

# 1. Défaut : Forge = 40 min (2400 s), aucune autre entrée.
run quick "" OC_IDLE_MIN=20
grep -qx 'agent_idle=Forge:2400' "$T/log.status" && [ "$(grep -c '^agent_idle=' "$T/log.status")" -eq 1 ] \
  && ok "défaut : Forge=40 min (2400 s), seule entrée" || ko "défaut : $(st)"

# 2. Réglable : entrées explicites par agent (minutes), variable vide = aucune entrée.
run quick "" OC_IDLE_MIN=20 OC_AGENT_IDLE_MIN="Forge=55,Max=30"
grep -qx 'agent_idle=Forge:3300' "$T/log.status" && grep -qx 'agent_idle=Max:1800' "$T/log.status" \
  && ok "réglable par agent (Forge=55, Max=30)" || ko "réglage : $(st)"
run quick "" OC_IDLE_MIN=20 OC_AGENT_IDLE_MIN=
! grep -q '^agent_idle=' "$T/log.status" && ok "variable vide : aucune entrée" || ko "vide : $(st)"

# 3. Valeurs invalides refusées (90), opencode jamais lancé.
for bad in "Forge=abc" "Forge=0" "Forge=721" "=5" "Forge" "Forge=40,Forge=50" "Fo rge=5" "Forge=40," "1Forge=5" "Forge=-3" "Forge=40;rm"; do
  run quick "" OC_IDLE_MIN=20 OC_AGENT_IDLE_MIN="$bad"; rc=$?
  [ "$rc" -eq 90 ] && [ ! -e "$T/n" ] && ok "valeur invalide refusée (90) : « $bad »" || ko "« $bad » accepté (rc=$rc)"
done

# 4. Comportement (secondes, variable de test) : base 3 s, Forge = 9 s.
run silent Forge OC_IDLE_MIN=20 OC_IDLE_SEC=3 OC_AGENT_IDLE_SEC="Forge=9"; g=$(gap)
if [ "$g" -ge 8 ] && [ "$g" -le 25 ] && grep -qx 'agent_idle_extended=Forge:9' "$T/log.status"; then
  ok "Forge en cours : coupé au seuil de Forge (${g}s), pas au seuil de base"; else ko "Forge : ${g}s $(st)"; fi
grep -q '^error=timeout' "$T/log.status" && grep -q 'main_rc=125' "$T/log.status" && grep -q 'arret=max_pass' "$T/log.status" \
  && ok "la coupure reste tracée (error=timeout, rc 125) et la reprise conclut" || ko "trace : $(st)"

run silent Engineer OC_IDLE_MIN=20 OC_IDLE_SEC=3 OC_AGENT_IDLE_SEC="Forge=9"; g=$(gap)
if [ "$g" -ge 2 ] && [ "$g" -le 7 ] && ! grep -q 'agent_idle_extended' "$T/log.status"; then
  ok "agent sans entrée (Engineer) : seuil de base inchangé (${g}s)"; else ko "Engineer : ${g}s $(st)"; fi

run silent "" OC_IDLE_MIN=20 OC_IDLE_SEC=3 OC_AGENT_IDLE_SEC="Forge=9"; g=$(gap)
if [ "$g" -ge 2 ] && [ "$g" -le 7 ] && ! grep -q 'agent_idle_extended' "$T/log.status"; then
  ok "aucun agent identifiable : seuil de base (${g}s), jamais d'extension"; else ko "inconnu : ${g}s $(st)"; fi

run silent Forge OC_IDLE_MIN=20 OC_IDLE_SEC=6 OC_AGENT_IDLE_SEC="Forge=2"; g=$(gap)
if [ "$g" -ge 5 ] && [ "$g" -le 12 ]; then ok "entrée plus courte que la base : sans effet, le seuil de base est un plancher (${g}s)"
else ko "plancher : ${g}s $(st)"; fi

# 5. Le plafond explicite OC_SUBAGENT_IDLE_SEC (watchdog court) reste maître : aucune extension.
run silent Forge OC_IDLE_MIN=20 OC_IDLE_SEC=12 OC_SUBAGENT_IDLE_SEC=3 OC_AGENT_IDLE_SEC="Forge=9"; g=$(gap)
if [ "$g" -ge 2 ] && [ "$g" -le 7 ] && ! grep -q 'agent_idle_extended' "$T/log.status"; then
  ok "OC_SUBAGENT_IDLE_SEC explicite : le watchdog court reste en place (${g}s)"; else ko "plafond : ${g}s $(st)"; fi
exit $fail
