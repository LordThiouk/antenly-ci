#!/usr/bin/env bash
# Job borné à une étape (stop_after_step) : le validateur doit exiger le PASS de l'agent
# réellement dispatché (target_agent prioritaire) ou de tout agent autorisé de l'étape
# (vera -> Algorithm, serena -> Architect, build -> Designer/Aditi/Engineer/Forge/Anvil,
# verify -> code-reviewer/Forge/Silas, max/close -> Max), le prompt doit ordonner l'arrêt,
# et aucune reprise ne doit dérouler les étapes suivantes. Le test vérifie l'arbre COURANT tel
# quel : il ne lit ni n'applique JAMAIS un fichier de docs/patches/ (pas de git apply, pas de
# patch). Les correctifs déjà intégrés dans la branche sont donc testés directement.
#   opencode/tests/stop-after-step-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
WF="$ROOT/.github/workflows/opencode-fullrun.yml"
STEP="$ROOT/opencode/step-agents.sh"
RUN="$ROOT/opencode/run-fullrun.sh"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { echo "OK   $*"; }
ko() { echo "FAIL $*"; fail=1; }

[ -f "$WF" ] || { echo "FAIL workflow introuvable : $WF"; exit 1; }
[ -f "$STEP" ] || { echo "FAIL mapping introuvable : $STEP"; exit 1; }

# --- 1. mapping étape -> agents autorisés (source unique, utilisée par le workflow) ---------------
mapping_ok=1
while read -r step agents; do
  got=$(bash "$STEP" "$step" 2>/dev/null) || got="(erreur)"
  got_list=$(bash "$STEP" --list "$step" 2>/dev/null) || got_list="(erreur)"
  [ "$got" = "$agents" ] || { ko "mapping $step -> '$got' au lieu de '$agents'"; mapping_ok=0; }
  [ "$got_list" = "$agents" ] || { ko "mapping --list $step -> '$got_list' au lieu de '$agents'"; mapping_ok=0; }
done <<'MAP'
0 Algorithm
scaffold Algorithm
1 Algorithm
completeness_pre Algorithm
2 Algorithm
vera Algorithm
3 Architect
serena Architect
4 Designer,Aditi,Engineer,Forge,Anvil
build Designer,Aditi,Engineer,Forge,Anvil
5 code-reviewer,Forge,Silas
verify code-reviewer,Forge,Silas
6 Max
max Max
7 Max
close Max
MAP
[ "$mapping_ok" -eq 1 ] && ok "mapping : les 8 étapes (noms et 0-7) désignent la bonne liste d'agents autorisés"
bash "$STEP" deploy >/dev/null 2>&1; [ "$?" -eq 64 ] && ok "mapping : étape inconnue refusée (64)" || ko "mapping : étape inconnue acceptée"
bash "$STEP" --list deploy >/dev/null 2>&1; [ "$?" -eq 64 ] && ok "mapping : étape inconnue refusée pour --list (64)" || ko "mapping --list : étape inconnue acceptée"

