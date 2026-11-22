#!/usr/bin/env bash
# Tests du validateur de fin (étape 4) : stockage opencode (SQLite et arbre JSON), hooks.log,
# vérificateurs relancés, arbre/rapport/ISA — et la sortie anticipée de run-fullrun.sh
# (`arret=max_pass`, rc 0, hors modèle).
# Usage : bash opencode/tests/done-check-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
DC="$ROOT/opencode/done_check.sh"
# shellcheck source=verdict-cli.sh
source "$HERE/verdict-cli.sh"
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
mkstore "$T/s13e" "opencode/v4-flash-free" 42 $'Revue.\n{"status":"pass"}' "$ENDP"
out=$(call "$T/s13e" OC_VERDICT_CLI=/nonexistent/FullRunVerdict.ts); [ "$out" = "done_check=ko raison=a:verdict-cli" ] && ok 13e "CLI introuvable : refus nommé a:verdict-cli, jamais ok" || ko "13e [$out]"
FAKE="$T/fakebun"; mkdir -p "$FAKE"
printf '#!/bin/sh\ncat >/dev/null; echo pass; exit 3\n' >"$FAKE/bun-pass-rc3"; chmod +x "$FAKE/bun-pass-rc3"
out=$(call "$T/s13e" OC_BUN="$FAKE/bun-pass-rc3"); [ "$out" != "done_check=ok" ] && ok 13f "stdout « pass » mais code 3 : pas pass (le code ET la sortie doivent dire pass)" || ko "13f [$out]"
printf '#!/bin/sh\ncat >/dev/null; echo unknown; exit 0\n' >"$FAKE/bun-unknown-rc0"; chmod +x "$FAKE/bun-unknown-rc0"
out=$(call "$T/s13e" OC_BUN="$FAKE/bun-unknown-rc0"); [ "$out" != "done_check=ok" ] && ok 13g "code 0 mais sortie « unknown » : pas pass" || ko "13g [$out]"
printf '#!/bin/sh\ncat >/dev/null; echo unknown; exit 3\n' >"$FAKE/bun-unknown"; chmod +x "$FAKE/bun-unknown"
out=$(call "$T/s13e" OC_BUN="$FAKE/bun-unknown"); [ "$out" = "done_check=ko raison=a:inconclusif" ] && ok 13h "code 3 (unknown) : inconclusif" || ko "13h [$out]"

echo "résumé : $pass ok, $fail ko"
[ "$fail" -eq 0 ]
