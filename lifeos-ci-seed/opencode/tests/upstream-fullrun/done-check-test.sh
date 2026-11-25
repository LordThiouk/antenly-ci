#!/usr/bin/env bash
# Tests du validateur de fin (étape 4) : stockage opencode (SQLite et arbre JSON), hooks.log,
# vérificateurs relancés, arbre/rapport/ISA — et la sortie anticipée de run-fullrun.sh
# (`arret=max_pass`, rc 0, hors modèle).
# Usage : bash opencode/tests/done-check-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
DC="$ROOT/opencode/done_check.sh"
# shellcheck source=verdict-cli.lib
source "$HERE/verdict-cli.lib"
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
mkstore "$T/s1" "opencode/v4-flash-free" 42 $'Travail terminé.\n{"status":"pass"}' "$ENDP"
mklog Max
out=$(call "$T/s1"); [ "$out" = "done_check=ok" ] && ok 1 "PASS SQLite complet" || ko "1 [$out]"

# 2. arbre JSON complet -> ok (l'autre format de stockage)
mkjson "$T/s2" "opencode/v4-flash-free" 7 'VERDICT: PASS' "$ENDP"
out=$(call "$T/s2"); [ "$out" = "done_check=ok" ] && ok 2 "PASS arbre JSON" || ko "2 [$out]"

# 3. modèle non gratuit -> a:tokens
mkstore "$T/s3" "opencode/v4-pro" 42 'VERDICT: PASS' "$ENDP"
out=$(call "$T/s3"); [ "$out" = "done_check=ko raison=a:tokens" ] && ok 3 "modèle non gratuit refusé" || ko "3 [$out]"

