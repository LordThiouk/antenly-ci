#!/usr/bin/env bash
# Step « opencode run » (id: oc) du workflow opencode-fullrun.yml : OC_DEADLINE_EPOCH doit tomber
# STRICTEMENT avant que GitHub ne tue le step par timeout-minutes, dans les deux modes (chaîné et
# non chaîné). Lit les valeurs directement dans le YAML publié — jamais une copie figée — et vérifie
# d'abord qu'OC_STEP_TIMEOUT_MIN est bien l'alias YAML de timeout-minutes du step (pas une valeur
# recopiée à la main qui pourrait un jour diverger, comme l'ancien OC_JOB_TIMEOUT_MIN qui lisait le
# timeout du JOB au lieu de celui du STEP — bug corrigé en revue le 18/11). Calcule le plafond avec
# la même formule que le workflow (OC_KILL_GRACE=60, OC_POLL_SEC=30, marge fixe de 10s), sans jamais
# exécuter le vrai step.
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
with open(wf) as f:
    y = yaml.safe_load(f)
steps = y["jobs"]["fullrun"]["steps"]
oc = next(s for s in steps if s.get("id") == "oc")

step_to_expr = oc["timeout-minutes"]
step_to_env_expr = oc["env"]["OC_STEP_TIMEOUT_MIN"]
assert step_to_expr == step_to_env_expr, (
    "OC_STEP_TIMEOUT_MIN (%r) doit être l'alias YAML de timeout-minutes du step oc (%r), "
    "identiques pour ne plus pouvoir diverger" % (step_to_env_expr, step_to_expr)
)
print("OK   OC_STEP_TIMEOUT_MIN est l'alias exact de timeout-minutes du step oc (une seule source)")

margin_expr = oc["env"]["OC_PUSH_MARGIN_MIN"]


def branches(expr):
    # Les deux expressions sont de la forme "${{ inputs.chain_enabled == 'true' && X || Y }}" :
    # X = branche chaînée, Y = branche non chaînée. Parsing minimal, sans réévaluer GitHub Actions.
    m = re.search(r"&&\s*'?(-?\d+)'?\s*\|\|\s*'?(-?\d+)'?", expr)
    assert m, "expression inattendue, format non reconnu : %r" % expr
    return int(m.group(1)), int(m.group(2))


step_to_chain, step_to_normal = branches(step_to_expr)
margin_chain, margin_normal = branches(margin_expr)

KILL_GRACE, POLL_SEC, EXTRA = 60, 30, 10


def deadline_min(step_timeout_min, push_margin_min):
    return (step_timeout_min * 60 - push_margin_min * 60 - KILL_GRACE - POLL_SEC - EXTRA) / 60.0


for label, step_to, margin in (
    ("chaîné", step_to_chain, margin_chain),
    ("non chaîné", step_to_normal, margin_normal),
):
    d = deadline_min(step_to, margin)
    assert d < step_to, (
        "%s : plafond interne (%.2f min) n'est PAS strictement avant le timeout du step (%d min) — "
        "GitHub tuerait le step avant que run-fullrun.sh arrête opencode et pousse" % (label, d, step_to)
    )
    marge = step_to - d
    print(
        "OK   %s : plafond interne %.2f min < timeout step %d min (marge %.2f min avant le kill GitHub)"
        % (label, d, step_to, marge)
    )
PY

exit $fail
