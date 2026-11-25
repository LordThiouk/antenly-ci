#!/usr/bin/env bash
# C2 — aucun hook/filtre/config locale du dépôt de l'agent n'est exécuté avec
# CI_TOKEN : push depuis une copie nue, git isolé (hooksPath=/dev/null,
# fsmonitor=false, GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1,
# --no-verify). Sans réseau, sans secret : workflow + dépôts locaux.
#   opencode/tests/critical-git-isolation-test.sh
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
steps = y["jobs"]["run"]["steps"]
names = [s.get("name", "") for s in steps]

def step(needle):
    for s in steps:
        if needle in s.get("name", ""):
            return s
    raise AssertionError("step introuvable : %s" % needle)

push = step("Porte gitleaks")
txt = push.get("run", "")
for needle in (
    "core.hooksPath=/dev/null",
    "core.fsmonitor=false",
    "GIT_CONFIG_GLOBAL=/dev/null",
    "GIT_CONFIG_NOSYSTEM=1",
    "--no-verify",
    "env -i",
    "git init -q --bare",
    "protocol.file.allow",
    '"$TOOLS_DIR/opencode/gitleaks"',
):
    assert needle in txt, "push non isolé : %r absent" % needle
assert 'git -C "$dir" push' not in txt, "push direct depuis le dépôt de l'agent"
assert 'git -C lifeos push' not in txt, "push direct depuis lifeos de l'agent"
assert 'git -C "$dir" commit' not in txt, "commit direct dans le dépôt de l'agent"

env = push.get("env", {})
assert str(env.get("GIT_CONFIG_GLOBAL")) == "/dev/null", "GIT_CONFIG_GLOBAL du step push"
assert str(env.get("GIT_CONFIG_NOSYSTEM")) == "1", "GIT_CONFIG_NOSYSTEM du step push"

prompt = step("Préparer le prompt")
assert "core.hooksPath=/dev/null" in prompt.get("run", ""), "fetch du prompt sans hooks neutralisés"
assert "core.fsmonitor=false" in prompt.get("run", ""), "fetch du prompt sans fsmonitor neutralisé"

raw = open(sys.argv[1]).read()
assert raw.count("core.hooksPath=/dev/null") >= 3, "isolation hooks insuffisamment généralisée"
assert raw.count("core.fsmonitor=false") >= 3, "isolation fsmonitor insuffisamment généralisée"
assert '>> "$GITHUB_ENV"' not in raw, "GITHUB_ENV encore utilisé"
print("OK   workflow : push isolé depuis une copie nue, hooks/config neutralisés")
PY

# Preuve fonctionnelle : un hook pre-push et un include.path malveillants ne
# s'exécutent pas avec l'isolation utilisée par le workflow.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
remote="$tmp/remote.git"
work="$tmp/work"
home="$tmp/home"
sentinel="$tmp/hook-ran"
mkdir -p "$home"
git init -q --bare "$remote"
git init -q -b feat/x "$work"
git -C "$work" config user.name Test
git -C "$work" config user.email test@example.invalid
printf 'base\n' > "$work/README.md"
git -C "$work" add README.md
git -C "$work" commit -qm base
git -C "$work" remote add origin "file://$remote"
cat > "$work/.git/hooks/pre-push" <<EOF
#!/bin/sh
: > "$sentinel"
exit 1
EOF
chmod +x "$work/.git/hooks/pre-push"
cat > "$tmp/evil.cfg" <<EOF
[core]
  hooksPath = $work/.git/hooks
[alias]
  push = !: > "$tmp/alias-ran"
EOF
git -C "$work" config include.path "$tmp/evil.cfg"

git_iso() {
  env -i PATH=/usr/local/bin:/usr/bin:/bin HOME="$home" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
    GIT_CONFIG_COUNT=2 \
    GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
    GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null \
    git -c core.fsmonitor=false -C "$work" "$@"
}

git_iso push --no-verify origin HEAD:refs/heads/feat/x >/dev/null 2>&1 \
  || ko "push isolé refusé"
[ "$(git -C "$remote" rev-parse refs/heads/feat/x)" = "$(git -C "$work" rev-parse HEAD)" ] \
  || ko "le commit n'est pas arrivé sur le distant"
[ ! -e "$sentinel" ] || ko "le hook pre-push de l'agent s'est exécuté malgré l'isolation"
[ ! -e "$tmp/alias-ran" ] || ko "un alias local s'est exécuté"
ok "isolation : hook pre-push et include.path locaux neutralisés"

# Contrôle négatif : sans hooksPath=/dev/null, le même hook s'exécute et bloque.
printf 'suite\n' > "$work/b.txt"
git -C "$work" add b.txt
git -C "$work" commit -qm suite
rm -f "$sentinel"
if git -C "$work" -c core.hooksPath="$work/.git/hooks" \
     push origin HEAD:refs/heads/feat/x >/dev/null 2>&1; then
  ko "contrôle négatif : le hook aurait dû bloquer le push"
fi
[ -e "$sentinel" ] || ko "contrôle négatif : le hook n'a pas été exécuté"
ok "contrôle négatif : le hook bloque bien sans hooksPath=/dev/null"
