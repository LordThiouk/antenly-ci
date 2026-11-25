#!/usr/bin/env bash
# C1 — copie root-owned des outils de confiance avant opencode, puis exécution
# des étapes post-opencode depuis cette copie (jamais depuis ci/, modifiable).
# Sans réseau, sans secret : analyse structurelle du workflow publié.
#   opencode/tests/critical-frozen-tools-test.sh
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"

wf="$here/../.github/workflows/_agent-run.yml"
[ -f "$wf" ] || ko "workflow introuvable : $wf"

python3 - "$wf" <<'PY' || exit 1
import sys
import yaml

wf = sys.argv[1]
y = yaml.safe_load(open(wf))
steps = y["jobs"]["run"]["steps"]
names = [s.get("name", "") for s in steps]

def idx(needle):
    for i, n in enumerate(names):
        if needle in n:
            return i
    raise AssertionError("step introuvable : %s" % needle)

i_freeze = idx("Outils de confiance figés")
i_oc = idx("Exécuter opencode")
assert i_freeze < i_oc, "la copie root doit précéder opencode"

freeze = steps[i_freeze]["run"]
for needle in (
    "sudo chmod go-w /opt",
    'T="$TOOLS_DIR"',
    "ci/opencode",
    "ci/targets",
    "sudo chown -R root:root",
    'find "$T" -user "$(id -u)"',
):
    assert needle in freeze, "copie root incomplète : %r absent" % needle
assert "/opt/lifeos-ci-tools" in open(wf).read(), "répertoire de confiance absent"

post = steps[i_oc + 1:]
post_txt = "\n".join(s.get("run", "") for s in post)
for needle in (
    '"$TOOLS_DIR/opencode/lifeos-guard.sh"',
    '"$TOOLS_DIR/opencode/gitleaks"',
    '"$TOOLS_DIR/opencode/notify.sh"',
):
    assert needle in post_txt, "étape post-opencode sans copie figée : %r" % needle
for forbidden in ("ci/opencode/", "ci/targets/", "ci/opencode", "ci/targets"):
    assert forbidden not in post_txt, "étape post-opencode exécute encore ci/ : %r" % forbidden

oc = steps[i_oc]["run"]
assert '"$TOOLS_DIR/opencode/quota.sh"' in oc, "opencode n'utilise pas la copie figée de quota.sh"
assert "ci/opencode/quota.sh" not in oc, "quota.sh lu depuis ci/ après le début d'opencode"

print("OK   freeze root avant opencode, post-opencode via $TOOLS_DIR uniquement")
PY
