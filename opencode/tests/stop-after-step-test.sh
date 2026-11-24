#!/usr/bin/env bash
# Job borné à une étape (stop_after_step) : le validateur doit exiger le PASS de l'agent de
# CETTE étape (vera -> Algorithm, serena -> Architect, build -> Forge, verify -> Silas,
# max/close -> Max), le prompt doit ordonner l'arrêt, et aucune reprise ne doit dérouler les
# étapes suivantes. Le workflow étant livré en patch (docs/patches), ce test l'applique d'abord
# sur une copie jetable : c'est la version patchée qui est vérifiée.
#   opencode/tests/stop-after-step-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
WF="$ROOT/.github/workflows/opencode-fullrun.yml"
PATCH="$ROOT/docs/patches/diag-arret-etape-2026-11-24.patch"
STEP="$ROOT/opencode/step-agents.sh"
RUN="$ROOT/opencode/run-fullrun.sh"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { echo "OK   $*"; }
ko() { echo "FAIL $*"; fail=1; }

[ -f "$WF" ] || { echo "FAIL workflow introuvable : $WF"; exit 1; }
[ -f "$PATCH" ] || { echo "FAIL patch introuvable : $PATCH"; exit 1; }
[ -f "$STEP" ] || { echo "FAIL mapping introuvable : $STEP"; exit 1; }

# --- 1. mapping étape -> agent (source unique, utilisée par le workflow) --------------------------
mapping_ok=1
while read -r step agent; do
  got=$(bash "$STEP" "$step" 2>/dev/null) || got="(erreur)"
  [ "$got" = "$agent" ] || { ko "mapping $step -> '$got' au lieu de '$agent'"; mapping_ok=0; }
done <<'MAP'
0 Algorithm
scaffold Algorithm
1 Algorithm
completeness_pre Algorithm
2 Algorithm
vera Algorithm
3 Architect
serena Architect
4 Forge
build Forge
5 Silas
verify Silas
6 Max
max Max
7 Max
close Max
MAP
[ "$mapping_ok" -eq 1 ] && ok "mapping : les 8 étapes (noms et 0-7) désignent le bon agent"
bash "$STEP" deploy >/dev/null 2>&1; [ "$?" -eq 64 ] && ok "mapping : étape inconnue refusée (64)" || ko "mapping : étape inconnue acceptée"

# --- 2. appliquer le patch workflow sur une copie jetable -----------------------------------------
mkdir -p "$T/repo/.github/workflows"
cp "$WF" "$T/repo/.github/workflows/opencode-fullrun.yml"
if ( cd "$T/repo" && git apply "$PATCH" ) 2>"$T/apply.err"; then
  ok "patch : git apply sur la copie du workflow"
elif grep -q 'BEGIN stop-after-effective' "$T/repo/.github/workflows/opencode-fullrun.yml"; then
  ok "patch : déjà intégré au workflow (marqueurs présents)"
else
  ko "patch : git apply impossible ($(tr '\n' ' ' <"$T/apply.err"))"
fi
PF="$T/repo/.github/workflows/opencode-fullrun.yml"

# --- 3. l'input done_agents est vide par défaut (l'étape décide) et accepte le vide ---------------
python3 - "$PF" <<'PY' || fail=1
import sys, yaml
y = yaml.safe_load(open(sys.argv[1]))
i = (y.get("on") or y.get(True))["workflow_dispatch"]["inputs"]
assert i["done_agents"].get("default") == "", "done_agents doit être vide par défaut"
run = next(s for s in y["jobs"]["fullrun"]["steps"] if s.get("id") == "guard")["run"]
assert 'if [ -n "$IN_DONE_AGENTS" ]' in run, "la garde doit accepter un done_agents vide"
print("OK   input done_agents : vide par défaut, vide accepté par la garde")
PY

extract_block() { # $1=step id ; $2=marqueur début ; $3=marqueur fin ; $4=fichier sortie
  python3 - "$PF" "$1" "$2" "$3" "$4" <<'PY'
import sys, yaml
wf, sid, begin, end, out = sys.argv[1:6]
y = yaml.safe_load(open(wf))
step = next(s for s in y["jobs"]["fullrun"]["steps"] if s.get("id") == sid)
lines = step["run"].splitlines()
try:
    i = next(n for n, l in enumerate(lines) if begin in l)
    j = next(n for n, l in enumerate(lines) if end in l and n > i)
except StopIteration:
    sys.exit("marqueur absent (%s / %s) dans %s" % (begin, end, sid))
open(out, "w").write("\n".join(lines[i + 1:j]) + "\n")
PY
}

