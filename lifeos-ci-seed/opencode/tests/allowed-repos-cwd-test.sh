#!/usr/bin/env bash
# Les étapes de push et de PR sourcent allowed-repos.sh depuis le checkout
# galass-ci (copie figée à côté des scripts), pas depuis le répertoire courant.
# Ce test exécute parse / push / pr depuis un autre répertoire.
#   opencode/tests/allowed-repos-cwd-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(cd "$here/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"

yml="$root/.github/workflows/opencode-fullrun.yml"
[ -f "$yml" ] || ko "opencode-fullrun.yml absent"
[ -f "$here/allowed-repos.sh" ] || ko "allowed-repos.sh absent"
[ -x "$here/extra-repos.sh" ] || ko "extra-repos.sh absent"

# Le workflow copie allowed-repos.sh dans /opt/fullrun-tools depuis le checkout ci.
grep -q 'opencode/allowed-repos.sh' "$yml" || ko "allowed-repos.sh non mentionné dans le workflow"
grep -q '/opt/fullrun-tools' "$yml" && grep -q 'allowed-repos.sh' "$yml" \
  || ko "allowed-repos.sh n'est pas installé dans /opt/fullrun-tools"
# Après opencode, push et PR sourcent la copie figée, pas un chemin relatif au cwd.
# On accepte $T/allowed-repos.sh (T=/opt/fullrun-tools).
rel=$(grep -n '\. .*allowed-repos\.sh' "$yml" | grep -v 'shellcheck source' || true)
bad=$(printf '%s\n' "$rel" | grep -E '\. ["'\'']?(\./)?opencode/allowed-repos|\. ["'\'']?\$CI_DIR/opencode/allowed-repos' || true)
# Les sourcings post-opencode doivent être $T/allowed-repos.sh
n_t=$(grep -c '\. "$T/allowed-repos.sh"' "$yml" || true)
[ "$n_t" -ge 2 ] || ko "les étapes push et PR doivent sourcer \"\$T/allowed-repos.sh\" (trouvé=$n_t)"
[ -z "$bad" ] || ko "sourcing encore relatif au cwd ou via CI_DIR après opencode :
$bad"
ok "workflow : allowed-repos.sh figé dans /opt/fullrun-tools, sourcé via \$T (pas le cwd)"

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# Simule /opt/fullrun-tools : scripts + liste blanche, rien dans le cwd de travail.
tools="$tmp/fullrun-tools"
mkdir -p "$tools" "$tmp/cwd" "$tmp/state" "$tmp/root" "$tmp/src"
cp "$here/allowed-repos.sh" "$here/extra-repos.sh" "$tools/"
chmod 0755 "$tools/extra-repos.sh"
chmod 0644 "$tools/allowed-repos.sh"

# parse depuis un cwd qui n'a pas opencode/allowed-repos.sh
out=$(cd "$tmp/cwd" && TARGET_REPO=Galass_backend EXTRA_REPOS_RAW="Galass_Driver,Galass_Rider" \
  "$tools/extra-repos.sh" parse 2>"$tmp/err") || ko "parse depuis un autre cwd a échoué : $(cat "$tmp/err")"
[ "$out" = "Galass_Driver,Galass_Rider" ] || ko "parse inattendu : [$out]"
[ ! -e "$tmp/cwd/allowed-repos.sh" ] || ko "le test a pollué le cwd"
ok "parse depuis un autre répertoire : $out"

# Sans allowed-repos.sh à côté du script : échec franc, même depuis un cwd
# qui contient allowed-repos.sh (on ne source jamais le répertoire courant).
mkdir -p "$tmp/orphan"
cp "$here/extra-repos.sh" "$tmp/orphan/"
chmod 0755 "$tmp/orphan/extra-repos.sh"
if cd "$here" && TARGET_REPO=Galass_backend EXTRA_REPOS_RAW=Galass_Driver      "$tmp/orphan/extra-repos.sh" parse >/dev/null 2>"$tmp/err"; then
  ko "extra-repos.sh sans allowed-repos.sh à côté aurait dû échouer"
fi
grep -qi 'allowed-repos.sh introuvable' "$tmp/err"   || ko "absence mal signalée : $(cat "$tmp/err")"
ok "sans allowed-repos.sh à côté du script : échec franc"

# Push et PR depuis un autre cwd, avec la même mécanique que les étapes CI
# (copie figée + extra-repos.sh). Dépôts factices file://, pas de réseau.
if ! command -v gitleaks >/dev/null 2>&1; then
  ok "gitleaks absent : push/PR réels sautés, parse depuis un autre cwd déjà prouvé"
  echo "PASS allowed-repos-cwd : sourcing figé, parse hors cwd"
  exit 0
fi

fake_token=$(fake_ghp)
bare="$tmp/src/Galass_Driver.git"
seed="$tmp/seed"
git init -q --bare "$bare"
git init -q "$seed"
git -C "$seed" config user.name T
git -C "$seed" config user.email t@t
echo base > "$seed/README"
git -C "$seed" add README
git -C "$seed" commit -q -m init
git -C "$seed" branch -M main
git -C "$seed" checkout -q -b feat/ms
echo feat > "$seed/feat"
git -C "$seed" add feat
git -C "$seed" commit -q -m 'wip: feat'
git -C "$seed" push -q "$bare" "HEAD:refs/heads/feat/ms"
git -C "$seed" checkout -q main
git -C "$seed" push -q "$bare" "HEAD:refs/heads/main"

# checkout, comme l'étape CI, depuis un autre répertoire
out=$(cd "$tmp/cwd" && EXTRA_SRC_DIR="$tmp/src" EXTRA_STATE="$tmp/state" \
  EXTRA_ROOT="$tmp/root" EXTRA_REPOS=Galass_Driver TARGET_REPO=Galass_backend \
  IN_BRANCH=feat/ms "$tools/extra-repos.sh" checkout 2>"$tmp/err") \
  || ko "checkout depuis un autre cwd a échoué : $(cat "$tmp/err") $out"
[ -d "$tmp/root/Galass_Driver/.git" ] || ko "checkout absent"
[ -s "$tmp/state/Galass_Driver.base" ] || ko "SHA de départ non enregistré"
ok "checkout depuis un autre répertoire"

# Travail ensuite commité (comme pendant le run)
git -C "$tmp/root/Galass_Driver" config user.name T
git -C "$tmp/root/Galass_Driver" config user.email t@t
echo work > "$tmp/root/Galass_Driver/y"
git -C "$tmp/root/Galass_Driver" add y
git -C "$tmp/root/Galass_Driver" commit -q -m 'wip: y'

run_from_cwd() {
  local cmd="$1"
  cd "$tmp/cwd" || return 1
  EXTRA_TOKEN_STDIN=1 EXTRA_GITLEAKS="$(command -v gitleaks)" \
    EXTRA_ISA_KEY_FILE="$tmp/empty.key" EXTRA_STATE="$tmp/state" \
    EXTRA_WORK="$tmp/work" EXTRA_SRC_DIR="$tmp/src" \
    IN_BRANCH=feat/ms EXTRA_ROOT="$tmp/root" EXTRA_REPOS=Galass_Driver \
    TARGET_REPO=Galass_backend "$tools/extra-repos.sh" "$cmd"
}
: > "$tmp/empty.key"

out=$(run_from_cwd check 2>"$tmp/err") || ko "check depuis un autre cwd a échoué : $(cat "$tmp/err") $out"
out=$(run_from_cwd push 2>"$tmp/err" <<< "$fake_token") || ko "push depuis un autre cwd a échoué : $(cat "$tmp/err") $out"
echo "$out" | grep -q 'Push OK : Galass_Driver@feat/ms' || ko "ligne Push OK absente : $out"
ok "push depuis un autre répertoire"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'S'
#!/usr/bin/env bash
case "$*" in
  *"pr list"*) echo 0; exit 0 ;;
  *"pr create"*) echo "https://github.com/LordThiouk/Galass_Driver/pull/0"; exit 0 ;;
  *merge*) echo "merge interdit dans le test" >&2; exit 1 ;;
  *) exit 0 ;;
