#!/usr/bin/env bash
# M2 — contrat de `FullRunPipeline.ts unit --isa --stop-after` (clés .exit/.reason/.next) vérifié contre le
# VRAI outil lifeos (le checkout épinglé par la CI, ref main), sur une ISA fixture, et non contre un faux bun :
#  1. schéma de sortie (exit ∈ suite_a_faire|termine|echec, code, reason, next) pour step/task/agent ;
#  2. progression plan → build → verify → close → termine, valeurs de .next EXACTEMENT celles que le step
#     « Décision de chaînage » attend par phase (plan 1-3 puis 4 ; verify 6 ; close 6-7) ;
#  3. le vrai step chain (script extrait du YAML, vrai bun) : plan → dispatch build ; build/verify sans
#     cible enregistrée ⇒ arrêt avec raison (jamais un lien sans cible) ; état complet ⇒ chaîne terminée.
#   opencode/tests/unit-contract-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WF="$HERE/../../.github/workflows/opencode-fullrun.yml"
# shellcheck source=opencode/tests/verdict-cli.lib
. "$HERE/verdict-cli.lib"
TOOLS=$(dirname "$OC_VERDICT_CLI"); PIPE="$TOOLS/FullRunPipeline.ts"
[ -f "$PIPE" ] || { echo "ko FullRunPipeline.ts introuvable à côté du CLI de verdict ($PIPE)"; exit 1; }
LIFEOS_ROOT=$(cd "$TOOLS/../.." && pwd)
BUN=$(command -v bun || echo "$HOME/.bun/bin/bun")
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { echo "OK   $*"; }; ko() { echo "FAIL $*"; fail=1; }

export HOME="$T/home"; mkdir -p "$HOME/.bun/bin" "$T/target/MEMORY/WORK/x"
ln -s "$BUN" "$HOME/.bun/bin/bun"
ISA="$T/target/MEMORY/WORK/x/ISA.md"
cat >"$ISA" <<'ISAEOF'
---
task: fixture contrat unit
slug: x
project: test
effort: E1
phase: plan
progress: 0/1
---
## Goal

Fixture du contrat unit --isa.

## Criteria

- [ ] ISC-1: fixture | pass | aucune
ISAEOF

