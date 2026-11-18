#!/usr/bin/env bash
# Step « opencode run » (id: oc) du workflow opencode-fullrun.yml : OC_DEADLINE_EPOCH doit tomber
# STRICTEMENT avant que GitHub ne tue le step par timeout-minutes, dans les deux modes (chaîné et
# non chaîné), ET laisser au moins OC_PUSH_MARGIN_MIN avant le kill du JOB quelle que soit la durée
# du préambule (revue 2, point 3 : deux horloges, min des deux). Lit les valeurs directement dans le
# YAML publié — jamais une copie figée — et vérifie d'abord que OC_STEP_TIMEOUT_MIN est bien l'alias
# YAML de timeout-minutes du step, et OC_JOB_TIMEOUT_MIN l'alias de timeout-minutes du job (pas des
# valeurs recopiées à la main qui pourraient un jour diverger, comme l'ancien OC_JOB_TIMEOUT_MIN qui
# lisait le timeout du JOB au lieu de celui du STEP — bug corrigé en revue le 18/11). Calcule les
# plafonds avec la même formule que le workflow, sans jamais exécuter le vrai step.
#   opencode/tests/oc-deadline-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WF="$HERE/../../.github/workflows/opencode-fullrun.yml"
fail=0
ok() { echo "OK   $*"; }; ko() { echo "FAIL $*"; fail=1; }

python3 - "$WF" <<'PY' || fail=1
import re
import sys
import yaml

wf = sys.argv[1]
raw = open(wf).read()
y = yaml.safe_load(raw)
steps = y["jobs"]["fullrun"]["steps"]
oc = next(s for s in steps if s.get("id") == "oc")

# --- ancrage des valeurs dans le YAML (jamais une valeur recopiée) --------------------------------
step_to_expr = oc["timeout-minutes"]
step_to_env_expr = oc["env"]["OC_STEP_TIMEOUT_MIN"]
assert step_to_expr == step_to_env_expr and re.search(
    r"^\s*timeout-minutes:\s*&oc_step_timeout_min\s", raw, re.M
) and re.search(r"^\s*OC_STEP_TIMEOUT_MIN:\s*\*oc_step_timeout_min\s*$", raw, re.M), (
    "OC_STEP_TIMEOUT_MIN (%r) doit rester l'alias YAML (ancre *oc_step_timeout_min) de "
    "timeout-minutes du step oc (%r), identiques pour ne plus pouvoir diverger"
    % (step_to_env_expr, step_to_expr)
)
print("OK   OC_STEP_TIMEOUT_MIN est l'alias exact de timeout-minutes du step oc (une seule source)")

# --- borne du JOB : l'ancre est sur le timeout-minutes du job, l'alias dans l'env du step oc ------
job_to_expr = y["jobs"]["fullrun"]["timeout-minutes"]
job_env_expr = oc["env"]["OC_JOB_TIMEOUT_MIN"]
assert job_to_expr == job_env_expr, (
    "OC_JOB_TIMEOUT_MIN (%r) doit valoir timeout-minutes du job fullrun (%r) : les deux horloges "
    "du calcul de plafond doivent porter sur la même valeur" % (job_env_expr, job_to_expr)
)
assert re.search(r"^\s*timeout-minutes:\s*&fullrun_job_timeout_min\s", raw, re.M), (
    "le timeout-minutes du job fullrun doit porter l'ancre &fullrun_job_timeout_min"
)
assert re.search(r"^\s*OC_JOB_TIMEOUT_MIN:\s*\*fullrun_job_timeout_min\s*$", raw, re.M), (
    "OC_JOB_TIMEOUT_MIN doit être l'alias YAML *fullrun_job_timeout_min (pas une valeur recopiée)"
)
print("OK   OC_JOB_TIMEOUT_MIN est l'alias YAML de timeout-minutes du job fullrun (ancre vérifiée)")

# --- l'horloge du job est bien lue en début de job (t0 du step guard) -----------------------------
assert oc["env"].get("OC_JOB_T0") == "${{ steps.guard.outputs.t0 }}", (
    "OC_JOB_T0 doit être ${{ steps.guard.outputs.t0 }} : sans cette horloge, la borne du job "
    "n'est pas la vraie horloge du job"
)
print("OK   OC_JOB_T0 lit l'horloge réelle du job (t0 du step guard)")

# --- le calcul est bien un min de deux horloges ---------------------------------------------------
run = oc["run"]
for token in ("step_deadline", "job_deadline", "OC_DEADLINE_EPOCH"):
    assert token in run, "calcul d'OC_DEADLINE_EPOCH : « %s » absent du run du step oc" % token
