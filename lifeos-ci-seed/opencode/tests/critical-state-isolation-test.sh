#!/usr/bin/env bash
# C3 — opencode n'accède ni à GITHUB_ENV/GITHUB_OUTPUT/GITHUB_PATH ni à un
# $RUNNER_TEMP partagé, et les étapes suivantes recalculent le statut, le modèle,
# les SHA de base et la liste des dépôts depuis un état root-owned / des inputs.
# Sans réseau, sans secret.
#   opencode/tests/critical-state-isolation-test.sh
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"

wf="$here/../.github/workflows/_agent-run.yml"
[ -f "$wf" ] || ko "workflow introuvable : $wf"

python3 - "$wf" <<'PY' || exit 1
import sys
import yaml

y = yaml.safe_load(open(sys.argv[1]))
job = y["jobs"]["run"]
steps = job["steps"]
names = [s.get("name", "") for s in steps]

def idx(needle):
    for i, n in enumerate(names):
        if needle in n:
            return i
    raise AssertionError("step introuvable : %s" % needle)

i_run = idx("Exécuter opencode")
i_status = idx("Statut opencode")
i_bases = idx("Enregistrer l'état de départ")
i_push = idx("Porte gitleaks")
assert i_bases < i_run < i_status < i_push, "ordre des étapes de sécurité incorrect"

run = steps[i_run].get("run", "")
for needle in (
    "env -i",
    'HOME="$agent_home"',
    'TMPDIR="$agent_tmp"',
    "STATE_DIR/oc-result",
    "sudo install -o root -g root -m 0644",
):
    assert needle in run, "isolation d'opencode incomplète : %r absent" % needle
for forbidden in ("GITHUB_OUTPUT", "GITHUB_ENV", "GITHUB_PATH"):
    assert forbidden not in run, "opencode écrit encore dans %s" % forbidden

status = steps[i_status]
assert status.get("id") == "oc", "le statut doit être publié par un step dédié id=oc"
srun = status.get("run", "")
assert 'sudo cat "$STATE_DIR/oc-result"' in srun, "le statut n'est pas relu depuis l'état root"
assert '>> "$GITHUB_OUTPUT"' in srun, "le statut dédié ne publie pas d'output"
assert "RUNNER_TEMP" not in srun, "le statut relit un fichier de RUNNER_TEMP"

bases = steps[i_bases].get("run", "")
assert 'sudo install -o root -g root -m 0644 "$tmp" "$STATE_DIR/bases"' in bases
assert "git -C target rev-parse HEAD" in bases, "SHA de base non recalculé avant opencode"

push = steps[i_push]
assert "steps.validate.outputs.extra_norm" in str(push.get("env", {})), \
    "la liste des dépôts n'est pas recalculée depuis l'output immuable de validation"
assert '"$STATE_DIR/bases"' in push.get("run", ""), "le push ne relit pas l'état root"

raw = open(sys.argv[1]).read()
assert '>> "$GITHUB_ENV"' not in raw, "GITHUB_ENV encore utilisé pour un état de sécurité"
assert "agent-repos.txt" not in raw, "ancien état modifiable agent-repos.txt encore utilisé"
assert "lifeos-base.txt" not in raw, "ancien état modifiable lifeos-base.txt encore utilisé"
assert job["outputs"]["status"] == "${{ steps.oc.outputs.status }}"
assert job["outputs"]["model"] == "${{ steps.oc.outputs.model }}"
assert job["outputs"]["head_sha"] == "${{ steps.push.outputs.head_sha }}"
print("OK   opencode isolé ; statut, modèle, SHA et dépôts recalculés hors de sa portée")
PY

# Preuve fonctionnelle : un enfant lancé avec env -i ne voit aucun fichier de
# commande du runner, même si le parent les exporte.
seen=$(GITHUB_ENV=/tmp/env GITHUB_OUTPUT=/tmp/out GITHUB_PATH=/tmp/path \
  RUNNER_TEMP=/tmp/rt env -i PATH=/usr/local/bin:/usr/bin:/bin HOME="$HOME" \
  sh -c 'printf "%s|%s|%s|%s" "${GITHUB_ENV:-}" "${GITHUB_OUTPUT:-}" "${GITHUB_PATH:-}" "${RUNNER_TEMP:-}"')
[ "$seen" = "|||" ] || ko "env -i laisse fuiter un fichier de commande : [$seen]"
ok "env -i : GITHUB_ENV/GITHUB_OUTPUT/GITHUB_PATH/RUNNER_TEMP absents de l'enfant"
