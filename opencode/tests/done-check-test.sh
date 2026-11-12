#!/usr/bin/env bash
# Tests du validateur de fin (étape 4) : stockage opencode (SQLite et arbre JSON), hooks.log,
# vérificateurs relancés, arbre/rapport/ISA — et la sortie anticipée de run-fullrun.sh
# (`arret=max_pass`, rc 0, hors modèle).
# Usage : bash opencode/tests/done-check-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
DC="$ROOT/opencode/done_check.sh"
RUN="$ROOT/opencode/run-fullrun.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "ok $1"; pass=$((pass + 1)); }
ko() { echo "ko $1"; fail=$((fail + 1)); }

# Dépôt de test, dernier commit = maintenant (les fins de part doivent être après).
R="$T/repo"; mkdir -p "$R"; cd "$R" || exit 1
git init -q; git config user.email t@t; git config user.name t
echo code >a.txt; git add -A; git commit -qm init
COMMIT=$(git log -1 --format=%ct)
REPORT="$T/REPORT.md"; echo rapport >"$REPORT"
ISA="$T/ISA.md"; printf -- '---\nphase: climbing\n---\n' >"$ISA"

mkstore() { # $1=dossier $2=modèle $3=tokens $4=sortie $5=fin(ms) [$6=agent]
  python3 - "$1" "$2" "$3" "$4" "$5" "${6:-Max}" <<'PY'
import json, os, sqlite3, sys
d, model, tokens, out, end, agent = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], int(sys.argv[5]), sys.argv[6]
os.makedirs(d, exist_ok=True)
part = {"type": "tool", "tool": "task",
        "state": {"status": "completed", "input": {"subagent_type": agent},
                  "metadata": {"sessionId": "child1", "model": {"modelID": model}},
                  "time": {"end": end}, "output": out}}
msg = {"role": "assistant", "modelID": model, "tokens": {"input": 10, "output": tokens}}
con = sqlite3.connect(os.path.join(d, "opencode.db"))
con.execute("create table part(session_id text, data text)")
con.execute("create table message(session_id text, data text)")
con.execute("insert into part values('s1',?)", (json.dumps(part),))
con.execute("insert into message values('child1',?)", (json.dumps(msg),))
con.commit()
PY
}
mkjson() { # arbre JSON : storage/part/<msg>/<part>.json + storage/message/<session>/<msg>.json
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, os, sys
d, model, tokens, out, end = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], int(sys.argv[5])
p = os.path.join(d, "storage", "part", "m1"); os.makedirs(p, exist_ok=True)
json.dump({"type": "tool", "tool": "task",
           "state": {"status": "completed", "input": {"subagent_type": "Max"},
                     "metadata": {"sessionId": "child1"},
                     "time": {"end": end}, "output": out}}, open(os.path.join(p, "p1.json"), "w"))
p = os.path.join(d, "storage", "message", "child1"); os.makedirs(p, exist_ok=True)
json.dump({"role": "assistant", "modelID": model, "tokens": {"output": tokens}},
          open(os.path.join(p, "m1.json"), "w"))
PY
}
ENDP=$(( (COMMIT + 10) * 1000 ))
HOOKS="$T/hooks.log"
mklog() { printf '%s SUBAGENT done subagent_type=%s ok=true session=s call=c\n' \
  "$(date -u -d "@$((COMMIT + 5))" +%Y-%m-%dT%H:%M:%S.000Z)" "${1:-Max}" >"$HOOKS"; }
call() { # $1=store ; le reste = env supplémentaires
  local store="$1"; shift
  env OC_STORE_DIR="$store" OC_HOOKS_LOG="$HOOKS" OC_REPORT="$REPORT" OC_ISA="$ISA" \
      OC_DONE_REPO="$R" "$@" bash "$DC" 2>/dev/null
}

# 1. SQLite complet -> ok
mkstore "$T/s1" "opencode/v4-flash-free" 42 '{"status":"pass"} travail terminé' "$ENDP"
mklog Max
out=$(call "$T/s1"); [ "$out" = "done_check=ok" ] && ok 1 "PASS SQLite complet" || ko "1 [$out]"

# 2. arbre JSON complet -> ok (l'autre format de stockage)
mkjson "$T/s2" "opencode/v4-flash-free" 7 'LGTM' "$ENDP"
out=$(call "$T/s2"); [ "$out" = "done_check=ok" ] && ok 2 "PASS arbre JSON" || ko "2 [$out]"

# 3. modèle non gratuit -> a:tokens
mkstore "$T/s3" "opencode/v4-pro" 42 'PASS' "$ENDP"
out=$(call "$T/s3"); [ "$out" = "done_check=ko raison=a:tokens" ] && ok 3 "modèle non gratuit refusé" || ko "3 [$out]"