esac
S
chmod 0755 "$tmp/bin/gh"
out=$(cd "$tmp/cwd" && PATH="$tmp/bin:$PATH" EXTRA_TOKEN_STDIN=1 \
  EXTRA_STATE="$tmp/state" IN_BRANCH=feat/ms IN_BASE=main IN_JOB=t \
  EXTRA_ROOT="$tmp/root" EXTRA_REPOS=Galass_Driver TARGET_REPO=Galass_backend \
  "$tools/extra-repos.sh" pr 2>"$tmp/err" <<< "$fake_token") \
  || ko "PR depuis un autre cwd a échoué : $(cat "$tmp/err") $out"
echo "$out" | grep -q 'PR en brouillon' || ko "ligne PR absente : $out"
echo "$out" | grep -qi merge && ko "tentative de fusion dans la PR"
ok "PR depuis un autre répertoire"

# Étape cible (push/PR) : sourcer $T/allowed-repos.sh depuis un cwd étranger
cd "$tmp/cwd"
T="$tools"
# shellcheck source=opencode/allowed-repos.sh
. "$T/allowed-repos.sh"
allowed_repo Galass_backend || ko "allowed_repo Galass_backend a échoué hors cwd"
allowed_repo not-a-repo && ko "allowed_repo a accepté un dépôt hors liste"
ok "étapes push/PR cible : source \$T/allowed-repos.sh depuis un autre répertoire"

echo "PASS allowed-repos-cwd : push et PR fonctionnent hors du checkout"