# --- 4. calcul de OC_DONE_AGENTS_EFFECTIVE (bloc réellement publié) --------------------------------
extract_block prep "# BEGIN stop-after-effective" "# END stop-after-effective" "$T/effective.sh" \
  || ko "bloc stop-after-effective non extrait"
eff() { # arguments env ; imprime la valeur écrite dans GITHUB_ENV
  : >"$T/env"
  env -u IN_DONE_AGENTS -u OC_TARGET_AGENT -u OC_STOP_AFTER_STEP \
      GITHUB_ENV="$T/env" CI_DIR="$ROOT" "$@" bash "$T/effective.sh" >/dev/null 2>&1 || return 1
  sed -n 's/^OC_DONE_AGENTS_EFFECTIVE=//p' "$T/env"
}
check_eff() { # $1=attendu ; $2=libellé ; reste=env
  local want="$1" label="$2"; shift 2
  local got; got=$(eff "$@") || { ko "$label : bloc en erreur"; return; }
  [ "$got" = "$want" ] && ok "$label -> $want" || ko "$label -> '$got' au lieu de '$want'"
}
check_eff Max "sans étape bornée : Max (comportement historique)"
check_eff Algorithm "stop_after_step=vera" OC_STOP_AFTER_STEP=vera
check_eff Architect "stop_after_step=serena" OC_STOP_AFTER_STEP=serena
check_eff Forge "stop_after_step=build" OC_STOP_AFTER_STEP=build
check_eff Silas "stop_after_step=verify" OC_STOP_AFTER_STEP=verify
check_eff Max "stop_after_step=max" OC_STOP_AFTER_STEP=max
check_eff Max "stop_after_step=close" OC_STOP_AFTER_STEP=close
check_eff "Max,Silas" "done_agents explicite respecté" OC_STOP_AFTER_STEP=vera IN_DONE_AGENTS=Max,Silas
check_eff Architect "stop_after_step prioritaire sur target_agent" OC_STOP_AFTER_STEP=serena OC_TARGET_AGENT=Algorithm
check_eff Silas "target_agent sans stop_after_step" OC_TARGET_AGENT=Silas

# --- 5. consigne d'arrêt injectée dans le prompt (bloc réellement publié) -------------------------
extract_block prep "# BEGIN stop-after-prompt" "# END stop-after-prompt" "$T/prompt-block.sh" \
  || ko "bloc stop-after-prompt non extrait"
prompt_test() { # $1=attendu (oui/non) ; $2=libellé ; $3=agent attendu ; reste=env
  local want="$1" label="$2" agent="$3"; shift 3
  : >"$T/prompt.md"
  env -u OC_STOP_AFTER_STEP -u OC_TARGET_AGENT OC_WORK="$T" CI_DIR="$ROOT" "$@" \
    bash "$T/prompt-block.sh" >/dev/null 2>&1 || { ko "$label : bloc en erreur"; return; }
  if [ "$want" = oui ]; then
    grep -q 'Étape finale imposée' "$T/prompt.md" && grep -q "$agent" "$T/prompt.md" \
      && grep -q 'ne lance AUCUNE étape suivante' "$T/prompt.md" \
      && ok "$label : arrêt explicite, agent nommé" || ko "$label : consigne absente ($(tr '\n' ' ' <"$T/prompt.md"))"
  else
    [ ! -s "$T/prompt.md" ] && ok "$label : aucune consigne (run non borné)" || ko "$label : consigne inattendue"
  fi
}
prompt_test oui "stop_after_step=vera" Algorithm OC_STOP_AFTER_STEP=vera
prompt_test oui "stop_after_step=serena" Architect OC_STOP_AFTER_STEP=serena
prompt_test non "sans stop_after_step" ""

