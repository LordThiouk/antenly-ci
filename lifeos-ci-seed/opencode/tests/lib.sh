# shellcheck shell=bash
# Outils communs aux tests locaux (sourcé). gitleaks : binaire du PATH, sinon version épinglée
# téléchargée et vérifiée (sha256), comme dans le workflow.
ok() { printf 'OK   %s\n' "$*"; }
ko() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
# Faux jetons générés à l'exécution : jamais de valeur fixe dans le dépôt. Les clés AWS
# « EXAMPLE » de la doc sont sur la liste blanche de gitleaks : inutilisables ici.
rand_alnum() { head -c 256 /dev/urandom | base64 -w0 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
fake_ghp() { printf 'ghp_%s' "$(rand_alnum 36)"; }
fake_glpat() { printf 'glpat-%s' "$(rand_alnum 20)"; }
find_gitleaks() {
  local v="${GITLEAKS_VERSION:-8.30.1}" sum="${GITLEAKS_SHA256:-551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb}" d="$1"
  if command -v gitleaks >/dev/null 2>&1; then command -v gitleaks; return; fi
  curl -sSfL -o "$d/gitleaks.tgz" \
    "https://github.com/gitleaks/gitleaks/releases/download/v${v}/gitleaks_${v}_linux_x64.tar.gz" || return 1
  echo "${sum}  $d/gitleaks.tgz" | sha256sum -c --quiet >/dev/null || return 1
  tar -xzf "$d/gitleaks.tgz" -C "$d" gitleaks && printf '%s\n' "$d/gitleaks"
}
