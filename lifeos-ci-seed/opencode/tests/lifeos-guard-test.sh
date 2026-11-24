#!/usr/bin/env bash
# Tests du garde-fou lifeos_write (sans réseau, sans secret).
#   opencode/tests/lifeos-guard-test.sh
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
guard="$here/lifeos-guard.sh"
[ -x "$guard" ] || { echo "FAIL guard absent : $guard" >&2; exit 1; }

pass=0
refuse() {
  local label="$1"; shift
  if "$guard" "$@" >/dev/null 2>&1; then
    echo "FAIL attendu refus : $label" >&2
    exit 1
  fi
  pass=$((pass + 1))
}
accept() {
  local label="$1"; shift
  if ! "$guard" "$@" >/dev/null 2>&1; then
    echo "FAIL attendu acceptation : $label" >&2
    "$guard" "$@" || true
    exit 1
  fi
  pass=$((pass + 1))
}

# lifeos_write=false : toute destination lifeos est refusée, quelle que soit la forme.
refuse "false + https lifeos" destination false "https://github.com/LordThiouk/lifeos.git" feat/x
refuse "false + owner/repo" destination false "LordThiouk/lifeos" feat/x
refuse "false + casse différente" destination false "lordthiouk/LIFEOS" feat/x
refuse "false + .git" destination false "LordThiouk/lifeos.git" feat/x
refuse "false + ssh" destination false "git@github.com:LordThiouk/lifeos.git" feat/x

# false + autre dépôt : autorisé.
accept "false + antenly" destination false "LordThiouk/antenly" feat/x
accept "false + galass-ci" destination false "https://github.com/LordThiouk/galass-ci.git" feat/y

# true + lifeos sur branche de fonctionnalité : autorisé ; main/master refusés.
accept "true + lifeos feature" destination true "LordThiouk/lifeos" feat/lifeos
accept "true + lifeos https" destination true "https://github.com/LordThiouk/lifeos.git" feat/lifeos
refuse "true + lifeos main" destination true "LordThiouk/lifeos" main
refuse "true + lifeos master" destination true "LordThiouk/lifeos" master

# Tout dépôt + main/master/HEAD refusé.
refuse "antenly main" destination false "LordThiouk/antenly" main
refuse "antenly master" destination true "LordThiouk/antenly" master
refuse "antenly HEAD" destination false "LordThiouk/antenly" HEAD
refuse "refs/heads/main" destination false "LordThiouk/antenly" refs/heads/main

# target_repo=lifeos en écriture avec lifeos_write=false : refusé.
refuse "false + target lifeos" writes false lifeos ""
refuse "false + target LordThiouk/lifeos" writes false "LordThiouk/lifeos" ""
refuse "false + extra lifeos" writes false antenly "galass-ci,lifeos"
accept "false + extra sans lifeos" writes false antenly "galass-ci,Galass_Rider"
accept "true + target lifeos" writes true lifeos ""
accept "true + extra lifeos" writes true antenly "lifeos"

# Vérification lecture seule.
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/ro/sub"
printf 'x\n' > "$tmp/ro/sub/f"
chmod -R a-w "$tmp/ro"
accept "clone lifeos en lecture seule" readonly "$tmp/ro"
chmod u+w "$tmp/ro/sub/f"
refuse "clone lifeos modifiable" readonly "$tmp/ro"

echo "PASS lifeos-guard-test : $pass cas"