# 4. sortie négative -> a:verdict
mkstore "$T/s4" "opencode/v4-flash-free" 42 'VERDICT: FAIL' "$ENDP"
out=$(call "$T/s4"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 4 "verdict négatif refusé" || ko "4 [$out]"

# 5. fin antérieure au dernier commit de code -> a:time
mkstore "$T/s5" "opencode/v4-flash-free" 42 'VERDICT: PASS' "$(( (COMMIT - 60) * 1000 ))"
out=$(call "$T/s5"); [ "$out" = "done_check=ko raison=a:time" ] && ok 5 "PASS antérieur au commit refusé" || ko "5 [$out]"

# 6. hooks.log sans ligne plugin -> b:hooks
mkstore "$T/s6" "opencode/v4-flash-free" 42 'VERDICT: PASS' "$ENDP"
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
# 9v. validate_only (OC_DONE_VALIDATE_ONLY=1) : seul d:isa-complete est sauté ; le reste reste exigé
printf -- '---\nphase: complete\n---\n' >"$ISA"
out=$(call "$T/s6" OC_DONE_VALIDATE_ONLY=1); [ "$out" = "done_check=ok" ] && ok 9vb "validate_only : ISA close acceptée" || ko "9vb [$out]"
out=$(call "$T/s6" OC_DONE_VALIDATE_ONLY=true); [ "$out" = "done_check=ko raison=d:isa-complete" ] && ok 9vc "validate_only : seule la valeur exacte 1 compte" || ko "9vc [$out]"
out=$(call "$T/s3" OC_DONE_VALIDATE_ONLY=1); [ "$out" = "done_check=ko raison=a:tokens" ] && ok 9vd "validate_only : les contrôles a restent exigés" || ko "9vd [$out]"
printf -- '---\nphase: climbing\n---\n' >"$ISA"

# 9b. magasin absent -> a:stockage : un chemin faux n'est pas « aucune tâche Max » (run F4).
out=$(call "$T/absent")
[ "$out" = "done_check=ko raison=a:stockage" ] && ok 9b "magasin absent refusé" || ko "9b [$out]"

# 9c. magasin lisible, aucune tâche Max -> a:none:Max (seul cas où « none » est vrai ; l'agent est nommé).
mkstore "$T/s9c" "opencode/v4-flash-free" 42 'VERDICT: PASS' "$ENDP" Forge
out=$(call "$T/s9c")
[ "$out" = "done_check=ko raison=a:none:Max" ] && ok 9c "aucune tâche Max refusée" || ko "9c [$out]"

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

# 10b (B1) : run-fullrun.sh vide OC_DONE_TEST_MODE / OC_VERDICT_CLI / OC_BUN / OC_VERDICT_TIMEOUT avant d'appeler done_check
# (espion : il note l'environnement qu'il reçoit), même quand le job les a injectés comme le ferait $GITHUB_ENV.
cat >"$T/spy-done" <<EOS
#!/usr/bin/env bash
echo called >>"$T/spy.called"
env | grep -E '^(OC_DONE_TEST_MODE|OC_VERDICT_CLI|OC_BUN|OC_VERDICT_TIMEOUT)=' >>"$T/spy.env"
echo done_check=ok
EOS
chmod +x "$T/spy-done"; : >"$T/spy.env"
env ANTENLY_DIR="$R" CI_DIR="$ROOT" OC_PROMPT_FILE="$T/prompt.md" OC_LOG="$T/run2.log" \
    OC_LOG.status="$T/run2.log.status" OC_MODEL_MAIN="opencode/v4-flash-free" OC_MODEL_CHAIN="opencode/v4-lite-free" \
    OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 OC_IDLE_SEC=30 OC_POLL_SEC=1 \
    OC_KILL_GRACE=1 OC_STORE_DIR="$T/run" OC_REPORT="$REPORT" OC_ISA="$ISA" OC_DONE_REPO="$R" \
    OC_DONE_CHECK_BIN="$T/spy-done" OC_DONE_CHECK_SEC=1 OC_DONE_IDLE_SEC=1 \
    OC_DONE_TEST_MODE=1 OC_VERDICT_CLI=/tmp/evil-cli.js OC_BUN=/tmp/evil-bun OC_VERDICT_TIMEOUT=99 \
    OC_INTERNAL_LOG="$T/run/internal2.log" \
    bash "$RUN" >"$T/run2.out" 2>&1
if [ -s "$T/spy.called" ] && [ ! -s "$T/spy.env" ]; then ok 10b "run-fullrun.sh : variables de test injectées non transmises à done_check"; else ko "10b $(tr '\n' ' ' <"$T/spy.env")"; fi

# 11. Verdict lu UNIQUEMENT dans une conclusion structurée (JSON final ou dernière ligne VERDICT:), jamais dans le corps
ENDP=$(( (COMMIT + 60) * 1000 ))
mkstore "$T/s11a" "opencode/v4-flash-free" 42 $'Le test a fail avant le correctif, le patch reject\u00e9 en v1, l\'ancien chemin \u00e9tait blocked, un FAIL, un BLOCK, REQUEST CHANGES au tour 1.\n\nVERDICT: PASS' "$ENDP"
out=$(call "$T/s11a"); [ "$out" = "done_check=ok" ] && ok 11a "PASS dont le corps contient fail/reject/blocked : accepté" || ko "11a [$out]"
mkstore "$T/s11b" "opencode/v4-flash-free" 42 $'Tout semble bon, pass, PASS, APPROVE, LGTM partout.\n{"verdict":"FAIL","reason":"x"}' "$ENDP"
out=$(call "$T/s11b"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 11b "JSON final FAIL refusé malgré PASS/APPROVE dans le corps" || ko "11b [$out]"
mkstore "$T/s11c" "opencode/v4-flash-free" 42 $'VERDICT: FAIL (tour 1)\n...corrig\u00e9...\nVERDICT: PASS' "$ENDP"
out=$(call "$T/s11c"); [ "$out" = "done_check=ok" ] && ok 11c "la dernière ligne VERDICT décide (FAIL puis PASS)" || ko "11c [$out]"
mkstore "$T/s11d" "opencode/v4-flash-free" 42 $'VERDICT: PASS (tour 1)\n...r\u00e9gression...\nVERDICT: BLOCKED' "$ENDP"
out=$(call "$T/s11d"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 11d "la dernière ligne VERDICT décide (PASS puis BLOCKED)" || ko "11d [$out]"
for k in "e:PASS sur la forme mais le test FAIL toujours" "f:APPROVE, LGTM, tout est pass" "g:REQUEST CHANGES — trou critique" "h:" "i:{\"foo\":\"bar\"}" "j:{\"verdict\":\"maybe\"}" "k:Le VERDICT: PASS est attendu mais pas rendu, voir ci-dessous"; do
  id=${k%%:*}; txt=${k#*:}
  mkstore "$T/s11$id" "opencode/v4-flash-free" 42 "$txt" "$ENDP"
  out=$(call "$T/s11$id"); [ "$out" = "done_check=ko raison=a:inconclusif" ] && ok "11$id" "sans verdict structuré = inconclusif, jamais PASS : « ${txt:-vide} »" || ko "11$id [$out]"
done
# 11r. Préfixe emoji/symbole (format de Max : « ✅ VERDICT: pass ») : lu ; un préfixe avec une lettre reste du corps
n=0
for k in "pass:✅ VERDICT: pass — aucun blocage" "pass:✔️ VERDICT: PASS" "pass:🟢 **VERDICT: pass**" "pass:- ✅ VERDICT: pass" "pass:> 🚀 VERDICT : Pass (tour 2)" \
         "fail:❌ VERDICT: fail — régression sur F3" "fail:⛔ VERDICT: blocked" "fail:tout semble pass"$'\n'"❌ VERDICT: fail"; do
  n=$((n + 1)); exp=${k%%:*}; txt=${k#*:}
  mkstore "$T/s11r$n" "opencode/v4-flash-free" 42 "$txt" "$ENDP"
  out=$(call "$T/s11r$n")
  if [ "$exp" = pass ]; then want="done_check=ok"; else want="done_check=ko raison=a:verdict"; fi
  [ "$out" = "$want" ] && ok "11r$n" "préfixe emoji/symbole : « ${txt%%$'\n'*} » → $exp" || ko "11r$n [$out]"
done
mkstore "$T/s11s" "opencode/v4-flash-free" 42 $'✅ VERDICT: fail (tour 1)\ncorrigé\n✅ VERDICT: pass' "$ENDP"
out=$(call "$T/s11s"); [ "$out" = "done_check=ok" ] && ok 11s "la dernière ligne ✅ VERDICT décide (fail puis pass)" || ko "11s [$out]"
n=0
for txt in "Le ✅ VERDICT: pass est attendu" "voir ✅ VERDICT: pass" "1. VERDICT: pass" "✅ VERDICT: concerns — deux réserves" "✅ VERDICT: pass | concerns | fail — avec la phrase qui décide"; do
  n=$((n + 1)); mkstore "$T/s11t$n" "opencode/v4-flash-free" 42 "$txt" "$ENDP"
  out=$(call "$T/s11t$n"); [ "$out" = "done_check=ko raison=a:inconclusif" ] && ok "11t$n" "inconclusif (lettre en préfixe, ou concerns, ou gabarit) : « $txt »" || ko "11t$n [$out]"
done
mkstore "$T/s11u" "opencode/v4-flash-free" 42 $'Revue.\n{"verdict":"pass"}' "$ENDP"
out=$(call "$T/s11u"); [ "$out" = "done_check=ok" ] && ok 11u "JSON final {verdict: pass} accepté" || ko "11u [$out]"
mkstore "$T/s11v" "opencode/v4-flash-free" 42 $'Revue.\n{"verdict":"fail"}' "$ENDP"
out=$(call "$T/s11v"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 11v "JSON final {verdict: fail} refusé" || ko "11v [$out]"
mkstore "$T/s11m" "opencode/v4-flash-free" 42 $'Exemple attendu : {"verdict":"fail"}\nEn r\u00e9alit\u00e9 tout est bon.\n{"verdict":"pass"}' "$ENDP"
out=$(call "$T/s11m"); [ "$out" = "done_check=ok" ] && ok 11m "faux JSON dans le corps puis vrai JSON final PASS : le final compte" || ko "11m [$out]"
mkstore "$T/s11n" "opencode/v4-flash-free" 42 $'Exemple : {"verdict":"pass"}\nMais non.\n{"verdict":"fail"}' "$ENDP"
out=$(call "$T/s11n"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 11n "faux JSON PASS dans le corps puis vrai JSON final FAIL : le final compte" || ko "11n [$out]"
mkstore "$T/s11o" "opencode/v4-flash-free" 42 $'Format attendu {"verdict":"fail"} — voir doc.\nVERDICT: PASS' "$ENDP"
out=$(call "$T/s11o"); [ "$out" = "done_check=ok" ] && ok 11o "JSON cité en milieu de corps : pas une conclusion, la ligne VERDICT décide" || ko "11o [$out]"
# 11p. Le JSON final ne compte QUE s'il n'y a aucune ligne VERDICT: ; priorité verdict > status > result
mkstore "$T/s11p" "opencode/v4-flash-free" 42 $'Revue FAIL puis corrigée\n{"status":"pass"}' "$ENDP"
out=$(call "$T/s11p"); [ "$out" = "done_check=ok" ] && ok 11p "sans ligne VERDICT : JSON final {status: pass} accepté (clé historique)" || ko "11p [$out]"
mkstore "$T/s11p2" "opencode/v4-flash-free" 42 $'✅ VERDICT: pass — ok' "$ENDP"
out=$(call "$T/s11p2"); [ "$out" = "done_check=ok" ] && ok 11p2 "« ✅ VERDICT: pass — ok » : pass" || ko "11p2 [$out]"
mkstore "$T/s11p3" "opencode/v4-flash-free" 42 $'VERDICT: FAIL\n{"status":"pass"}' "$ENDP"
out=$(call "$T/s11p3"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 11p3 "VERDICT: FAIL + JSON final {status: pass} : fail, le JSON ne l'emporte jamais" || ko "11p3 [$out]"
mkstore "$T/s11p4" "opencode/v4-flash-free" 42 $'VERDICT: PASS\nExemple de sortie attendue : {"status":"fail"}' "$ENDP"
out=$(call "$T/s11p4"); [ "$out" = "done_check=ok" ] && ok 11p4 "VERDICT: PASS + exemple JSON {status: fail} cité en dernier : pass" || ko "11p4 [$out]"
mkstore "$T/s11p5" "opencode/v4-flash-free" 42 $'Exemple : {"status":"fail"}\nVERDICT: PASS' "$ENDP"
out=$(call "$T/s11p5"); [ "$out" = "done_check=ok" ] && ok 11p5 "exemple JSON {status: fail} en milieu de corps + VERDICT: PASS : pass" || ko "11p5 [$out]"
mkstore "$T/s11p6" "opencode/v4-flash-free" 42 $'VERDICT: pass | concerns | fail' "$ENDP"
out=$(call "$T/s11p6"); [ "$out" = "done_check=ko raison=a:inconclusif" ] && ok 11p6 "ligne modèle « VERDICT: pass | concerns | fail » : inconclusif" || ko "11p6 [$out]"
mkstore "$T/s11p7" "opencode/v4-flash-free" 42 $'✅ VERDICT: concerns — deux réserves\n{"verdict":"pass"}' "$ENDP"
out=$(call "$T/s11p7"); [ "$out" = "done_check=ko raison=a:inconclusif" ] && ok 11p7 "VERDICT: concerns + JSON pass : inconclusif (le JSON ne remplace pas une ligne VERDICT)" || ko "11p7 [$out]"
mkstore "$T/s11p8" "opencode/v4-flash-free" 42 $'VERDICT: PASS\nrelu : voir ci-dessous\nVERDICT: concerns' "$ENDP"
out=$(call "$T/s11p8"); [ "$out" = "done_check=ko raison=a:inconclusif" ] && ok 11p8 "la DERNIÈRE ligne VERDICT: décide, même non lisible (PASS puis concerns)" || ko "11p8 [$out]"
n=0
for k in 'ok:{"verdict":"pass","status":"fail"}' 'ko:{"verdict":"fail","status":"pass"}' 'ok:{"status":"pass","result":"fail"}' 'ko:{"result":"fail"}' 'ko:{"verdict":"maybe","status":"pass"}'; do
  n=$((n + 1)); exp=${k%%:*}; txt=${k#*:}
  mkstore "$T/s11q$n" "opencode/v4-flash-free" 42 "Revue.
$txt" "$ENDP"
  out=$(call "$T/s11q$n"); if [ "$exp" = ok ]; then want="done_check=ok"; else want_re="^done_check=ko raison=a:(verdict|inconclusif)$"; fi
  if [ "$exp" = ok ]; then [ "$out" = "$want" ] && ok "11q$n" "priorité JSON verdict > status > result : $txt → pass" || ko "11q$n [$out]"
  else [[ "$out" =~ $want_re ]] && ok "11q$n" "priorité JSON verdict > status > result : $txt → non pass" || ko "11q$n [$out]"; fi
done
mkstore "$T/s11q" "opencode/v4-flash-free" 42 $'{"verdict":"pass","note":"le bloc {fail} est cit\u00e9"}' "$ENDP"
out=$(call "$T/s11q"); [ "$out" = "done_check=ok" ] && ok 11q "accolades dans une chaîne du JSON final" || ko "11q [$out]"

# 12. done_agents (Max,Silas) : a:none nomme le PREMIER agent sans tâche « completed » ; rien n'est assoupli
#     (même exigences par agent qu'avant : fin postérieure au dernier commit de code, modèle gratuit, verdict).
mkstore2() { # $1=dossier ; puis des « Agent:fin_ms » ; chaque tâche : modèle gratuit, 42 tokens, VERDICT: PASS
  local d="$1"; shift
  python3 - "$d" "$@" <<'PY'
import json, os, sqlite3, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
con = sqlite3.connect(os.path.join(d, "opencode.db"))
con.execute("create table part(session_id text, data text)")
con.execute("create table message(session_id text, data text)")
for i, spec in enumerate(sys.argv[2:]):
    agent, end = spec.split(":")
    part = {"type": "tool", "tool": "task",
            "state": {"status": "completed", "input": {"subagent_type": agent},
                      "metadata": {"sessionId": "child%d" % i, "model": {"modelID": "opencode/v4-flash-free"}},
                      "time": {"end": int(end)}, "output": "Revue.\nVERDICT: PASS"}}
    # une session par agent : reprise / rotation de modèle (done_check ne filtre aucune session)
    con.execute("insert into part values(?,?)", ("sess%d" % i, json.dumps(part)))
    con.execute("insert into message values(?,?)", ("child%d" % i, json.dumps(
        {"role": "assistant", "modelID": "opencode/v4-flash-free", "tokens": {"output": 42}})))
con.commit()
PY
}
HOOKS2="$T/hooks2.log"
for a in Max Silas; do
  printf '%s SUBAGENT done subagent_type=%s ok=true session=s call=c\n' \
    "$(date -u -d "@$((COMMIT + 5))" +%Y-%m-%dT%H:%M:%S.000Z)" "$a"
done >"$HOOKS2"
call2() { local store="$1"; shift; call "$store" OC_DONE_AGENTS=Max,Silas OC_HOOKS_LOG="$HOOKS2" "$@"; }

mkstore2 "$T/s12a" "Max:$ENDP"
out=$(call2 "$T/s12a"); [ "$out" = "done_check=ko raison=a:none:Silas" ] && ok 12a "Max sans Silas : a:none:Silas" || ko "12a [$out]"
mkstore2 "$T/s12b" "Silas:$ENDP"
out=$(call2 "$T/s12b"); [ "$out" = "done_check=ko raison=a:none:Max" ] && ok 12b "Silas sans Max : a:none:Max" || ko "12b [$out]"
mkstore2 "$T/s12c" "Max:$ENDP" "Silas:$ENDP"
out=$(call2 "$T/s12c"); [ "$out" = "done_check=ok" ] && ok 12c "Max + Silas valides (sessions différentes) : ok" || ko "12c [$out]"
out=$(call2 "$T/s12c" OC_DONE_AGENTS=Max); [ "$out" = "done_check=ok" ] && ok 12c2 "done_agents=Max seul : inchangé (ok)" || ko "12c2 [$out]"
mkdir -p "$T/s12e"; mkstore2 "$T/s12e"
out=$(call2 "$T/s12e"); [ "$out" = "done_check=ko raison=a:none:Max" ] && ok 12e "aucun agent : le premier (Max) est nommé" || ko "12e [$out]"
out=$(call "$T/s12a" OC_DONE_AGENTS=Max OC_HOOKS_LOG="$HOOKS2"); [ "$out" = "done_check=ok" ] && ok 12f "done_agents=Max, Max présent : ok" || ko "12f [$out]"
mkstore2 "$T/s12g" "Silas:$ENDP"
out=$(call "$T/s12g" OC_DONE_AGENTS=Max OC_HOOKS_LOG="$HOOKS2"); [ "$out" = "done_check=ko raison=a:none:Max" ] && ok 12g "done_agents=Max, aucun Max : a:none:Max" || ko "12g [$out]"
# ANY (job borné) : un seul agent autorisé doit avoir rendu un vrai PASS ; a et b portent sur le MÊME agent.
out=$(call "$T/s12a" OC_DONE_AGENTS=Max,Silas OC_DONE_AGENTS_ANY=1 OC_HOOKS_LOG="$HOOKS2"); [ "$out" = "done_check=ok" ] && ok 12h "ANY : Max seul parmi Max,Silas -> ok" || ko "12h [$out]"
out=$(call "$T/s12b" OC_DONE_AGENTS=Max,Silas OC_DONE_AGENTS_ANY=1 OC_HOOKS_LOG="$HOOKS2"); [ "$out" = "done_check=ok" ] && ok 12i "ANY : Silas seul parmi Max,Silas -> ok" || ko "12i [$out]"
out=$(call "$T/s12e" OC_DONE_AGENTS=Max,Silas OC_DONE_AGENTS_ANY=1 OC_HOOKS_LOG="$HOOKS2"); [ "$out" = "done_check=ko raison=a:none:Max" ] && ok 12j "ANY : aucun agent -> a:none:Max" || ko "12j [$out]"
HOOKS_MAX_ONLY="$T/hooks-max.log"
printf '%s SUBAGENT done subagent_type=Max ok=true session=s call=c\n' \
  "$(date -u -d "@$((COMMIT + 5))" +%Y-%m-%dT%H:%M:%S.000Z)" >"$HOOKS_MAX_ONLY"
out=$(call "$T/s12c" OC_DONE_AGENTS=Max,Silas OC_DONE_AGENTS_ANY=1 OC_HOOKS_LOG="$HOOKS_MAX_ONLY"); [ "$out" = "done_check=ok" ] && ok 12k "ANY : Max (a+b) suffit même si le hook de Silas manque" || ko "12k [$out]"
HOOKS_SILAS_ONLY="$T/hooks-silas.log"
printf '%s SUBAGENT done subagent_type=Silas ok=true session=s call=c\n' \
  "$(date -u -d "@$((COMMIT + 5))" +%Y-%m-%dT%H:%M:%S.000Z)" >"$HOOKS_SILAS_ONLY"
out=$(call "$T/s12c" OC_DONE_AGENTS=Max,Silas OC_DONE_AGENTS_ANY=1 OC_HOOKS_LOG="$HOOKS_SILAS_ONLY"); [ "$out" = "done_check=ok" ] && ok 12l "ANY : un agent sans hook n'empêche pas un autre agent (a+b)" || ko "12l [$out]"

# Max PASS sur un ancien état : du code a changé APRÈS lui -> refus (a:time), même si Silas est frais.
cp -r "$R" "$T/repo2"; ( cd "$T/repo2" && echo apres >b.txt && git add -A \
  && GIT_COMMITTER_DATE="@$((COMMIT + 100))" GIT_AUTHOR_DATE="@$((COMMIT + 100))" git commit -qm "code apres" )
mkstore2 "$T/s12d" "Max:$ENDP" "Silas:$(( (COMMIT + 200) * 1000 ))"
out=$(call2 "$T/s12d" OC_DONE_REPO="$T/repo2"); [ "$out" = "done_check=ko raison=a:time" ] \
  && ok 12d "Max PASS antérieur à un commit de code postérieur : refusé (a:time)" || ko "12d [$out]"
out=$(call2 "$T/s12d"); [ "$out" = "done_check=ok" ] && ok 12d2 "même stockage, dépôt sans commit postérieur : ok (le refus vient bien du commit)" || ko "12d2 [$out]"

# 13. Source unique du verdict (incident 22 nov. 2026) : le pipeline lifeos lisait pass dans l'enveloppe
#     opencode 1.19 (<task id state="completed"> … <task_result>), l'ancien lecteur python lisait « inconclusif ».
#     done_check.sh délègue désormais à LIFEOS/TOOLS/FullRunVerdict.ts (pass|fail|unknown, code 0/1/3).
env119() { printf '<task id="ses_abc" state="%s">\n<summary>Revue</summary>\n<task_result>\n%s\n</task_result>\n</task>' "$1" "$2"; }
mkstore "$T/s13a" "opencode/v4-flash-free" 42 "$(env119 completed $'Revue terminée.\n{"status":"pass"}')" "$ENDP"
out=$(call "$T/s13a"); [ "$out" = "done_check=ok" ] && ok 13a "enveloppe <task> 1.19 + JSON final pass : pass (comme le pipeline)" || ko "13a [$out]"
mkstore "$T/s13b" "opencode/v4-flash-free" 42 "$(env119 completed 'VERDICT: FAIL')" "$ENDP"
out=$(call "$T/s13b"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 13b "enveloppe 1.19 + VERDICT: FAIL : refusé" || ko "13b [$out]"
mkstore "$T/s13c" "opencode/v4-flash-free" 42 "$(env119 error '{"status":"pass"}')" "$ENDP"
out=$(call "$T/s13c"); [ "$out" = "done_check=ko raison=a:inconclusif" ] && ok 13c "enveloppe 1.19 en erreur + JSON pass cité : inconclusif, jamais pass" || ko "13c [$out]"
mkstore "$T/s13d" "opencode/v4-flash-free" 42 $'task_id: ses_x (for resuming...)\n\n<task_result>\nVERDICT: PASS\n</task_result>' "$ENDP"
out=$(call "$T/s13d"); [ "$out" = "done_check=ok" ] && ok 13d "ancienne enveloppe task_id/<task_result> + VERDICT: PASS : pass" || ko "13d [$out]"
# CLI absent ou défaillant : jamais pass, panne nommée (a:verdict-cli), jamais « inconclusif » silencieux.
# 13e (M2) : indépendant de la machine — le CLI absent est SIMULÉ par la configuration du test (mode test +
# OC_VERDICT_CLI inexistant), jamais par l'absence de /opt ou de ~/.claude. Un ~/.claude qui contient un vrai
# CLI (machine du principal) ne doit PAS servir de repli : on le fabrique ici pour le prouver.
mkstore "$T/s13e" "opencode/v4-flash-free" 42 $'Revue.\n{"status":"pass"}' "$ENDP"
FAKEHOME="$T/fakehome"; mkdir -p "$FAKEHOME/.claude/LIFEOS/TOOLS" "$FAKEHOME/.bun/bin"
cp "$OC_VERDICT_CLI" "$FAKEHOME/.claude/LIFEOS/TOOLS/FullRunVerdict.ts" || ko "13e préparation : copie de FullRunVerdict.ts impossible"
cp "$(dirname "$OC_VERDICT_CLI")/FullRunVerdictParse.ts" "$FAKEHOME/.claude/LIFEOS/TOOLS/" || ko "13e préparation : copie de FullRunVerdictParse.ts impossible"
out=$(call "$T/s13e" HOME="$FAKEHOME" OC_VERDICT_CLI=/nonexistent/FullRunVerdict.ts); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 13e "CLI introuvable (config de test, ~/.claude garni ignoré) : a:verdict-cli, jamais ok" || ko "13e [$out]"
FAKE="$T/fakebun"; mkdir -p "$FAKE"
printf '#!/bin/sh\ncat >/dev/null; echo pass; exit 3\n' >"$FAKE/bun-pass-rc3"; chmod +x "$FAKE/bun-pass-rc3"
out=$(call "$T/s13e" OC_BUN="$FAKE/bun-pass-rc3"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 13f "stdout « pass » mais code 3 : pas pass (le code ET la sortie doivent dire pass)" || ko "13f [$out]"
printf '#!/bin/sh\ncat >/dev/null; echo unknown; exit 0\n' >"$FAKE/bun-unknown-rc0"; chmod +x "$FAKE/bun-unknown-rc0"
out=$(call "$T/s13e" OC_BUN="$FAKE/bun-unknown-rc0"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 13g "code 0 mais sortie « unknown » : pas pass" || ko "13g [$out]"
printf '#!/bin/sh\ncat >/dev/null; echo unknown; exit 3\n' >"$FAKE/bun-unknown"; chmod +x "$FAKE/bun-unknown"
out=$(call "$T/s13e" OC_BUN="$FAKE/bun-unknown"); [ "$out" = "done_check=ko raison=a:inconclusif" ] && ok 13h "code 3 (unknown) : inconclusif" || ko "13h [$out]"
# 13i bun absent ; 13j délai dépassé ; 13k « pass » écrit seulement sur stderr.
out=$(call "$T/s13e" OC_BUN=/nonexistent/bun); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 13i "bun absent : a:verdict-cli, jamais ok" || ko "13i [$out]"
printf '#!/bin/sh\ncat >/dev/null; sleep 6; echo pass; exit 0\n' >"$FAKE/bun-slow"; chmod +x "$FAKE/bun-slow"
t0=$(date +%s); out=$(call "$T/s13e" OC_BUN="$FAKE/bun-slow" OC_VERDICT_TIMEOUT=1); dt=$(( $(date +%s) - t0 ))
[ "$out" = "done_check=ko raison=a:verdict-cli" ] && [ "$dt" -lt 6 ] && ok 13j "CLI trop lent (timeout) : a:verdict-cli, jamais ok" || ko "13j [$out] ${dt}s"
printf '#!/bin/sh\ncat >/dev/null; echo pass >&2; exit 0\n' >"$FAKE/bun-stderr"; chmod +x "$FAKE/bun-stderr"
out=$(call "$T/s13e" OC_BUN="$FAKE/bun-stderr"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 13k "« pass » seulement sur stderr (stdout vide, code 0) : a:verdict-cli, jamais ok" || ko "13k [$out]"
# 13l (M5) : un CLI en panne sur UNE tâche requise donne a:verdict-cli même si une autre tâche du même agent passe.
python3 - "$T/s13l" "$ENDP" <<'PY'
import json, os, sqlite3, sys
d, end = sys.argv[1], int(sys.argv[2]); os.makedirs(d, exist_ok=True)
con = sqlite3.connect(os.path.join(d, "opencode.db"))
con.execute("create table part(session_id text, data text)"); con.execute("create table message(session_id text, data text)")
for i, out in ((1, "BOOM {\"status\":\"pass\"}"), (2, "{\"status\":\"pass\"}")):
    part = {"type": "tool", "tool": "task", "state": {"status": "completed", "input": {"subagent_type": "Max"},
            "metadata": {"sessionId": "child%d" % i, "model": {"modelID": "opencode/v4-flash-free"}},
            "time": {"end": end}, "output": out}}
    msg = {"role": "assistant", "modelID": "opencode/v4-flash-free", "tokens": {"input": 10, "output": 42}}
    con.execute("insert into part values('s1',?)", (json.dumps(part),)); con.execute("insert into message values(?,?)", ("child%d" % i, json.dumps(msg)))
con.commit()
PY
printf '#!/bin/sh\nin=$(cat)\ncase "$in" in *BOOM*) exit 9;; esac\necho pass; exit 0\n' >"$FAKE/bun-boom-once"; chmod +x "$FAKE/bun-boom-once"
out=$(call "$T/s13l" OC_BUN="$FAKE/bun-boom-once"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 13l "M5 : panne CLI sur une tâche requise + autre tâche pass : a:verdict-cli (pas de continue permissif)" || ko "13l [$out]"

printf 'bunfig.toml\nevil-preload.js\n' >>"$R/.git/info/exclude"  # le piège ne doit pas salir l'arbre (d:arbre-sale)
# 13m (B2) : bunfig.toml piégé dans le cwd du run, vrai bun, mode test : le CLI tourne dans son propre dossier.
mkstore "$T/s13m" "opencode/v4-flash-free" 42 "$(env119 completed 'VERDICT: FAIL')" "$ENDP"
printf 'console.log("pass"); process.exit(0)\n' >"$R/evil-preload.js"; printf 'preload = ["./evil-preload.js"]\n' >"$R/bunfig.toml"
out=$(call "$T/s13m" OC_BUN=); rm -f "$R/evil-preload.js" "$R/bunfig.toml"
[ "$out" = "done_check=ko raison=a:verdict" ] && ok 13m "bunfig.toml piégé (preload) dans le cwd du run : sans effet, FAIL => a:verdict" || ko "13m [$out]"
# 13o : OC_DONE_VALIDATE_ONLY injecté n'affaiblit jamais le verdict (valeur 1 ou autre).
for v in 1 true yes; do
  out=$(call "$T/s13m" OC_DONE_VALIDATE_ONLY=$v); [ "$out" = "done_check=ko raison=a:verdict" ] && ok "13o-$v" "OC_DONE_VALIDATE_ONLY=$v injecté : un FAIL reste a:verdict" || ko "13o-$v [$out]"
done

# 14. Chemin de PRODUCTION : vrai bundle construit, copié en root dans /opt/fullrun-tools avec un bun et un bunfig root,
# SANS OC_VERDICT_CLI ni mode test. Demande root ou `sudo -n` ; OC_REQUIRE_PROD_TESTS=1 (CI) refuse de sauter.
# M3 : ne déplace JAMAIS un /opt/fullrun-tools existant (il est alors sauté, ou ko en CI) ; verrou flock contre les
# exécutions concurrentes ; /opt et le marqueur de mode test sont restaurés à la sortie.
PT=/opt/fullrun-tools; MARK=/etc/fullrun-done-test-mode
if [ "$(id -u)" = 0 ]; then SU=""; elif sudo -n true 2>/dev/null; then SU="sudo -n"; else SU="NONE"; fi
skip14() { if [ "${OC_REQUIRE_PROD_TESTS:-}" = 1 ]; then ko "14 chemin de production : $1 (OC_REQUIRE_PROD_TESTS=1)"; else echo "skip 14 ($1)"; fi; }
exec 9>/tmp/fullrun-prod-tests.lock
if [ "$SU" = NONE ]; then skip14 "ni root ni sudo -n"
elif ! flock -n 9; then skip14 "exécution concurrente (verrou /tmp/fullrun-prod-tests.lock)"
elif [ -e "$PT" ]; then skip14 "$PT existe déjà : jamais déplacé"
else
  BUNDLE="$T/FullRunVerdict.js"
  BUNBIN=$(command -v bun || echo "$HOME/.bun/bin/bun")
  bun build "$OC_VERDICT_CLI" --target bun --outfile "$BUNDLE" >/dev/null 2>&1 || ko "14 bun build du bundle"
  OPT_MODE=$(stat -c %a /opt); MARK_SAVED=""
  if [ -e "$MARK" ]; then MARK_SAVED="$T/mark-saved"; $SU mv "$MARK" "$MARK_SAVED"; fi
  restore_pt() { $SU rm -rf "$PT"; $SU chmod "$OPT_MODE" /opt; $SU rm -f "$MARK"; [ -n "$MARK_SAVED" ] && $SU mv "$MARK_SAVED" "$MARK"; true; }
  trap 'restore_pt; rm -rf "$T"' EXIT
  install_pt() { $SU rm -rf "$PT"; $SU chmod 0755 /opt; $SU install -d -o root -g root -m 0755 "$PT"
    $SU install -o root -g root -m 0644 "$BUNDLE" "$PT/FullRunVerdict.js"; $SU install -o root -g root -m 0755 "$BUNBIN" "$PT/bun"
    printf '# bunfig vide (root) : rien ne se précharge\n' >"$T/bunfig.toml"; $SU install -o root -g root -m 0644 "$T/bunfig.toml" "$PT/bunfig.toml"; }
  # Production : aucun env d'override, aucun mode test.
  callp() { local store="$1"; shift
    env -u OC_DONE_TEST_MODE -u OC_VERDICT_CLI -u OC_BUN -u OC_VERDICT_TIMEOUT \
        OC_STORE_DIR="$store" OC_HOOKS_LOG="$HOOKS" OC_REPORT="$REPORT" OC_ISA="$ISA" OC_DONE_REPO="$R" "$@" bash "$DC" 2>>"$T/callp.err"; }
  # Injection comme le ferait $GITHUB_ENV : mode test + faux CLI + faux bun « toujours pass » dans l'environnement.
  printf '#!/bin/sh\ncat >/dev/null; echo pass; exit 0\n' >"$FAKE/bun-always-pass"; chmod +x "$FAKE/bun-always-pass"; : >"$FAKE/fake-cli.js"
  INJ=(OC_DONE_TEST_MODE=1 OC_VERDICT_CLI="$FAKE/fake-cli.js" OC_BUN="$FAKE/bun-always-pass")
  mkstore "$T/s14a" "opencode/v4-flash-free" 42 "$(env119 completed $'Revue terminée.\n{"status":"pass"}')" "$ENDP"
  mkstore "$T/s14b" "opencode/v4-flash-free" 42 "$(env119 completed 'VERDICT: FAIL')" "$ENDP"
  install_pt
  # Diagnostic (jamais de secret : chemins, uid, modes) : si le chemin de production est refusé, dit pourquoi.
  : >"$T/callp.err"; out=$(callp "$T/s14a")
  if [ "$out" != "done_check=ok" ]; then
    echo "diag 14 : sortie [$out] ; $(tr '\n' ' ' <"$T/callp.err")"
    stat -c 'diag %n uid=%u gid=%g mode=%a type=%F' / /opt "$PT" "$PT"/* 2>&1 | sed 's/^/  /'
    echo "diag uid=$(id -u) bun=$BUNBIN -> $(readlink -f "$BUNBIN") GITHUB_ACTIONS=${GITHUB_ACTIONS:-}"
  fi
  out=$(callp "$T/s14a"); [ "$out" = "done_check=ok" ] && ok 14a "production : bundle réel + bun root, sans OC_VERDICT_CLI ni mode test : pass" || ko "14a [$out]"
  out=$(callp "$T/s14b"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 14b "production : VERDICT: FAIL refusé par le vrai bundle" || ko "14b [$out]"
  out=$(callp "$T/s14b" OC_BUN="$FAKE/bun-always-pass" OC_VERDICT_CLI="$FAKE/fake-cli.js"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 14c "hors mode test, OC_BUN/OC_VERDICT_CLI ignorés : le CLI root l'emporte (FAIL reste refusé)" || ko "14c [$out]"
  out=$(callp "$T/s14b" OC_DONE_TEST_MODE=0 OC_BUN="$FAKE/bun-always-pass"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 14c2 "OC_DONE_TEST_MODE différent de 1 : overrides toujours ignorés" || ko "14c2 [$out]"
  # B1 : mode test injecté sous GITHUB_ACTIONS sans marqueur root : refusé, le CLI root décide quand même.
  out=$(callp "$T/s14b" GITHUB_ACTIONS=true "${INJ[@]}"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 14j "GITHUB_ACTIONS + mode test/CLI/bun injectés (comme GITHUB_ENV), sans marqueur : le CLI root décide (FAIL => a:verdict)" || ko "14j [$out]"
  $SU install -o root -g root -m 0644 /dev/null "$MARK"
  out=$(callp "$T/s14b" GITHUB_ACTIONS=true "${INJ[@]}"); [ "$out" = "done_check=ok" ] && ok 14k "marqueur root présent (suite de tests CI) : le mode test est honoré" || ko "14k [$out]"
  $SU chmod 0666 "$MARK"; out=$(callp "$T/s14b" GITHUB_ACTIONS=true "${INJ[@]}"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 14l "marqueur inscriptible par tous : ignoré, le CLI root décide" || ko "14l [$out]"
  $SU chown 65534:65534 "$MARK"; $SU chmod 0644 "$MARK"; out=$(callp "$T/s14b" GITHUB_ACTIONS=true "${INJ[@]}"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 14l2 "marqueur non root : ignoré" || ko "14l2 [$out]"
  $SU rm -f "$MARK"
  # B2 : bunfig.toml piégé (preload) dans le cwd du run : le CLI tourne ailleurs, avec la config root.
  printf 'console.log("pass"); process.exit(0)\n' >"$R/evil-preload.js"; printf 'preload = ["./evil-preload.js"]\n' >"$R/bunfig.toml"
  out=$(callp "$T/s14b"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 14n "bunfig.toml piégé dans le cwd du run : sans effet (FAIL => a:verdict)" || ko "14n [$out]"
  rm -f "$R/evil-preload.js" "$R/bunfig.toml"
  # Env minimal : une variable BUN_* héritée n'atteint pas le CLI (BUN_OPTIONS=--preload d'un script qui écrit « pass »).
  printf 'console.log("pass"); process.exit(0)\n' >"$T/evil-env.js"
  out=$(callp "$T/s14b" BUN_OPTIONS="--preload $T/evil-env.js" NODE_OPTIONS="--require $T/evil-env.js"); [ "$out" = "done_check=ko raison=a:verdict" ] && ok 14o "BUN_OPTIONS / NODE_OPTIONS hérités : sans effet (env minimal)" || ko "14o [$out]"
  # Bundle absent / bun absent / bunfig absent / fichiers non root, inscriptibles, liens, ancêtre inscriptible.
  $SU rm -f "$PT/FullRunVerdict.js"; out=$(callp "$T/s14a"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14d "bundle absent : a:verdict-cli" || ko "14d [$out]"
  install_pt; $SU rm -f "$PT/bun"; out=$(callp "$T/s14a"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14e "bun root absent : a:verdict-cli (pas de bun du PATH)" || ko "14e [$out]"
  install_pt; $SU rm -f "$PT/bunfig.toml"; out=$(callp "$T/s14a"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14e2 "bunfig root absent : a:verdict-cli" || ko "14e2 [$out]"
  install_pt; $SU chown 65534:65534 "$PT/FullRunVerdict.js"; out=$(callp "$T/s14a"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14f "bundle non root : a:verdict-cli" || ko "14f [$out]"
  install_pt; $SU chmod 0664 "$PT/FullRunVerdict.js"; out=$(callp "$T/s14a"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14g "bundle inscriptible par le groupe : a:verdict-cli" || ko "14g [$out]"
  install_pt; $SU chmod 0757 "$PT"; out=$(callp "$T/s14a"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14h "dossier inscriptible par tous : a:verdict-cli" || ko "14h [$out]"
  install_pt; $SU chown 65534:65534 "$PT/bun"; out=$(callp "$T/s14a"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14i "bun non root : a:verdict-cli" || ko "14i [$out]"
  install_pt; $SU chown 65534:65534 "$PT/bunfig.toml"; out=$(callp "$T/s14a"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14i2 "bunfig non root : a:verdict-cli" || ko "14i2 [$out]"
  # M4 : lien symbolique (fichier) et ancêtre inscriptible (/opt) refusés.
  install_pt; $SU mv "$PT/FullRunVerdict.js" "$PT/real.js"; $SU ln -s "$PT/real.js" "$PT/FullRunVerdict.js"
  out=$(callp "$T/s14a"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14p "bundle = lien symbolique (même vers un fichier root) : a:verdict-cli" || ko "14p [$out]"
  install_pt; $SU chmod 0775 /opt; out=$(callp "$T/s14a"); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14q "ancêtre (/opt) inscriptible par le groupe : a:verdict-cli" || ko "14q [$out]"
  $SU chmod 0755 /opt; $SU chown 65534:65534 /opt; out=$(callp "$T/s14a"); $SU chown root:root /opt
  [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 14r "ancêtre (/opt) non root : a:verdict-cli" || ko "14r [$out]"
  install_pt; out=$(callp "$T/s14a"); [ "$out" = "done_check=ok" ] && ok 14s "après restauration des droits : pass de nouveau" || ko "14s [$out]"
  restore_pt; trap 'rm -rf "$T"' EXIT
fi

# 15. Workflows et appelants.
if grep -rnE "OC_DONE_TEST_MODE[[:space:]]*[:=]" "$ROOT/.github" >/dev/null 2>&1; then
  ko "15a un workflow pose OC_DONE_TEST_MODE (réservé aux scripts de test)"; else ok 15a "aucun workflow ne pose OC_DONE_TEST_MODE"; fi
FREEZE=$(awk '/CLI de verdict lifeos/{f=1} /fin du CLI de verdict/{f=0} f' "$ROOT/.github/workflows/opencode-fullrun.yml")
if [ -n "$FREEZE" ] && ! printf '%s' "$FREEZE" | grep -q '::warning::' && printf '%s' "$FREEZE" | grep -q 'exit 1' \
   && printf '%s' "$FREEZE" | grep -q '\$T/bun' && printf '%s' "$FREEZE" | grep -q 'bunfig.toml'; then
  ok 15b "étape de gel : échec en dur sans bundle (exit 1, pas de ::warning::), bun et bunfig root copiés"; else ko "15b étape de gel du bundle"; fi
if grep -q "ref: 4fac2d59de94bf6a5fa6c68c7f09874a2f9cd634" "$ROOT/.github/workflows/ci.yml" && ! grep -q "ref: main" "$ROOT/.github/workflows/ci.yml"; then
  ok 15c "ci.yml épingle lifeos au même SHA (4fac2d5, merge lifeos#24 : CLI de verdict + préflight)"; else ko "15c pin lifeos dans ci.yml"; fi
if grep -q 'OC_REQUIRE_PROD_TESTS: "1"' "$ROOT/.github/workflows/ci.yml"; then ok 15d "ci.yml exige les tests de chemin de production"; else ko "15d OC_REQUIRE_PROD_TESTS"; fi
# M2 : le dossier de gel ($T) du workflow, la constante de done_check.sh et les tests sont la MÊME valeur.
FT=$(awk '/^ *T=\/opt\/fullrun-tools/{t=$1} /CLI de verdict lifeos/{print t; exit}' "$ROOT/.github/workflows/opencode-fullrun.yml" | sed 's/;$//')
DCDIR=$(sed -n "s/^PROD_CLI = '\(.*\)\/FullRunVerdict.js'/\1/p" "$DC")
[ "$FT" = "T=$PT" ] && [ "$DCDIR" = "$PT" ] && ok 15e "dossier de gel du workflow = $PT = constante de done_check.sh = constante des tests" || ko "15e gel [$FT] done_check [$DCDIR] test [$PT]"
grep -q 'etc/fullrun-done-test-mode' "$ROOT/.github/workflows/ci.yml" && grep -q "$MARK" "$DC" && ok 15f "ci.yml pose le marqueur root du mode test ($MARK), lu par done_check.sh" || ko "15f marqueur mode test"
# B1 (v3) : UN seul point d'appel de done_check.sh, qui purge le mode test et les surcharges du CLI.
LIBF="$ROOT/opencode/done-check-call.sh"
if grep -qF 'env -u OC_DONE_TEST_MODE -u OC_VERDICT_CLI -u OC_BUN -u OC_VERDICT_TIMEOUT bash "$1"' "$LIBF" 2>/dev/null; then
  ok 15g1 "done-check-call.sh : fullrun_done_check purge OC_DONE_TEST_MODE/OC_VERDICT_CLI/OC_BUN/OC_VERDICT_TIMEOUT"; else ko "15g1 fonction centrale sans purge"; fi
# Détecteur d'appel direct (hors lib, tests, done_check.sh lui-même, commentaires) : refuse bash/sh/exec sur done_check ou $DC / $DONE_CHECK_BIN,
# et toute exécution directe de ".../done_check.sh".
direct_calls() { # $1 = racine du dépôt ; imprime fichier:ligne des appels directs
  grep -rnE --include='*.sh' --include='*.yml' --include='*.yaml' \
    -e '(^|[[:space:];(&|])(bash|sh|exec)[[:space:]]+"?[^[:space:]]*done_check' \
    -e '(^|[[:space:];(&|])(bash|sh|exec)[[:space:]]+"\$\{?(DC|DONE_CHECK_BIN)\}?"' \
    -e '"\$[A-Za-z_{}]*/done_check\.sh"[[:space:]]*(2>|\||\)|$|OC_)' \
    -e '(^|[[:space:]])\./done_check\.sh' \
    "$1/opencode" "$1/.github" 2>/dev/null \
  | grep -vE '^[^:]*opencode/tests/|^[^:]*opencode/done-check-call\.sh:|^[^:]*opencode/done_check\.sh:' \
  | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' | grep -v 'fullrun_done_check'
}
found=$(direct_calls "$ROOT")
[ -z "$found" ] && ok 15g2 "aucun appel direct (non purgé) de done_check.sh dans le dépôt" || ko "15g2 appels directs :$(printf '\n  %s' $found)"
# Témoin négatif : le détecteur DOIT voir chaque forme d'appel direct, et laisser passer l'appel centralisé.
DT="$T/dc-detect"; mkdir -p "$DT/opencode" "$DT/.github"; nd=0; nm=0
for form in 'bash "$DC" 2>/dev/null' 'bash "$DONE_CHECK_BIN" | grep x' 'x=$(OC_A=1 "$T/done_check.sh" 2>/dev/null | head -n1)' 'bash /opt/fullrun-tools/done_check.sh' './done_check.sh'; do
  printf '%s\n' "$form" >"$DT/opencode/x.sh"
  if [ -n "$(direct_calls "$DT")" ]; then nd=$((nd + 1)); else nm=$((nm + 1)); echo "  non détecté : $form"; fi
done
printf '%s\n' 'x=$(OC_A=1 fullrun_done_check "$T/done_check.sh" 2>/dev/null | head -n1)' '# bash "$DC"' >"$DT/opencode/x.sh"
[ "$nm" -eq 0 ] && [ -z "$(direct_calls "$DT")" ] && ok 15g3 "détecteur : 5 formes d'appel direct vues, appel centralisé et commentaire acceptés" || ko "15g3 détecteur ($nd vues, $nm manquées)"
# GitHub refuse tout workflow_dispatch de plus de 25 inputs (le workflow entier devient invalide, run « failure » sans job).
python3 - "$ROOT/.github/workflows/opencode-fullrun.yml" <<'CAP' && ok 15i "opencode-fullrun.yml : au plus 25 inputs workflow_dispatch" || ko "15i trop d'inputs workflow_dispatch (limite GitHub : 25)"
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)  # pas de PyYAML : contrôle sauté
d = yaml.safe_load(open(sys.argv[1]))
n = len(((d.get(True) or d.get('on') or {}).get('workflow_dispatch') or {}).get('inputs') or {})
sys.exit(0 if n <= 25 else 1)
CAP
# /opt inscriptible (0777 sur les runners hébergés) : l'étape de gel du workflow doit le fermer et échouer sinon.
if grep -q 'sudo chmod go-w /opt' "$ROOT/.github/workflows/opencode-fullrun.yml" && awk '/sudo chmod go-w \/opt/{c=NR} /sudo install -d -o root -g root -m 0755 "\$T"/{d=NR} END{exit !(c && d && c<d)}' "$ROOT/.github/workflows/opencode-fullrun.yml" \
   && grep -q 'find /opt -maxdepth 0 -perm /022' "$ROOT/.github/workflows/opencode-fullrun.yml"; then
  ok 15j "étape de gel : chmod go-w /opt AVANT de créer /opt/fullrun-tools, échec dur si /opt reste inscriptible"; else ko "15j /opt non fermé avant le gel"; fi
# M5 : README — la phrase du verdict est complète (parenthèses et backticks équilibrés, finit par « jamais PASS. »).
RL=$(grep -F "Le verdict est lu par le CLI lifeos" "$ROOT/README.md" | head -1)
python3 - "$RL" <<'PY' && ok 15h "README : phrase du verdict complète (parenthèses/backticks équilibrés)" || ko "15h README : phrase tronquée ou déséquilibrée"
import sys
l = sys.argv[1]
assert l.count('(') == l.count(')') and l.count('`') % 2 == 0 and l.rstrip().endswith('jamais PASS.'), l
PY

# 16. c:verify4 (incident annotation-build-solo3, run 45089775991) : OC_DONE_VERIFY en mode fichier
# exécute CHAQUE ligne dans un sous-shell isolé (opencode/done_check.sh:296-308) — une variable
# locale affectée sur une ligne (`isa=...`) ne survit jamais jusqu'à la ligne suivante. Le générateur
# bogué (opencode-fullrun.yml, step « Rapport, journal privé et contrôles avant push ») affectait
# `isa` en ligne 2 puis le relisait en lignes 3-4 : `isa` y était TOUJOURS vide, donc
# `[ -f "$isa" ] || exit 1` échouait À CHAQUE FOIS, même quand l'ISA existait réellement.
# Revue 2 (PR #40) : le générateur résout désormais OC_ISA_PATH UNE SEULE FOIS, dans sa propre garde
# (isa-path-guard, jamais exit — revue 3 ci-dessous), puis GRAVE cette valeur, littérale, dans chaque
# ligne générée — aucune ligne ne dépend plus d'un env survivant aux sous-shells.
# Revue 3 (PR #40) : BLOQUANT #1 — le RED doit être un test COMMITÉ, pas une vérification manuelle.
# 16a1 grave l'ANCIEN générateur bogué en dur (set -u ; isa= défini sur une ligne ; [ -f "$isa" ] sur
# une autre, exactement la forme décrite par la revue) et exige le c:verify4 original, avec une ISA
# qui existe réellement. 16a2 prouve, avec les MÊMES entrées, que le générateur RÉEL (extrait par ses
# marqueurs, jamais une copie réécrite à la main) rend ok.
YML="$ROOT/.github/workflows/opencode-fullrun.yml"
BEGIN_N=$(grep -c '# BEGIN done-verify-generator' "$YML")
END_N=$(grep -c '# END done-verify-generator' "$YML")
if [ "$BEGIN_N" -eq 1 ] && [ "$END_N" -eq 1 ]; then
  ok 16a "marqueurs BEGIN/END done-verify-generator présents une seule fois chacun"
else
  ko "16a marqueurs BEGIN=$BEGIN_N END=$END_N (attendu 1/1)"
fi

# Extrait le générateur RÉEL (texte entre ses marqueurs, jamais réécrit). Depuis la revue 2 ce bloc
# ne pose plus `isa_path_input` lui-même (déplacé dans isa-path-guard, extrait séparément plus bas
# pour 16e) : run_generator le pose donc elle-même avant de source-r le texte extrait, exactement
# comme isa-path-guard le fait juste avant ce bloc dans le step réel.
GEN="$T/vf-generator.sh"
awk '/# BEGIN done-verify-generator/{f=1; next} /# END done-verify-generator/{f=0} f' "$YML" >"$GEN"
[ -s "$GEN" ] || ko "16a2-setup extraction du générateur vide (marqueurs introuvables ou mal placés)"
run_generator() { # $1=OC_WORK $2=isa_path_input -> imprime le code de sortie ; sortie combinée (le
  # générateur écrit ses ::error:: sur stdout, convention GitHub Actions) dans $T/gen.out
  ( OC_WORK=$1; isa_path_input=$2; source "$GEN" ) >"$T/gen.out" 2>&1
  echo $?
}

# --- Groupe A (sans outils LIFEOS présents, dépôt principal $R/$ISA déjà utilisés par les tests 1-15) ---
mkstore "$T/s16" "opencode/v4-flash-free" 42 'VERDICT: PASS' "$ENDP"; mklog Max
call16a() { env OC_STORE_DIR="$T/s16" OC_HOOKS_LOG="$HOOKS" OC_REPORT="$REPORT" OC_ISA="$ISA" \
    OC_DONE_REPO="$R" "$@" bash "$DC" 2>/dev/null; }

# SC2015 (A && B || C n'est pas if/then/else : C tourne aussi si B échoue) : jamais de ternaire ici,
# toujours un if/then/else explicite — call16a peut légitimement imprimer puis sortir non-zéro
# (ko() de done_check.sh fait exit 1 après avoir imprimé la raison).
out_g16b() { if [ "$1" = 0 ]; then call16a OC_DONE_VERIFY="$2"; else echo "generateur rc=$1"; fi; }

# 16a1 (RED, BLOQUANT #1, commité) : l'ANCIEN validateur, en dur, pas un texte réécrit pour l'occasion
# mais la forme exacte dénoncée par la revue 3 — `set -u`, `isa=` posée sur UNE ligne, `[ -f "$isa" ]`
# lue sur UNE AUTRE — soumis à done_check.sh avec une ISA qui existe réellement ($ISA, $R comme les
# tests 1-15). Chaque ligne de ce fichier tourne dans son propre `bash -c`
# (opencode/done_check.sh:296-308) : `isa` posée en ligne 2 ne survit jamais jusqu'à la ligne 4, qui
# lit `$isa` nu (jamais `${isa:-}`) donc vide, jamais l'erreur `set -u` — exactement le bug original.
VF_OLD="$T/w16a1/done-verify.sh"; mkdir -p "$T/w16a1"
cat >"$VF_OLD" <<'OLDBUG'
set -u
isa="${OC_ISA_PATH:-}"
if [ -n "${isa:-}" ] && [ -f "LIFEOS/TOOLS/IsaFrontier.ts" ]; then bun LIFEOS/TOOLS/IsaFrontier.ts validate "${isa:-}"; fi
[ -f "$isa" ] || exit 1
OLDBUG
out=$(OC_ISA_PATH="$ISA" call16a OC_DONE_VERIFY="$VF_OLD")
[ "$out" = "done_check=ko raison=c:verify4" ] \
  && ok 16a1 "RED commité : l'ANCIEN validateur (set -u, isa posée/lue sur des lignes séparées) refuse TOUJOURS, même ISA existante -> c:verify4 (bug original reproduit, pas une vérification manuelle)" \
  || ko "16a1 [$out] (attendu done_check=ko raison=c:verify4 — l'ancien validateur, en dur, n'a pas reproduit le bug)"

mkdir -p "$T/w16a2"; rc=$(run_generator "$T/w16a2" "$ISA")
out=$(out_g16b "$rc" "$T/w16a2/done-verify.sh")
[ "$out" = "done_check=ok" ] \
  && ok 16a2 "GREEN : mêmes entrées que 16a1 (ISA existante, $ISA), générateur RÉEL (extrait, jamais une copie) -> done_check=ok" \
  || ko "16a2 [$out] (attendu done_check=ok, generateur rc=$rc)"

mkdir -p "$T/w16b"; rc=$(run_generator "$T/w16b" "$ISA")
out=$(out_g16b "$rc" "$T/w16b/done-verify.sh")
[ "$out" = "done_check=ok" ] \
  && ok 16b "générateur réel : ISA existante -> vf écrit, done_check=ok" \
  || ko "16b [$out] (attendu done_check=ok, generateur rc=$rc)"

mkdir -p "$T/w16c"; rc=$(run_generator "$T/w16c" "$T/isa-absente16.md")
out=$(out_g16b "$rc" "$T/w16c/done-verify.sh")
[ "$out" = "done_check=ko raison=c:verify1" ] \
  && ok 16c "générateur réel : isa_path fourni mais absente -> toujours refusé (c:verify1, contrôle non affaibli)" \
  || ko "16c [$out] (attendu done_check=ko raison=c:verify1, generateur rc=$rc)"

mkdir -p "$T/w16d"; rc=$(run_generator "$T/w16d" "")
out=$(out_g16b "$rc" "$T/w16d/done-verify.sh")
[ "$out" = "done_check=ok" ] \
  && ok 16d "générateur réel : aucune ISA demandée pour ce run -> ok (frontière hors scope de ce validateur)" \
  || ko "16d [$out] (attendu done_check=ok, generateur rc=$rc)"

# --- Revue 3 MAJEUR #3 : la garde M3 (isa-path-guard) ne doit JAMAIS faire `exit` au milieu du step —
# le contrat du step dit qu'un échec du validateur ne bloque ni le rapport, ni le journal, ni le push ;
# elle doit seulement mémoriser l'échec (isa_path_guard_failed) pour que dc_out devienne
# "done_check=ko raison=g:isa-path" en fin de step, après rapport et push. Extraction du bloc RÉEL
# (done-verify-outcome, qui englobe isa-path-guard ET son branchement vers dc_out) — jamais une copie.
OUT_BEGIN_N=$(grep -c '# BEGIN done-verify-outcome' "$YML")
OUT_END_N=$(grep -c '# END done-verify-outcome' "$YML")
if [ "$OUT_BEGIN_N" -eq 1 ] && [ "$OUT_END_N" -eq 1 ]; then
  ok 16e0 "marqueurs BEGIN/END done-verify-outcome présents une seule fois chacun"
else
  ko "16e0 marqueurs BEGIN=$OUT_BEGIN_N END=$OUT_END_N (attendu 1/1)"
fi
OUT="$T/vf-outcome.sh"
awk '/# BEGIN done-verify-outcome/{f=1; next} /# END done-verify-outcome/{f=0} f' "$YML" >"$OUT"
[ -s "$OUT" ] || ko "16e-setup extraction de done-verify-outcome vide (marqueurs introuvables ou mal placés)"
WRAP="$T/vf-outcome-wrap.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'source "'"$OUT"'"'
  echo 'echo "GUARD_FAILED=${isa_path_guard_failed:-}"'
  echo 'echo "DC_OUT=${dc_out:-}"'
} >"$WRAP"
run_outcome() { # $1=OC_WORK $2=OC_ISA_PATH $3=IN_ISA_PATH_EXPECTED -> imprime le code de sortie ;
  # sortie (GUARD_FAILED=…, DC_OUT=…) dans $T/outcome.out
  env OC_WORK="$1" OC_ISA_PATH="$2" IN_ISA_PATH_EXPECTED="$3" bash "$WRAP" >"$T/outcome.out" 2>&1
  echo $?
}

mkdir -p "$T/w16e"
rc=$(run_outcome "$T/w16e" "" true)
GUARD_FAILED=$(grep '^GUARD_FAILED=' "$T/outcome.out" | cut -d= -f2-)
DC_OUT=$(grep '^DC_OUT=' "$T/outcome.out" | cut -d= -f2-)
if [ "$rc" = 0 ] && [ "$GUARD_FAILED" = 1 ] && [ "$DC_OUT" = "done_check=ko raison=g:isa-path" ] \
   && [ ! -e "$T/w16e/done-verify.sh" ]; then
  ok 16e "garde M3 (bloc réel done-verify-outcome) : isa_path attendue mais OC_ISA_PATH vide -> JAMAIS d'exit (rc=0), isa_path_guard_failed mémorisé, dc_out='done_check=ko raison=g:isa-path', aucun vf écrit (générateur jamais atteint)"
else
  ko "16e rc=$rc guard_failed=[$GUARD_FAILED] dc_out=[$DC_OUT] (attendu rc=0, guard_failed=1, dc_out='done_check=ko raison=g:isa-path')"
fi

mkdir -p "$T/w16e2"
rc=$(run_outcome "$T/w16e2" "" "")
GUARD_FAILED2=$(grep '^GUARD_FAILED=' "$T/outcome.out" | cut -d= -f2-)
if [ "$rc" = 0 ] && [ -z "$GUARD_FAILED2" ]; then
  ok 16e2 "garde M3 : aucune ISA attendue (IN_ISA_PATH_EXPECTED non true) -> pas de faux positif, isa_path_guard_failed jamais posé, toujours pas d'exit"
else
  ko "16e2 rc=$rc guard_failed=[$GUARD_FAILED2] (attendu rc=0, guard_failed vide)"
fi

# --- Revue 3 MAJEUR #2 : IN_ISA_PATH_EXPECTED doit arriver dans l'env DU STEP qui exécute le
# générateur (id: check, « Rapport, journal privé et contrôles avant push »), pas seulement injecté
# à la main par les tests ci-dessus — preuve structurelle sur le fichier YAML réel, entre le nom du
# step et son premier `run: |` (début du script shell).
STEP_HDR=$(awk '
  /^      - name: Rapport, journal privé et contrôles avant push$/ { f = 1 }
  f { print }
  f && /^        run: \|$/ { exit }
' "$YML")
if printf '%s\n' "$STEP_HDR" | grep -qE '^ +IN_ISA_PATH_EXPECTED:'; then
  ok 16l "IN_ISA_PATH_EXPECTED déclaré dans l'env du step « id: check » lui-même (pas seulement injecté à la main dans les tests)"
else
  ko "16l IN_ISA_PATH_EXPECTED absent de l'env du step « id: check » dans opencode-fullrun.yml"
fi

# --- Groupe B (M1 : outils LIFEOS réellement présents — dépôt dédié $R2, horodatages propres,
# jamais mêlés au dépôt $R des tests 1-15) : les lignes 2 à 4 appellent vraiment IsaFrontier,
# CheckCompleteness puis ISATool, et un échec de l'un d'eux doit être refusé (jamais ignoré).
R2="$T/repo16"; mkdir -p "$R2/LIFEOS/TOOLS"
git -C "$R2" init -q; git -C "$R2" config user.email t@t; git -C "$R2" config user.name t
printf '// stub IsaFrontier\n' >"$R2/LIFEOS/TOOLS/IsaFrontier.ts"
printf '// stub CheckCompleteness\n' >"$R2/LIFEOS/TOOLS/CheckCompleteness.ts"
printf '// stub ISATool\n' >"$R2/LIFEOS/TOOLS/ISATool.ts"
(cd "$R2" && git add -A && git commit -qm init16) >/dev/null
COMMIT16=$(git -C "$R2" log -1 --format=%ct)
# ISA16 HORS de $R2 (comme $ISA est hors de $R pour les tests 1-15) : sinon le fichier, non commité,
# rend l'arbre de $R2 sale (d:arbre-sale) dès sa création.
ISA16="$T/isa16.md"; printf -- '---\nphase: climbing\n---\n' >"$ISA16"
REPORT16="$T/report16.md"; echo rapport >"$REPORT16"
HOOKS16="$T/hooks16.log"
printf '%s SUBAGENT done subagent_type=Max ok=true session=s call=c\n' \
  "$(date -u -d "@$((COMMIT16 + 5))" +%Y-%m-%dT%H:%M:%S.000Z)" >"$HOOKS16"
mkstore "$T/store16" "opencode/v4-flash-free" 42 'VERDICT: PASS' "$(( (COMMIT16 + 10) * 1000 ))"
# Stub `bun` : journalise chaque appel ($BUN_LOG) et échoue seulement si $1 (le .ts appelé)
# contient $BUN_FAIL_MATCH — permet de simuler un échec précis d'IsaFrontier/CheckCompleteness/ISATool.
BIN16="$T/bin16"; mkdir -p "$BIN16"
cat >"$BIN16/bun" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BUN_LOG:-/dev/null}"
case "$1" in
  *"${BUN_FAIL_MATCH:-__none__}"*) exit 1 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN16/bun"
BUN_LOG16="$T/bun16.log"
# Revue 3 MINEUR #6 : si bun est introuvable (ni $PATH ni ~/.bun/bin), échec CLAIR et immédiat — jamais
# une valeur de repli silencieusement inexistante qui ferait échouer les tests plus bas avec un message
# cryptique (« command not found » loin de sa cause réelle).
if REAL_BUN=$(command -v bun 2>/dev/null); then
  :
elif [ -x "$HOME/.bun/bin/bun" ]; then
  REAL_BUN="$HOME/.bun/bin/bun"
else
  echo "ko 16-setup bun introuvable (ni \$PATH ni ~/.bun/bin/bun) — requis par le CLI de verdict de done_check.sh pour le Groupe B" >&2
  exit 1
fi
# OC_BUN pointe le VRAI bun pour le CLI de verdict (part a, verdict_of() le résout lui-même via
# shutil.which si OC_BUN est vide, et verrait alors $BIN16/bun en premier sur le PATH ci-dessous) ;
# le $BIN16/bun (stub, journalisé) ne sert donc qu'aux lignes 2-4 du validateur de fin (part c),
# invoquées par un bare `bun` résolu via PATH dans leurs propres sous-shells.
call16b() { env PATH="$BIN16:$PATH" BUN_LOG="$BUN_LOG16" OC_BUN="$REAL_BUN" OC_STORE_DIR="$T/store16" \
    OC_HOOKS_LOG="$HOOKS16" OC_REPORT="$REPORT16" OC_ISA="$ISA16" OC_DONE_REPO="$R2" \
    "$@" bash "$DC" 2>/dev/null; }
out_g16f() { if [ "$1" = 0 ]; then call16b OC_DONE_VERIFY="$2" "${@:3}"; else echo "generateur rc=$1"; fi; }

mkdir -p "$T/w16f"; rc=$(run_generator "$T/w16f" "$ISA16")
: >"$BUN_LOG16"
out=$(out_g16f "$rc" "$T/w16f/done-verify.sh")
[ "$out" = "done_check=ok" ] \
  && ok 16f "outils présents, tous ok -> done_check=ok" \
  || ko "16f [$out] (attendu done_check=ok, generateur rc=$rc)"
# Revue 3 MINEUR #4 : `|| true` (jamais `|| echo 0`, qui n'apporte rien ici puisque `grep -c` imprime
# déjà 0 quand il ne trouve rien) + `${var:-0}` pour tolérer un fichier de log absent ou illisible sans
# faire échouer `set -o pipefail` plus haut dans le script.
n_isafrontier=$(grep -c 'IsaFrontier\.ts validate' "$BUN_LOG16" 2>/dev/null) || true
n_completeness=$(grep -c 'CheckCompleteness\.ts' "$BUN_LOG16" 2>/dev/null) || true
n_isatool=$(grep -c 'ISATool\.ts verify' "$BUN_LOG16" 2>/dev/null) || true
n_total=$(wc -l <"$BUN_LOG16" 2>/dev/null) || true
if [ "${n_total:-0}" -eq 3 ] && [ "${n_isafrontier:-0}" -eq 1 ] && [ "${n_completeness:-0}" -eq 1 ] \
   && [ "${n_isatool:-0}" -eq 1 ] && grep -qF "$ISA16" "$BUN_LOG16"; then
  ok 16g "les 3 outils (IsaFrontier validate, CheckCompleteness, ISATool verify) sont bien appelés, avec le chemin ISA"
else
  ko "16g appels bun observés (${n_total:-0} au total) : $(cat "$BUN_LOG16" 2>/dev/null)"
fi

mkdir -p "$T/w16h"; rc=$(run_generator "$T/w16h" "$ISA16")
out=$(out_g16f "$rc" "$T/w16h/done-verify.sh" BUN_FAIL_MATCH=IsaFrontier)
[ "$out" = "done_check=ko raison=c:verify2" ] \
  && ok 16h "IsaFrontier validate en échec -> refusé (c:verify2), jamais ignoré" \
  || ko "16h [$out] (attendu done_check=ko raison=c:verify2, generateur rc=$rc)"

mkdir -p "$T/w16i"; rc=$(run_generator "$T/w16i" "$ISA16")
out=$(out_g16f "$rc" "$T/w16i/done-verify.sh" BUN_FAIL_MATCH=CheckCompleteness)
[ "$out" = "done_check=ko raison=c:verify3" ] \
  && ok 16i "CheckCompleteness en échec -> refusé (c:verify3), jamais ignoré" \
  || ko "16i [$out] (attendu done_check=ko raison=c:verify3, generateur rc=$rc)"

mkdir -p "$T/w16j"; rc=$(run_generator "$T/w16j" "$ISA16")
out=$(out_g16f "$rc" "$T/w16j/done-verify.sh" BUN_FAIL_MATCH=ISATool)
[ "$out" = "done_check=ko raison=c:verify4" ] \
  && ok 16j "ISATool verify en échec -> refusé (c:verify4, désormais un VRAI échec d'outil, jamais un faux positif)" \
  || ko "16j [$out] (attendu done_check=ko raison=c:verify4, generateur rc=$rc)"

# --- Revue 3 MINEUR #5 : garde structurelle limitée au texte EXTRAIT du générateur ($GEN), pas au
# fichier YAML entier ($YML) — un commentaire ou un historique mentionnant l'ancien motif ailleurs
# dans le YAML ne doit jamais faire échouer cette garde à tort.
if grep -qF 'isa="${OC_ISA_PATH:-}"' "$GEN"; then
  ko "16k le générateur extrait (done-verify-generator) affecte encore 'isa' dans une ligne séparée de son usage (régression c:verify4)"
else
  ok 16k "générateur extrait (done-verify-generator) : plus de variable 'isa' partagée entre lignes du validateur de fin"
fi

# --- 17. Repli REPORT.md : a/b (verdict PASS + hooks) déjà vérifiés, mais le fichier attendu par
# done_check.sh est absent/vide -> un rapport de repli FACTUEL est généré, et le check passe.
# Store s6 est un PASS complet déjà utilisé par les tests 6-9 ; l'ISA y est remise à climbing juste
# avant (fin du test 9), donc réutilisable ici sans setup supplémentaire.
REPORT17="$T/report17/REPORT.md"  # dossier n'existe pas encore : vérifie aussi le mkdir -p du repli
out=$(call "$T/s6" OC_REPORT="$REPORT17")
[ "$out" = "done_check=ok" ] \
  && ok 17a "REPORT.md absent : repli factuel généré, done_check passe quand même" \
  || ko "17a [$out]"
[ -s "$REPORT17" ] && grep -q "repli automatique" "$REPORT17" \
  && ok 17b "le fichier de repli est bien écrit sur disque et se déclare comme tel" \
  || ko "17b (REPORT17 absent ou sans la mention de repli)"
grep -q "$R" "$REPORT17" 2>/dev/null \
  && ko "17c le repli ne doit jamais fuiter un chemin de dépôt absolu dans le rapport" \
  || ok "17c aucun chemin de dépôt absolu dans le rapport de repli"

# 17d. REPORT.md vide (fichier existe mais 0 octet) -> même repli que fichier absent.
: >"$T/report17/REPORT.md"
out=$(call "$T/s6" OC_REPORT="$T/report17/REPORT.md")
[ "$out" = "done_check=ok" ] && grep -q "repli automatique" "$T/report17/REPORT.md" \
  && ok 17d "REPORT.md vide (0 octet) : même repli que fichier absent" \
  || ko "17d [$out]"

# 17e. Le repli n'est PAS un blanc-seing : un vrai échec (b:hooks, agent sans ligne hooks.log après
# le dernier commit) reste un échec même si REPORT est absent — le repli ne se déclenche qu'après
# a ET b, jamais avant (ordre du script : b échoue avant d'atteindre le bloc d).
mkstore "$T/s17e" "opencode/v4-flash-free" 42 $'Travail terminé.\n{"status":"pass"}' "$ENDP"
: >"$T/hooks-empty.log"
out=$(env OC_STORE_DIR="$T/s17e" OC_HOOKS_LOG="$T/hooks-empty.log" OC_REPORT="$T/report17e-missing.md" \
      OC_ISA="$ISA" OC_DONE_REPO="$R" bash "$DC" 2>/dev/null)
[ "$out" = "done_check=ko raison=b:hooks" ] && [ ! -e "$T/report17e-missing.md" ] \
  && ok 17e "REPORT absent + b:hooks en échec : refusé normalement, AUCUN repli généré avant b" \
  || ko "17e [$out] (repli ne doit jamais masquer un vrai échec a/b)"

echo "résumé : $pass ok, $fail ko"
[ "$fail" -eq 0 ]