# --- 2. workflow de l'arbre courant (aucun patch réappliqué) --------------------------------------
# Le workflow est lu tel quel : les correctifs sont déjà dans la branche. Aucune copie patchée,
# aucun `git apply` : c'est exactement ce que la CI exécutera.
PF="$WF"

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
eff_var() { # $1=variable ; reste=env ; imprime la valeur écrite dans GITHUB_ENV
  local var="$1"; shift
  : >"$T/env"
  env -u IN_DONE_AGENTS -u OC_TARGET_AGENT -u OC_STOP_AFTER_STEP \
      GITHUB_ENV="$T/env" CI_DIR="$ROOT" "$@" bash "$T/effective.sh" >/dev/null 2>&1 || return 1
  sed -n "s/^${var}=//p" "$T/env"
}
eff() { eff_var OC_DONE_AGENTS_EFFECTIVE "$@"; }
check_eff() { # $1=attendu ; $2=libellé ; reste=env
  local want="$1" label="$2"; shift 2
  local got; got=$(eff "$@") || { ko "$label : bloc en erreur"; return; }
  [ "$got" = "$want" ] && ok "$label -> $want" || ko "$label -> '$got' au lieu de '$want'"
}
check_any() { # $1=attendu (1/le vide) ; $2=libellé ; reste=env
  local want="$1" label="$2"; shift 2
  local got; got=$(eff_var OC_DONE_AGENTS_ANY "$@") || { ko "$label : bloc en erreur"; return; }
  [ "$got" = "$want" ] && ok "$label -> '${want}'(ANY)" || ko "$label -> '$got' au lieu de '$want' (ANY)"
}
check_eff Max "sans étape bornée : Max (comportement historique)"
check_any "" "sans étape bornée : ANY vide"
check_eff Algorithm "stop_after_step=vera" OC_STOP_AFTER_STEP=vera
check_eff Architect "stop_after_step=serena" OC_STOP_AFTER_STEP=serena
check_eff "Designer,Aditi,Engineer,Forge,Anvil" "stop_after_step=build" OC_STOP_AFTER_STEP=build
check_any 1 "stop_after_step=build : un seul PASS autorisé" OC_STOP_AFTER_STEP=build
check_eff "code-reviewer,Forge,Silas" "stop_after_step=verify" OC_STOP_AFTER_STEP=verify
check_any 1 "stop_after_step=verify : un seul PASS autorisé" OC_STOP_AFTER_STEP=verify
check_eff Max "stop_after_step=max" OC_STOP_AFTER_STEP=max
check_eff Max "stop_after_step=close" OC_STOP_AFTER_STEP=close
check_eff "Max,Silas" "done_agents explicite respecté" OC_STOP_AFTER_STEP=vera IN_DONE_AGENTS=Max,Silas
check_any "" "done_agents explicite : chaque agent exigé (ANY vide)" OC_STOP_AFTER_STEP=vera IN_DONE_AGENTS=Max,Silas
check_eff Designer "target_agent prioritaire sur stop_after_step (build)" OC_STOP_AFTER_STEP=build OC_TARGET_AGENT=Designer
check_any "" "target_agent prioritaire : ANY vide" OC_STOP_AFTER_STEP=build OC_TARGET_AGENT=Designer
check_eff code-reviewer "target_agent prioritaire sur stop_after_step (verify)" OC_STOP_AFTER_STEP=verify OC_TARGET_AGENT=code-reviewer
check_eff Anvil "target_agent Anvil accepté en build" OC_STOP_AFTER_STEP=build OC_TARGET_AGENT=Anvil
# Hors job borné, le défaut historique Max reste maître même si target_agent limite le dispatch :
# le chaînage manuel (chain_enabled=false, sans stop_after_step) ne change pas de validateur.
check_eff Max "target_agent sans stop_after_step : Max (comportement inchangé)" OC_TARGET_AGENT=Silas

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
prompt_test oui "stop_after_step=build sans target_agent" "Designer,Aditi,Engineer,Forge,Anvil" OC_STOP_AFTER_STEP=build
prompt_test oui "stop_after_step=build target_agent=Designer" Designer OC_STOP_AFTER_STEP=build OC_TARGET_AGENT=Designer
prompt_test oui "stop_after_step=verify target_agent=code-reviewer" code-reviewer OC_STOP_AFTER_STEP=verify OC_TARGET_AGENT=code-reviewer
prompt_test oui "stop_after_step=build target_agent=Anvil" Anvil OC_STOP_AFTER_STEP=build OC_TARGET_AGENT=Anvil
prompt_test non "sans stop_after_step" ""

# --- 6. le workflow consomme la valeur effective partout (préflight, run, validateur, chaînage) ----
n=$(grep -cF 'OC_DONE_AGENTS="${OC_DONE_AGENTS_EFFECTIVE:-${IN_DONE_AGENTS:-Max}}"' "$PF" || true)
[ "$n" -ge 2 ] && ok "workflow : agent effectif consommé par préflight et validateur ($n)" \
  || ko "workflow : agent effectif consommé seulement $n fois (attendu >= 2)"
grep -qF 'OC_DONE_AGENTS="${OC_DONE_AGENTS_EFFECTIVE:-${OC_DONE_AGENTS:-Max}}"; export OC_DONE_AGENTS' "$PF" \
  && ok "workflow : step oc exporte l'agent effectif" || ko "workflow : step oc ignore l'agent effectif"
grep -qF 'OC_DONE_AGENTS_ANY="${OC_DONE_AGENTS_ANY:-}"; export OC_DONE_AGENTS_ANY' "$PF" \
  && ok "workflow : step oc exporte le mode ANY" || ko "workflow : step oc ignore le mode ANY"
grep -qF 'OC_DONE_AGENTS_ANY="${OC_DONE_AGENTS_ANY:-}"' "$PF" \
  && ok "workflow : validateur final reçoit le mode ANY" || ko "workflow : validateur final ignore le mode ANY"
grep -qF 'done_agents="${OC_DONE_AGENTS_EFFECTIVE:-${IN_DONE_AGENTS:-Max}}"' "$PF" \
  && ok "workflow : chaînage transmet l'agent effectif" || ko "workflow : chaînage ignore l'agent effectif"
