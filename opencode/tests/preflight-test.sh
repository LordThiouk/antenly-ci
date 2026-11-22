#!/usr/bin/env bash
# Préflight du lien FullRun : AVANT opencode, lecture seule, dire où la porte démarrera et si l'agent imposé par
# le chaînage y sera accepté. Incident (22 nov. 2026, runs 45007041407, 45014947646, 45040922754) :
# start_step=verify + chain_phase=verify + next=code-reviewer, aucun verdict build signé dans le carry → la porte
# redescend au build, rejette code-reviewer et le run tourne ~95 min sans revue.
# Le script du step est extrait du YAML réel, jamais recopié ici.
#   opencode/tests/preflight-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WF="$HERE/../../.github/workflows/opencode-fullrun.yml"
fail=0; nok=0; nko=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { printf 'OK   %s\n' "$*"; nok=$((nok + 1)); }
ko() { printf 'FAIL %s\n' "$*"; fail=1; nko=$((nko + 1)); }

# --- 1. Le step existe, est placé avant opencode et après la préparation du dépôt ------------------------
python3 - "$WF" "$T/pre.sh" "$T/meta" <<'PY' || { ko "le step preflight est absent du workflow"; printf 'résumé : %d ok, %d ko\n' "$nok" "$nko"; exit 1; }
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = wf["jobs"]["fullrun"]["steps"]
names = [s.get("name", "") for s in steps]
idx = lambda pred: next(i for i, n in enumerate(names) if pred(n))
pre = next(s for s in steps if s.get("id") == "preflight")
open(sys.argv[2], "w").write("#!/usr/bin/env bash\nset -euo pipefail\n" + pre["run"])
i_pre = steps.index(pre)
i_prep = steps.index(next(s for s in steps if s.get("id") == "prep"))
i_run = idx(lambda n: n.startswith("opencode run"))
i_frozen = idx(lambda n: n.startswith("Outils de contrôle figés"))
open(sys.argv[3], "w").write(
    f"after_prep={int(i_pre > i_prep)}\nbefore_opencode={int(i_pre < i_run)}\nbefore_frozen={int(i_pre < i_frozen)}\n"
    f"if={pre.get('if', '')}\nhas_secrets={int('secrets.' in str(pre))}\n"
    f"writes_github_env={int('GITHUB_ENV' in pre['run'])}\n")
PY
chmod +x "$T/pre.sh"
meta() { rg "^$1=" "$T/meta" | cut -d= -f2-; }
[ "$(meta after_prep)" = 1 ] && ok "le préflight vient après « Préparer le dépôt antenly et le prompt » (l'ISA et la clé sont en place)" || ko "préflight placé avant la préparation du dépôt"
[ "$(meta before_opencode)" = 1 ] && [ "$(meta before_frozen)" = 1 ] && ok "le préflight vient avant le gel des outils et avant opencode (rien à dépenser avant)" || ko "préflight placé après opencode ou après le gel"
meta if | rg -q "OC_START_STEP" && meta if | rg -q "OC_ISA_PATH" && ok "le step ne tourne que si start_step ET isa_path sont donnés" || ko "condition du step: $(meta if)"
[ "$(meta has_secrets)" = 0 ] && ok "le step ne reçoit aucun secret" || ko "le step référence un secret"
[ "$(meta writes_github_env)" = 0 ] && ok "le step n'écrit pas dans GITHUB_ENV (lecture seule, aucune porte influencée)" || ko "le step écrit dans GITHUB_ENV"

# --- 2. Logique du step avec un CLI factice (code, arguments) -----------------------------------------
mkhome() { # $1 = répertoire HOME ; $2 = code de sortie du CLI factice ; $3 = texte stderr
  mkdir -p "$1/.claude/LIFEOS/TOOLS" "$1/ant/MEMORY/WORK/x" "$1/bin"
  : >"$1/ant/MEMORY/WORK/x/ISA.md"
  cat >"$1/.claude/LIFEOS/TOOLS/FullRunPreflight.ts" <<EOF
// factice : le test ne juge que le step
EOF
  cat >"$1/bin/bun" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$1/argv"
printf '%s\n' "\${OC_DONE_AGENTS-<non défini>}" >"$1/done_agents"
printf '%s\n' '$3' >&2
printf '{"ok":%s}\n' "\$([ $2 = 0 ] && echo true || echo false)"
exit $2
EOF
  chmod +x "$1/bin/bun"
}
run_pre() { # $1 = home, $2 = chain_enabled, $3 = next ; env minimal, le step est le seul code testé
  env -i PATH="$1/bin:/usr/bin:/bin" HOME="$1" RUNNER_TEMP="$1" GITHUB_STEP_SUMMARY="$1/summary" \
    ANTENLY_DIR="$1/ant" OC_ISA_PATH="MEMORY/WORK/x/ISA.md" OC_START_STEP=verify \
    IN_CHAIN_ENABLED="$2" IN_CHAIN_PHASE=verify IN_NEXT="$3" IN_DONE_AGENTS=Max \
    bash "$T/pre.sh" >"$1/out" 2>&1
}

H="$T/h0"; mkhome "$H" 0 "[preflight] porte verify"
run_pre "$H" true code-reviewer; rc=$?
[ "$rc" = 0 ] && ok "porte ouverte (CLI code 0) : le step passe" || ko "CLI code 0 : le step a échoué rc=$rc ($(tail -3 "$H/out" | tr '\n' ' '))"
for want in "--isa" "$H/ant/MEMORY/WORK/x/ISA.md" "--start-step" "verify" "--chain-phase" "--next" "code-reviewer"; do
  rg -qxF -- "$want" "$H/argv" || { ko "argument manquant au CLI : $want"; break; }