assert re.search(r'if\s*\[\s*"\$job_deadline"\s*-lt\s*"\$step_deadline"\s*\]', run), (
    "le run doit retenir le MIN des deux horloges (comparaison job_deadline < step_deadline)"
)
print("OK   run oc : min(step_deadline, job_deadline) retenu dans OC_DEADLINE_EPOCH")


# --- simulation numérique (même formule que le workflow, valeurs lues dans le YAML) ---------------
def branches(expr):
    # Les expressions sont de la forme "${{ inputs.chain_enabled == 'true' && X || Y }}" :
    # X = branche chaînée, Y = branche non chaînée. Parsing minimal, sans réévaluer GitHub Actions.
    m = re.search(r"&&\s*'?(-?\d+)'?\s*\|\|\s*'?(-?\d+)'?", str(expr))
    assert m, "expression inattendue, format non reconnu : %r" % (expr,)
    return int(m.group(1)), int(m.group(2))


step_chain, step_normal = branches(step_to_expr)
job_chain, job_normal = branches(job_to_expr)
margin_chain, margin_normal = branches(oc["env"]["OC_PUSH_MARGIN_MIN"])
kill_grace = int(oc["env"]["OC_KILL_GRACE"])
poll_sec = int(oc["env"]["OC_POLL_SEC"])
m = re.search(r"OC_KILL_GRACE\s*-\s*OC_POLL_SEC\s*-\s*(\d+)", run)
assert m, "terme fixe « OC_KILL_GRACE - OC_POLL_SEC - N » introuvable dans le run du step oc"
extra = int(m.group(1))

PRELUDE_MIN = (0, 10, 11, 12, 30, 60)


def step_deadline_min(prelude_min, step_to, margin):
    # OC_START = t0_job + préambule ; tout est exprimé en minutes depuis t0_job.
    return prelude_min + (step_to - margin) - (kill_grace + poll_sec + extra) / 60.0


def job_deadline_min(job_to, margin):
    return (job_to - margin) - (kill_grace + poll_sec + extra) / 60.0


for label, step_to, job_to, margin in (
    ("chaîné", step_chain, job_chain, margin_chain),
    ("non chaîné", step_normal, job_normal, margin_normal),
):
    for prelude in PRELUDE_MIN:
        step_d = step_deadline_min(prelude, step_to, margin)
        job_d = job_deadline_min(job_to, margin)
        deadline = min(step_d, job_d)
        assert deadline < max(step_d, job_d) or step_d == job_d, "min() incohérent"
        # Kill du step : GitHub le tue à OC_START + timeout ; le plafond doit rester strictement avant.
        assert deadline < prelude + step_to, (
            "%s (préambule %d min) : plafond %.2f min n'est PAS avant le kill du step (%.2f min)"
            % (label, prelude, deadline, prelude + step_to)
        )
        # Kill du job : la marge de push doit rester >= OC_PUSH_MARGIN_MIN, quelle que soit la
        # durée du préambule — c'est l'invariant que la revue 2 (point 3) exige.
        remaining = job_to - deadline
        assert remaining >= margin - 1e-9, (
            "%s (préambule %d min) : marge avant le kill du job %.2f min < OC_PUSH_MARGIN_MIN (%d) "
            "— la marge de push n'est plus structurelle" % (label, prelude, remaining, margin)
        )
    print(
        "OK   %s : marge de push ≥ %d min garantie avant le kill du job pour préambule ∈ %s "
        "(plafonds calculés : %s)"
        % (label, margin, list(PRELUDE_MIN),
           ", ".join("%.2f min" % min(step_deadline_min(p, step_to, margin),
                                      job_deadline_min(job_to, margin)) for p in PRELUDE_MIN))
    )

# Le comportement d'origine est conservé : au préambule nominal (P=0), le plafond STEP reste le plus
# tôt dans les deux modes. En mode non chaîné, l'horloge du JOB prend le relais dès que le préambule
# dépasse ~8 min — c'est précisément le correctif de la revue 2 (point 3), pas une régression.
assert step_deadline_min(0, step_chain, margin_chain) <= job_deadline_min(job_chain, margin_chain)
assert step_deadline_min(0, step_normal, margin_normal) <= job_deadline_min(job_normal, margin_normal)
print("OK   plafond STEP le plus tôt au préambule nominal (P=0) dans les deux modes")
PY

exit $fail