# --- 6. le workflow consomme la valeur effective partout (préflight, run, validateur, chaînage) ----
n=$(grep -cF 'OC_DONE_AGENTS="${OC_DONE_AGENTS_EFFECTIVE:-${IN_DONE_AGENTS:-Max}}"' "$PF" || true)
[ "$n" -ge 2 ] && ok "workflow : agent effectif consommé par préflight et validateur ($n)" \
  || ko "workflow : agent effectif consommé seulement $n fois (attendu >= 2)"
grep -qF 'OC_DONE_AGENTS="${OC_DONE_AGENTS_EFFECTIVE:-${OC_DONE_AGENTS:-Max}}"; export OC_DONE_AGENTS' "$PF" \
  && ok "workflow : step oc exporte l'agent effectif" || ko "workflow : step oc ignore l'agent effectif"
grep -qF 'done_agents="${OC_DONE_AGENTS_EFFECTIVE:-${IN_DONE_AGENTS:-Max}}"' "$PF" \
  && ok "workflow : chaînage transmet l'agent effectif" || ko "workflow : chaînage ignore l'agent effectif"
grep -qF 'OC_DONE_AGENTS_EFFECTIVE' "$PF" && ok "workflow : la valeur effective est posée et consommée" \
  || ko "workflow : OC_DONE_AGENTS_EFFECTIVE absent"

# --- 7. bout en bout du wrapper : l'agent de l'étape arrête le job, sans reprise -------------------
rm -rf "$T/repo-ant"; mkdir -p "$T/repo-ant" "$T/store" "$T/agents" "$T/internals"; : >"$T/prompt.md"
cat >"$T/oc" <<S
#!/usr/bin/env bash
echo run >>"$T/oc.runs"
echo "travail de l'étape"
exit 0
S
chmod +x "$T/oc"
mkdone() { # $1 = agent attendu
cat >"$T/done" <<S
#!/usr/bin/env bash
if [ "\${OC_DONE_AGENTS:-}" = "$1" ]; then echo done_check=ok; exit 0; fi
echo "done_check=ko raison=a:none:\${OC_DONE_AGENTS:-}"
exit 1
S
chmod +x "$T/done"
}
run_wrapper() { # $1=done_agents
  rm -f "$T/oc.runs" "$T/log"*; : >"$T/log"; : >"$T/log.status"
  env ANTENLY_DIR="$T/repo-ant" OC_PROMPT_FILE="$T/prompt.md" OC_LOG="$T/log" \
    OC_MODEL_MAIN=opencode/main-free OC_MODEL_CHAIN=opencode/fb-free \
    OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 OC_IDLE_SEC=2 OC_POLL_SEC=1 \
    OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC=0 OC_STORE_DIR="$T/store" OC_BIN="$T/oc" \
    OC_STALL_RESUMES=2 OC_AGENT_DIR="$T/agents" OC_DONE_CHECK_BIN="$T/done" \
    OC_DONE_CHECK_SEC=1 OC_DONE_IDLE_SEC=1 OC_INTERNAL_LOG="$T/log.internal" \
    OC_INTERNAL_LOG_DIR="$T/internals" OC_STOP_AFTER_STEP=vera OC_DONE_AGENTS="$1" \
    bash "$RUN" >/dev/null 2>&1
}
mkdone Algorithm
run_wrapper Algorithm; rc=$?
if [ "$rc" -eq 0 ] && grep -qx 'arret=max_pass' "$T/log.status" \
   && [ "$(wc -l <"$T/oc.runs")" -eq 1 ]; then
  ok "wrapper : PASS Algorithm sur stop_after_step=vera -> arrêt immédiat (max_pass)"
else
  ko "wrapper/vera : rc=$rc $(tr '\n' ' ' <"$T/log.status" 2>/dev/null)"
fi
mkdone Algorithm
run_wrapper Max; rc=$?
if [ "$rc" -eq 127 ] && grep -qx 'arret=tour-fini' "$T/log.status" \
   && grep -qx 'stop_after_no_resume=vera' "$T/log.status" \
   && [ "$(wc -l <"$T/oc.runs")" -eq 1 ]; then
  ok "wrapper : sans PASS de l'étape, aucune reprise vers les étapes suivantes (127, un seul tour)"
else
  ko "wrapper/no-resume : rc=$rc $(tr '\n' ' ' <"$T/log.status" 2>/dev/null)"
fi

exit "$fail"