# 4. sortie négative -> a:verdict
mkstore "$T/s4" "opencode/v4-flash-free" 42 'REQUEST CHANGES' "$ENDP"
out=$(call "$T/s4"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 4 "verdict négatif refusé" || ko "4 [$out]"

# 5. fin antérieure au dernier commit de code -> a:time
mkstore "$T/s5" "opencode/v4-flash-free" 42 'PASS' "$(( (COMMIT - 60) * 1000 ))"
out=$(call "$T/s5"); [ "$out" = "done_check=ko raison=a:time" ] && ok 5 "PASS antérieur au commit refusé" || ko "5 [$out]"

# 6. hooks.log sans ligne plugin -> b:hooks
mkstore "$T/s6" "opencode/v4-flash-free" 42 'PASS' "$ENDP"
printf 'autre chose\n' >"$HOOKS"
out=$(call "$T/s6"); [ "$out" = "done_check=ko raison=b:hooks" ] && ok 6 "sans ligne hooks refusé" || ko "6 [$out]"
mklog Max

# 7. vérificateur en échec -> c:verify2
out=$(call "$T/s6" OC_DONE_VERIFY="true; false"); [ "$out" = "done_check=ko raison=c:verify2" ] \
  && ok 7 "vérificateur en échec refusé" || ko "7 [$out]"

# 8. arbre sale -> d:arbre-sale
echo sale >"$R/pas-commite.txt"
out=$(call "$T/s6"); [ "$out" = "done_check=ko raison=d:arbre-sale" ] && ok 8 "arbre sale refusé" || ko "8 [$out]"
rm -f "$R/pas-commite.txt"

# 9. ISA close -> d:isa-complete
printf -- '---\nphase: complete\n---\n' >"$ISA"
out=$(call "$T/s6"); [ "$out" = "done_check=ko raison=d:isa-complete" ] && ok 9 "ISA close refusée" || ko "9 [$out]"
printf -- '---\nphase: climbing\n---\n' >"$ISA"

# 9b. magasin absent -> a:stockage : un chemin faux n'est pas « aucune tâche Max » (run F4).
out=$(call "$T/absent")
[ "$out" = "done_check=ko raison=a:stockage" ] && ok 9b "magasin absent refusé" || ko "9b [$out]"

# 9c. magasin lisible, aucune tâche Max -> a:none (seul cas où « none » est vrai).
mkstore "$T/s9c" "opencode/v4-flash-free" 42 'PASS' "$ENDP" Forge
out=$(call "$T/s9c")
[ "$out" = "done_check=ko raison=a:none" ] && ok 9c "aucune tâche Max refusée" || ko "9c [$out]"

# 9d. régression F4 : plus de chemin bâti sur le contexte env (HOME n'y est pas -> chaîne vide).
if grep -qE 'OC_(STORE_DIR|HOOKS_LOG): *\$\{\{ *env\.HOME *\}\}' "$ROOT/.github/workflows/opencode-fullrun.yml"; then
  ko "9d workflow construit un chemin sur env.HOME"
else
  ok 9d "workflow sans env.HOME"
fi

# 10. boucle : PASS vérifié + session inactive -> run-fullrun sort 0 avec arret=max_pass.
mkdir -p "$T/run"
cat >"$T/fake-oc" <<'EOF'
#!/usr/bin/env bash
sleep 60
EOF
chmod +x "$T/fake-oc"
cat >"$T/fake-done" <<'EOF'
#!/usr/bin/env bash
echo done_check=ok
EOF
chmod +x "$T/fake-done"
: >"$T/prompt.md"
env ANTENLY_DIR="$R" CI_DIR="$ROOT" OC_PROMPT_FILE="$T/prompt.md" OC_LOG="$T/run.log" \
    OC_LOG.status="$T/run.log.status" OC_MODEL_MAIN="opencode/v4-flash-free" OC_MODEL_CHAIN="opencode/v4-lite-free" \
    OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 OC_IDLE_SEC=30 OC_POLL_SEC=1 \
    OC_KILL_GRACE=1 OC_STORE_DIR="$T/run" OC_REPORT="$REPORT" OC_ISA="$ISA" OC_DONE_REPO="$R" \
    OC_DONE_CHECK_BIN="$T/fake-done" OC_DONE_CHECK_SEC=1 OC_DONE_IDLE_SEC=1 \
    OC_INTERNAL_LOG="$T/run/internal.log" \
    bash "$RUN" >"$T/run.out" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -qx 'arret=max_pass' "$T/run.log.status" \
   && grep -qx 'done_check=ok' "$T/run.log.status" \
   && ! grep -q 'error=empty' "$T/run.log.status"; then
  ok 10 "boucle : PASS vérifié -> rc 0, arret=max_pass"
else
  ko "10 rc=$rc $(tr '\n' ' ' <"$T/run.log.status" 2>/dev/null)"
fi

echo "résumé : $pass ok, $fail ko"
[ "$fail" -eq 0 ]
