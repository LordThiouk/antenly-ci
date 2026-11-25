#!/usr/bin/env bash
# Défaut 1 — prompt du PREMIER lien d'une chaîne lancée directement en build/verify/close.
# Le script de la garde doit être l'UNIQUE endroit qui choisit le prompt selon chain_phase
# (IN_PROMPT_EFFECTIVE), le step prep doit le consommer, et le dispatch doit passer prompt_path
# inchangé (la garde du lien suivant refait le choix avec SON chain_phase).
# Les trois scripts sont extraits du YAML réel, jamais recopiés ici.
#   opencode/tests/first-link-prompt-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WF="$HERE/../../../.github/workflows/opencode-fullrun.yml"
R="$HERE/../../run-fullrun.sh"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { printf 'OK   %s\n' "$*"; }
ko() { printf 'FAIL %s\n' "$*"; fail=1; }

python3 - "$WF" "$T/guard.sh" "$T/prep.sh" "$T/chain.sh" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = wf["jobs"]["fullrun"]["steps"]
for sid, out in (("guard", sys.argv[2]), ("prep", sys.argv[3]), ("chain", sys.argv[4])):
    step = next(s for s in steps if s.get("id") == sid)
    open(out, "w").write("#!/usr/bin/env bash\nset -euo pipefail\n" + step["run"])
PY
chmod +x "$T/guard.sh" "$T/prep.sh" "$T/chain.sh"

# --- 1. La garde choisit le prompt effectif selon chain_phase (seul endroit qui décide) -------------
run_guard() { # $1 = chain_enabled, $2 = chain_phase
  : >"$T/genv"; : >"$T/gout"
  env -i PATH="/usr/bin:/bin" HOME="$T" GITHUB_ENV="$T/genv" GITHUB_OUTPUT="$T/gout" RUNNER_TEMP="$T" \
    IN_BRANCH=feat/x IN_JOB=job1 IN_PROMPT=prompts:p.md IN_LIFEOS_REF=main IN_HF_CORPUS= \
    OC_ISA_PATH="MEMORY/WORK/x/ISA.md" IN_IDLE_MIN=20 IN_AGENT_IDLE_MIN= IN_START_STEP= \
    IN_DONE_AGENTS=Max IN_WIP_PUSH_MIN=30 IN_PREV_RUN_ID= IN_NEXT= \
    IN_PROMPT_BUILD=prompts:b.md IN_PROMPT_VERIFY=prompts:v.md IN_PROMPT_CLOSE=prompts:c.md \
    OC_MODEL_MAIN=opencode/m-free OC_MODEL_MAX=opencode/x-free \
    OC_MODEL_CHAIN=opencode/f-free IN_CHAIN_ENABLED="$1" IN_CHAIN_PHASE="$2" \
    IN_CHAIN_PROGRESS=0/20 IN_STOP_AFTER_STEP= IN_TARGET_AGENT= \
    bash "$T/guard.sh" >"$T/gout.stdout" 2>"$T/gerr"
}
eff() { grep -E "^IN_PROMPT_EFFECTIVE=" "$T/genv" 2>/dev/null | cut -d= -f2- || true; }

for pair in "plan:prompts:p.md" "build:prompts:b.md" "verify:prompts:v.md" "close:prompts:c.md"; do
  phase="${pair%%:*}"; want="${pair#*:}"
  run_guard true "$phase"
  got=$(eff)
  if [ "$got" = "$want" ]; then
    ok "garde chaînée : chain_phase=$phase -> IN_PROMPT_EFFECTIVE=$want"
  else
    ko "garde chaînée : phase=$phase, effectif « $got » (attendu $want) — $(cat "$T/gerr")"
  fi
done
run_guard false build
got=$(eff)
if [ "$got" = prompts:p.md ]; then
  ok "hors chaîne : IN_PROMPT_EFFECTIVE=prompt_path, comportement inchangé"
else
  ko "hors chaîne : effectif « $got » au lieu de prompts:p.md"
fi

# --- 2. Le step prep CONSOMME le prompt effectif (vrai dépôt, vrai git, vraie branche de prompts) ---
mkdir -p "$T/bin" "$T/ci/opencode" "$T/antenly" "$T/oc"
cp "$HERE/../../ci-preamble.md" "$T/ci/opencode/ci-preamble.md"
cat >"$T/bin/envsubst" <<'S'
#!/bin/sh
cat
S
chmod +x "$T/bin/envsubst"
(
  # Dépôt jetable isolé de la config git globale du runner (hooksPath LifeOS) : sinon les commits
  # de fixture sont refusés et les refs de prompts restent vides.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  cd "$T/antenly" || exit 1
  git init -q -b feat/x
  git config user.email t@t.local; git config user.name test
  echo x > f; git add f; git commit -qm init
  git checkout -qb fullrun-prompts
  printf 'PROMPT-PLAN\n' >p.md
  printf 'PROMPT-BUILD\n' >b.md
  printf 'PROMPT-VERIFY\n' >v.md
  printf 'PROMPT-CLOSE\n' >c.md
  git add p.md b.md v.md c.md; git commit -qm prompts
  git checkout -q feat/x
  git update-ref refs/remotes/origin/feat/x refs/heads/feat/x
  git update-ref refs/remotes/origin/fullrun-prompts refs/heads/fullrun-prompts
) || { ko "préparation du dépôt de test"; exit $fail; }