done && ok "le CLI reçoit l'ISA, start_step, chain_phase et next (chaînage actif)"
[ "$(cat "$H/done_agents")" = Max ] && ok "done_agents est transmis (OC_DONE_AGENTS) comme pour la porte" || ko "OC_DONE_AGENTS non transmis"

H="$T/h1"; mkhome "$H" 0 "x"
run_pre "$H" false ""; rc=$?
if [ "$rc" = 0 ] && ! rg -q -- "--chain-phase|--next" "$H/argv"; then ok "chaînage inactif : ni chain_phase ni next transmis (aucun conflit inventé)"; else ko "chaînage inactif : arguments inattendus ($(tr '\n' ' ' <"$H/argv"))"; fi

H="$T/h2"; mkhome "$H" 2 "[preflight] CONFLIT : chain_phase=verify suppose une porte ouverte à verify mais le run démarrera à build ; [preflight] relance conseillée : start_step=build chain_phase=build next=(vide)"
run_pre "$H" true code-reviewer; rc=$?
[ "$rc" != 0 ] && ok "conflit (CLI code 2) : le step échoue avant opencode" || ko "conflit non bloquant (rc=$rc)"
rg -q "::error::" "$H/out" && rg -q "start_step=build chain_phase=build" "$H/out" && ok "le message d'échec contient les paramètres exacts de relance" || ko "message de conflit sans paramètres de relance : $(tail -4 "$H/out" | tr '\n' ' ')"

H="$T/h3"; mkhome "$H" 1 "[preflight] entrée invalide : ISA introuvable"
run_pre "$H" true code-reviewer; rc=$?
[ "$rc" = 0 ] && rg -q "::warning::" "$H/out" && ok "entrée invalide (CLI code 1) : avertissement, pas d'échec (le préflight n'est pas une porte)" || ko "CLI code 1 : rc=$rc $(tail -3 "$H/out" | tr '\n' ' ')"

H="$T/h4"; mkhome "$H" 0 "x"; rm -f "$H/.claude/LIFEOS/TOOLS/FullRunPreflight.ts"
run_pre "$H" true code-reviewer; rc=$?
[ "$rc" = 0 ] && rg -q "::warning::.*(lifeos_ref|indisponible)" "$H/out" && ok "lifeos sans FullRunPreflight.ts : avertissement nommant lifeos_ref, le run n'est pas bloqué" || ko "CLI absent : rc=$rc $(tail -3 "$H/out" | tr '\n' ' ')"

# --- 2b. Le README dit la cause, la règle du périmètre et les paramètres de relance ----------------------
R="$HERE/../../README.md"
rg -q "Préflight du lien" "$R" && rg -q "pas de verdict signé" "$R" && rg -q "step build rejects agent" "$R" && ok "README : la cause de la redescente est documentée" || ko "README : cause absente"
rg -q "pose \*\*pendant\*\* le build|posé \*\*pendant\*\* le build" "$R" && rg -q "avant\*\* le lancement" "$R" && ok "README : un marqueur de périmètre doit être dans l'ISA avant le lancement (gel dès l'étape 4)" || ko "README : règle du périmètre absente"
rg -q 'start_step=build`, `chain_phase=build`' "$R" && rg -q 'start_step=verify`, `chain_phase=verify`, `next=<agent>`' "$R" && ok "README : paramètres exacts du prochain lien (build puis verify)" || ko "README : paramètres de relance absents"

# --- 3. Bout en bout avec le vrai CLI lifeos, s'il est présent (sinon SKIP, dit tel quel) ------------------
CLI=""
for c in "${LIFEOS_DIR:-/nonexistent}/LIFEOS/TOOLS/FullRunPreflight.ts" "$HOME/.claude/LIFEOS/TOOLS/FullRunPreflight.ts"; do
  [ -f "$c" ] && { CLI="$c"; break; }
done
if [ -n "$CLI" ] && command -v bun >/dev/null 2>&1; then
  H="$T/real"; mkdir -p "$H/.claude/LIFEOS/TOOLS" "$H/ant/MEMORY/WORK/x"
  git -C "$H/ant" init -q
  printf -- '---\ntask: x\nphase: climbing\n---\n# ISA\n## Criteria\n- [ ] ISC-1: x\n' >"$H/ant/MEMORY/WORK/x/ISA.md"
  ln -s "$(dirname "$CLI")"/* "$H/.claude/LIFEOS/TOOLS/" 2>/dev/null
  ln -s "$(dirname "$(dirname "$CLI")")/../hooks" "$H/.claude/hooks" 2>/dev/null
  run_real() { env -i PATH="$(dirname "$(command -v bun)"):/usr/bin:/bin" HOME="$H" RUNNER_TEMP="$H" GITHUB_STEP_SUMMARY="$H/summary" \
      ANTENLY_DIR="$H/ant" OC_ISA_PATH="MEMORY/WORK/x/ISA.md" OC_START_STEP=verify IN_CHAIN_ENABLED=true IN_CHAIN_PHASE=verify \
      IN_NEXT=code-reviewer IN_DONE_AGENTS=Max bash "$T/pre.sh" >"$H/out" 2>&1; }
  run_real; rc=$?
  if [ "$rc" != 0 ] && rg -q "code-reviewer" "$H/out" && rg -q "relance conseillée" "$H/out"; then ok "vrai CLI lifeos : start_step=verify sans verdict signé + code-reviewer imposé → échec avec relance"; else ko "vrai CLI lifeos : rc=$rc $(tail -5 "$H/out" | tr '\n' ' ')"; fi
else
  printf 'SKIP vrai CLI lifeos absent (lifeos_ref sans FullRunPreflight.ts) : couvert par les tests de lifeos\n'
fi

printf 'résumé : %d ok, %d ko\n' "$nok" "$nko"
exit "$fail"