unit() { "$BUN" "$PIPE" unit --isa "$ISA" --stop-after "$1" 2>/dev/null; }
field() { printf '%s' "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); v=d.get(sys.argv[1],''); print(v)" "$2"; }
schema_ok() { printf '%s' "$1" | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert d['exit'] in ('suite_a_faire','termine','echec'), d
assert isinstance(d['code'],int) and isinstance(d['reason'],str) and d['reason'], d
assert ('next' not in d) or isinstance(d['next'],str), d
" 2>/dev/null; }

"$BUN" "$PIPE" init --isa "$ISA" --session itest >/dev/null 2>&1 || { ko "init sur l'ISA fixture impossible"; exit 1; }

# 1. schéma, sur les trois granularités, avant toute progression
for g in step task agent; do
  o=$(unit "$g"); schema_ok "$o" && ok "schéma $g : exit/code/reason (next facultatif, chaîne)" || ko "schéma $g invalide : $o"
done
o=$(unit task); [ "$(field "$o" exit)" = echec ] && [ -z "$(field "$o" next)" ] \
  && ok "task sans tâche enregistrée ⇒ echec sans next (le chain doit s'arrêter)" || ko "task initial inattendu : $o"
o=$(unit agent); [ "$(field "$o" exit)" = echec ] && [ -z "$(field "$o" next)" ] \
  && ok "agent sans résultat verify ⇒ echec sans next" || ko "agent initial inattendu : $o"

# 2. progression par étapes (granularité step) : next attendu à chaque palier
o=$(unit step); [ "$(field "$o" exit)" = suite_a_faire ] && [ "$(field "$o" next)" = 1 ] && ok "plan : next=1 après l'init" || ko "init : $o"
for pair in "1:2" "2:3" "3:4" "4:5" "5:6" "6:7"; do
  s=${pair%%:*}; want=${pair#*:}
  "$BUN" "$PIPE" advance --isa "$ISA" --step "$s" --result pass >/dev/null 2>&1
  o=$(unit step)
  [ "$(field "$o" exit)" = suite_a_faire ] && [ "$(field "$o" next)" = "$want" ] \
    && ok "après l'étape $s : next=$want (suite_a_faire)" || ko "après l'étape $s : attendu next=$want : $o"
done
"$BUN" "$PIPE" advance --isa "$ISA" --step 7 --result pass >/dev/null 2>&1
o=$(unit step); [ "$(field "$o" exit)" = termine ] && ok "après l'étape 7 : exit=termine (run clos)" || ko "fin : $o"

# 3. le VRAI step chain avec le vrai bun : une ISA/état neufs par phase
python3 - "$WF" "$T/chain.sh" <<'PY'
import sys, yaml
y = yaml.safe_load(open(sys.argv[1]))
step = next(s for s in y["jobs"]["fullrun"]["steps"] if s.get("id") == "chain")
open(sys.argv[2], "w").write("#!/usr/bin/env bash\nset -euo pipefail\n" + step["run"])
PY
cat >"$HOME/.bun/bin/gh" <<S
#!/usr/bin/env bash
[ "\$1" = workflow ] && [ "\$2" = run ] && echo "\$@" > "$T/gh_args"
exit 0
S
chmod +x "$HOME/.bun/bin/gh"
fake_tok="canari-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
real_chain() { # $1 = phase
  rm -f "$T/out" "$T/gh_args"; : >"$T/out"; : >"$T/summary"
  env -i PATH="$PATH" HOME="$HOME" GITHUB_OUTPUT="$T/out" GITHUB_STEP_SUMMARY="$T/summary" GITHUB_REF_NAME=feat \
    TARGET_DIR="$T/target" LIFEOS_DIR="$LIFEOS_ROOT" IN_BRANCH=feat-x IN_JOB=job1 IN_PROMPT=prompts:p.md \
    IN_PROMPT_BUILD=prompts:b.md IN_PROMPT_VERIFY=prompts:v.md IN_PROMPT_CLOSE=prompts:c.md IN_LIFEOS_REF=main \
    OC_MODEL_MAIN=opencode/m-free OC_MODEL_MAX=opencode/x-free OC_MODEL_FALLBACK=opencode/f-free OC_MODEL_CHAIN=opencode/f-free \
    IN_AGENT_IDLE_MIN= IN_IDLE_MIN=20 IN_DONE_AGENTS=Max IN_WIP_PUSH_MIN=30 IN_TARGET=Galass_Rider IN_EXTRA= \
    IN_WITH_EMU=false IN_VALIDATE_ONLY=false OC_ISA_PATH="MEMORY/WORK/x/ISA.md" IN_CHAIN_PHASE="$1" IN_CHAIN_COUNT=0 \
    IN_CHAIN_MAX=20 IN_PREV_RUN_ID= RUN_ID=1 RESTORE_STATE_OUTCOME= RESTORE_STATE_STATUS= DISPATCH_TOKEN="$fake_tok" \
    SAVE_STATE_OUTCOME=success HAS_STATE=true PUBLISH_STATE_OUTCOME=success OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success \
    bash "$T/chain.sh" >"$T/chain_log" 2>&1
}
fresh() { rm -rf "$HOME/.claude"; sed -i 's/^phase: .*/phase: plan/' "$ISA"; "$BUN" "$PIPE" init --isa "$ISA" --session itest >/dev/null 2>&1; }
out_eq() { grep -qx "$1=$2" "$T/out"; }

fresh; real_chain plan
{ out_eq continue true && grep -q '"phase":"plan"' "$T/gh_args"; } && ok "vrai chain : plan (next=1) ⇒ lien suivant en phase plan" || ko "plan next=1 : $(cat "$T/out") $(cat "$T/chain_log")"
for s in 1 2; do "$BUN" "$PIPE" advance --isa "$ISA" --step $s --result pass >/dev/null 2>&1; done
real_chain plan
{ out_eq continue true && grep -q '"phase":"plan"' "$T/gh_args"; } && ok "vrai chain : plan (next=3) ⇒ reste en plan" || ko "plan next=3 : $(cat "$T/out")"
"$BUN" "$PIPE" advance --isa "$ISA" --step 3 --result pass >/dev/null 2>&1
real_chain plan
{ out_eq continue true && grep -q '"phase":"build"' "$T/gh_args"; } && ok "vrai chain : plan (next=4) ⇒ dispatch phase build" || ko "plan next=4 : $(cat "$T/out") $(cat "$T/chain_log")"

for ph in build verify; do
  fresh; real_chain "$ph"
  { out_eq block true && [ ! -f "$T/gh_args" ]; } && ok "vrai chain : $ph sans cible enregistrée ⇒ arrêt (raison), zéro dispatch" || ko "$ph sans cible : $(cat "$T/out")"
  grep -q '^reason=.\+' "$T/out" && ok "vrai chain : $ph arrêté AVEC une raison lisible" || ko "$ph : raison vide : $(cat "$T/out")"
done

# build (granularité task) avec le vrai outil : plan de 2 tâches, signées l'une après l'autre sur HEAD
fresh; for s in 1 2 3; do "$BUN" "$PIPE" advance --isa "$ISA" --step $s --result pass >/dev/null 2>&1; done
( cd "$T/target" && git init -q . && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm fixture ) >/dev/null 2>&1
sha=$(git -C "$T/target" rev-parse HEAD 2>/dev/null)
"$BUN" "$PIPE" build-plan --isa "$ISA" --tasks T1,T2 >/dev/null 2>&1
"$BUN" "$PIPE" task-done --isa "$ISA" --task T1 --sha "$sha" --cmd true >/dev/null 2>&1
o=$(unit task); { [ "$(field "$o" exit)" = suite_a_faire ] && [ "$(field "$o" next)" = T2 ]; } \
  && ok "task : T1 faite ⇒ suite_a_faire, next=T2 (ID de tâche)" || ko "task T1 : $o"
real_chain build
{ out_eq continue true && grep -q '"phase":"build"' "$T/gh_args" && grep -q '"next":"T2"' "$T/gh_args"; } \
  && ok "vrai chain : build (next=T2) ⇒ reste en build avec la cible T2 imposée" || ko "build T2 : $(cat "$T/out") $(cat "$T/gh_args" 2>/dev/null)"
"$BUN" "$PIPE" task-done --isa "$ISA" --task T2 --sha "$sha" --cmd true >/dev/null 2>&1
real_chain build
{ out_eq block true && [ ! -f "$T/gh_args" ]; } && ok "vrai chain : build complet sans avance enregistrée ⇒ arrêt (jamais un lien de plus)" || ko "build sans avance : $(cat "$T/out")"
"$BUN" "$PIPE" advance --isa "$ISA" --step 4 --result pass >/dev/null 2>&1
real_chain build
{ out_eq continue true && grep -q '"phase":"verify"' "$T/gh_args"; } && ok "vrai chain : build terminé + avance ⇒ dispatch phase verify" || ko "build→verify : $(cat "$T/out") $(cat "$T/chain_log")"

fresh; for s in 1 2 3 4 5 6; do "$BUN" "$PIPE" advance --isa "$ISA" --step $s --result pass >/dev/null 2>&1; done
real_chain close
{ out_eq continue true && grep -q '"phase":"close"' "$T/gh_args"; } && ok "vrai chain : close (next=7) ⇒ reste en close" || ko "close next=7 : $(cat "$T/out") $(cat "$T/chain_log")"
"$BUN" "$PIPE" advance --isa "$ISA" --step 7 --result pass >/dev/null 2>&1
real_chain close
{ out_eq block false && out_eq continue false && [ ! -f "$T/gh_args" ]; } && ok "vrai chain : run complet ⇒ chaîne terminée, zéro dispatch" || ko "close terminé : $(cat "$T/out")"

exit $fail