run_prep() { # $1 = prompt_path brut, $2 = prompt effectif, $3 = chain_enabled, $4 = phase
  # prep consomme la référence distante (usage unique, supprimée en fin d'étape) : la recréer.
  ( cd "$T/antenly" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
      git update-ref refs/remotes/origin/fullrun-prompts refs/heads/fullrun-prompts )
  : >"$T/gout"; : >"$T/genv"
  env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T" GITHUB_OUTPUT="$T/gout" GITHUB_ENV="$T/genv" \
    RUNNER_TEMP="$T" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    ANTENLY_DIR="$T/antenly" CI_DIR="$T/ci" OC_WORK="$T/oc" \
    IN_BRANCH=feat/x IN_JOB=job1 IN_PROMPT="$1" IN_PROMPT_EFFECTIVE="$2" \
    IN_CHAIN_ENABLED="$3" IN_CHAIN_PHASE="$4" IN_NEXT= \
    OC_MODEL_MAIN=opencode/m-free OC_MODEL_MAX=opencode/x-free OC_JOB=job1 \
    OC_REPORT="$T/oc/REPORT.md" OC_BRANCH=feat/x \
    bash "$T/prep.sh" >"$T/prep.out" 2>"$T/prep.err"
}
run_prep prompts:p.md prompts:b.md true build; rc=$?
if [ "$rc" -eq 0 ] && grep -Eq '^PROMPT-BUILD$' "$T/oc/prompt.md" && ! grep -Eq '^PROMPT-PLAN$' "$T/oc/prompt.md"; then
  ok "prep chaîné (build) : le prompt du job est prompt_path_build, pas le gros prompt plan"
else
  ko "prep chaîné (rc=$rc) : mauvais prompt ou échec de prep — out=$(cat "$T/prep.out" 2>/dev/null) err=$(cat "$T/prep.err" 2>/dev/null) prompt=$(tail -n 3 "$T/oc/prompt.md" 2>/dev/null)"
fi
run_prep prompts:p.md prompts:p.md false plan; rc=$?
if [ "$rc" -eq 0 ] && grep -Eq '^PROMPT-PLAN$' "$T/oc/prompt.md"; then
  ok "prep hors chaîne : prompt_path inchangé"
else
  ko "prep hors chaîne (rc=$rc) : prompt absent — out=$(cat "$T/prep.out" 2>/dev/null) err=$(cat "$T/prep.err" 2>/dev/null)"
fi

# --- 3. Un seul endroit qui décide : prep lit l'effectif, chain ne recalcule plus de prompt ----------
if grep -Eq 'IN_PROMPT_EFFECTIVE' "$T/prep.sh"; then
  ok "prep : lit IN_PROMPT_EFFECTIVE"
else
  ko "prep : n'utilise pas IN_PROMPT_EFFECTIVE"
fi
if ! grep -Eq 'src="\$\{IN_PROMPT%%:\*\}"' "$T/prep.sh"; then
  ok "prep : plus de lecture directe de IN_PROMPT"
else
  ko "prep : lit encore IN_PROMPT directement"
fi
if grep -Eq 'IN_PROMPT_EFFECTIVE' "$T/guard.sh"; then
  ok "garde : calcule IN_PROMPT_EFFECTIVE"
else
  ko "garde : ne calcule pas l'effectif"
fi
if ! grep -Eq 'next_prompt' "$T/chain.sh"; then
  ok "chain : aucun second calcul du prompt (prompt_path transmis inchangé)"
else
  ko "chain : recalcule encore next_prompt (deux endroits qui décident)"
fi
if grep -Eq 'prompt_path="\$IN_PROMPT"' "$T/chain.sh"; then
  ok "chain : prompt_path=IN_PROMPT inchangé au dispatch"
else
  ko "chain : prompt_path modifié au dispatch"
fi

# --- 4. Garde de non-régression sur la chaîne de secours (défaut 2, simple présence) -----------------
if grep -Eq 'OC_ERROR_IDLE_SEC:-240' "$R"; then
  ok "run-fullrun.sh : OC_ERROR_IDLE_SEC a un défaut de 240 s"
else
  ko "run-fullrun.sh : OC_ERROR_IDLE_SEC absent ou sans défaut"
fi

exit $fail