grep -qF 'OC_DONE_AGENTS_EFFECTIVE' "$PF" && ok "workflow : la valeur effective est posée et consommée" \
  || ko "workflow : OC_DONE_AGENTS_EFFECTIVE absent"

# --- 6b. chaînage : un job borné ne dispatche jamais le lien suivant --------------------------------
# Le step chain est extrait du workflow courant et exécuté avec IN_STOP_AFTER_STEP : l'arrêt doit être
# décidé AVANT bun/unit et avant tout gh workflow run (aucun outil n'est disponible ici).
python3 - "$PF" "$T/chain.sh" <<'PY' || fail=1
import sys, yaml
wf, out = sys.argv[1], sys.argv[2]
y = yaml.safe_load(open(wf))
step = next(s for s in y["jobs"]["fullrun"]["steps"] if s.get("id") == "chain")
open(out, "w").write("#!/usr/bin/env bash\nset -euo pipefail\n" + step["run"])
PY
chmod +x "$T/chain.sh" 2>/dev/null || true
: >"$T/chain.out"; : >"$T/chain.summary"
if env -i PATH="/usr/bin:/bin" HOME="$T" GITHUB_OUTPUT="$T/chain.out" GITHUB_STEP_SUMMARY="$T/chain.summary" \
     IN_CHAIN_PROGRESS=0/20 IN_STOP_AFTER_STEP=vera \
     bash "$T/chain.sh" >/dev/null 2>"$T/chain.err"; then
  grep -qx 'block=false' "$T/chain.out" && grep -qx 'continue=false' "$T/chain.out" \
    && grep -q 'stop_after_step=vera' "$T/chain.out" \
    && ok "chaînage : stop_after_step + chain_enabled=true -> aucun lien suivant dispatché" \
    || ko "chaînage : arrêt non tracé ($(tr '\n' ' ' <"$T/chain.out"))"
else
  ko "chaînage : le step chain échoue avec stop_after_step ($(tr '\n' ' ' <"$T/chain.err"))"
fi
grep -qF 'IN_STOP_AFTER_STEP: ${{ inputs.stop_after_step }}' "$PF" \
  && ok "chaînage : l'input stop_after_step est épinglé dans le step chain" \
  || ko "chaînage : input stop_after_step non épinglé dans le step chain"

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
mkdone_any() { # liste des agents autorisés ; le PASS d'un agent suffit (OC_DONE_AGENTS_ANY=1)
cat >"$T/done" <<S
#!/usr/bin/env bash
if [ "\${OC_DONE_AGENTS_ANY:-}" = 1 ] && [ "\${OC_DONE_AGENTS:-}" = "$1" ]; then echo done_check=ok; exit 0; fi
echo "done_check=ko raison=a:any:\${OC_DONE_AGENTS:-}"
exit 1
S
chmod +x "$T/done"
}
run_wrapper() { # $1=done_agents ; $2=étape bornée (défaut vera) ; $3=mode ANY
  local stop="${2:-vera}" any="${3:-}"
  rm -f "$T/oc.runs" "$T/log"*; : >"$T/log"; : >"$T/log.status"
  env ANTENLY_DIR="$T/repo-ant" OC_PROMPT_FILE="$T/prompt.md" OC_LOG="$T/log" \
    OC_MODEL_MAIN=opencode/main-free OC_MODEL_CHAIN=opencode/fb-free \
    OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 OC_IDLE_SEC=2 OC_POLL_SEC=1 \
    OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC=0 OC_STORE_DIR="$T/store" OC_BIN="$T/oc" \
    OC_STALL_RESUMES=2 OC_AGENT_DIR="$T/agents" OC_DONE_CHECK_BIN="$T/done" \
    OC_DONE_CHECK_SEC=1 OC_DONE_IDLE_SEC=1 OC_INTERNAL_LOG="$T/log.internal" \
    OC_INTERNAL_LOG_DIR="$T/internals" OC_STOP_AFTER_STEP="$stop" OC_DONE_AGENTS="$1" \
    OC_DONE_AGENTS_ANY="$any" \
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

mkdone_any "Designer,Aditi,Engineer,Forge,Anvil"
run_wrapper "Designer,Aditi,Engineer,Forge,Anvil" build 1; rc=$?
if [ "$rc" -eq 0 ] && grep -qx 'arret=max_pass' "$T/log.status" \
   && [ "$(wc -l <"$T/oc.runs")" -eq 1 ]; then
  ok "wrapper : PASS d'un des agents autorisés en build (ANY) -> arrêt immédiat"
else
  ko "wrapper/any : rc=$rc $(tr '\n' ' ' <"$T/log.status" 2>/dev/null)"
fi

exit "$fail"
