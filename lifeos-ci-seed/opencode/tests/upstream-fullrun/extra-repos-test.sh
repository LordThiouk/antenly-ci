#!/usr/bin/env bash
# Test local de extra-repos.sh (parse, checkout, contrôles, push, PR brouillon) contre des
# dépôts nus file://, sans réseau réel : liste validée, checkout sur la branche de
# fonctionnalité (créée depuis la branche par défaut si absente), gitleaks et clé ISA
# bloquent le push, non-fast-forward refusé (jamais de force), main refusée, jeton jamais
# dans les arguments ni la sortie, PR en brouillon uniquement (jamais fusionnée).
#   opencode/tests/extra-repos-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
gl=$(find_gitleaks "$tmp") || ko "gitleaks introuvable"
script="$here/extra-repos.sh"
src="$tmp/src"; mkdir -p "$src"
root="$tmp/extra"
state="$tmp/state"
work="$tmp/work"
fake_token="TESTEXTRATOKEN$(rand_alnum 24)"
out="$tmp/out.txt"

mkrepo() {
  local name="$1" branch="${2:-main}"
  local bare="$src/$name.git" seed="$tmp/seed-$name"
  git init -q --bare "$bare"
  git init -q -b "$branch" "$seed"
  git -C "$seed" config user.name Test
  git -C "$seed" config user.email test@example.invalid
  printf 'depart %s\n' "$name" > "$seed/README.md"
  git -C "$seed" add README.md && git -C "$seed" commit -qm "base $name"
  git -C "$seed" push -q "$bare" "HEAD:refs/heads/$branch"
  git -C "$bare" symbolic-ref HEAD "refs/heads/$branch"
}

run_parse() {
  EXTRA_REPOS_RAW="$1" TARGET_REPO="${2:-Galass_backend}" "$script" parse > "$out" 2>"$tmp/err.txt"
}

run_chk() {
  EXTRA_REPOS="$1" TARGET_REPO=Galass_backend IN_BRANCH=feat/ms \
    EXTRA_ROOT="$root" EXTRA_STATE="$state" EXTRA_SRC_DIR="$src" \
    EXTRA_WORK="$work" EXTRA_GITLEAKS="$gl" EXTRA_ISA_KEY_FILE="${EXTRA_ISA_KEY_FILE:-}" \
    "$script" "$2" > "$out" 2>"$tmp/err.txt"
}

# --- 1. parse : liste vide, normalisation, refus --------------------------------
run_parse "" && [ -z "$(cat "$out")" ] || ko "liste vide devrait produire une chaîne vide"
ok "parse : liste vide"

run_parse " Galass_Driver , Galass_Rider " || ko "liste valide refusée : $(cat "$tmp/err.txt")"
[ "$(cat "$out")" = "Galass_Driver,Galass_Rider" ] || ko "normalisation inattendue : $(cat "$out")"
ok "parse : espaces retirés, ordre conservé"

run_parse "Galass_backend" "Galass_backend" && ko "target_repo répété accepté"
grep -q 'répéter target_repo' "$tmp/err.txt" || ko "message de répétition absent"
ok "parse : target_repo répété refusé"

run_parse "Galass_Driver,Galass_Driver" && ko "doublon accepté"
grep -q 'double' "$tmp/err.txt" || ko "message de doublon absent"
ok "parse : doublon refusé"

for bad in lifeos antenly-ci evil 'Galass_backend;rm' '../x' ''; do
  [ -n "$bad" ] || continue
  run_parse "$bad" && ko "dépôt non autorisé accepté : $bad"
done
run_parse "lifeos,Galass_Driver" && ko "lifeos accepté dans la liste"
ok "parse : lifeos, antenly-ci et noms hors liste refusés"

run_parse "galass-emu-actions-pub,Galass_Rider" "Galass_backend" || ko "liste avec emu refusée"
[ "$(cat "$out")" = "galass-emu-actions-pub,Galass_Rider" ] || ko "emu absente de la liste normalisée"
ok "parse : galass-emu-actions-pub accepté"

# --- 2. checkout : branche existante, branche créée, hook, pas d'identifiants ---
mkrepo Galass_Driver main
mkrepo Galass_Rider main
# Branche déjà présente sur Driver seulement.
dseed="$tmp/seed-Galass_Driver"
git -C "$dseed" checkout -q -b feat/ms
printf 'deja\n' > "$dseed/pre.txt"
git -C "$dseed" add pre.txt && git -C "$dseed" commit -qm "feat start"
git -C "$dseed" push -q "$src/Galass_Driver.git" "HEAD:refs/heads/feat/ms"
rm -rf "$root" "$state"
run_chk "Galass_Driver,Galass_Rider" checkout || ko "checkout en échec : $(cat "$tmp/err.txt") $(cat "$out")"
[ -d "$root/Galass_Driver/.git" ] && [ -d "$root/Galass_Rider/.git" ] || ko "dossiers de checkout absents"
[ "$(git -C "$root/Galass_Driver" rev-parse --abbrev-ref HEAD)" = feat/ms ] || ko "Driver pas sur feat/ms"
[ "$(git -C "$root/Galass_Rider" rev-parse --abbrev-ref HEAD)" = feat/ms ] || ko "Rider pas sur feat/ms"
[ -f "$root/Galass_Driver/pre.txt" ] || ko "Driver n'a pas pris la branche existante"
[ ! -f "$root/Galass_Rider/pre.txt" ] || ko "Rider aurait dû partir de main"
[ -x "$root/Galass_Driver/.git/hooks/pre-push" ] || ko "hook pre-push absent"
git -C "$root/Galass_Driver" push 2>"$tmp/hook.txt" && ko "hook pre-push n'a pas bloqué"
grep -q 'push interdit' "$tmp/hook.txt" || ko "message du hook inattendu"
git -C "$root/Galass_Driver" remote get-url origin | grep -q '^file://' || ko "remote n'est pas file://"
git -C "$root/Galass_Driver" remote get-url origin | grep -q '@' && ko "identifiants dans l'URL du remote"
[ -s "$state/Galass_Driver.base" ] && [ -s "$state/Galass_Rider.base" ] || ko "SHA de départ non enregistré"
ok "checkout : branche existante, branche créée depuis main, hook, URL nue"

# --- 3. check + push : cas propre ----------------------------------------------
printf 'travail\n' > "$root/Galass_Driver/a.txt"
git -C "$root/Galass_Driver" add a.txt
git -C "$root/Galass_Driver" commit -qm "wip: a"
run_chk "Galass_Driver,Galass_Rider" check || ko "check propre en échec : $(cat "$tmp/err.txt") $(cat "$out")"
grep -q 'modifié, contrôles OK' "$out" || ko "Driver non signalé modifié"
grep -q 'inchangé' "$out" || ko "Rider non signalé inchangé"
[ "$(cat "$state/Galass_Driver.modified")" = yes ] || ko "état modified Driver"
[ "$(cat "$state/Galass_Rider.modified")" = no ] || ko "état modified Rider"
run_chk "Galass_Driver,Galass_Rider" push || ko "push propre en échec : $(cat "$tmp/err.txt") $(cat "$out")"
h1=$(git -C "$root/Galass_Driver" rev-parse HEAD)
[ "$(git -C "$src/Galass_Driver.git" rev-parse refs/heads/feat/ms)" = "$h1" ] || ko "Driver non poussé"
git -C "$src/Galass_Rider.git" rev-parse -q --verify refs/heads/feat/ms >/dev/null && ko "Rider inchangé a été poussé"
grep -q "Push OK : Galass_Driver@feat/ms" "$out" || ko "ligne de push absente"
ok "check+push : Driver poussé, Rider inchangé non poussé"

# --- 4. secret factice ghp_ : check refuse, rien de poussé --------------------
h_before=$(git -C "$src/Galass_Driver.git" rev-parse refs/heads/feat/ms)
sec=$(fake_ghp)
printf 'export GITHUB_TOKEN=%s\n' "$sec" > "$root/Galass_Driver/secret.txt"
git -C "$root/Galass_Driver" add secret.txt
git -C "$root/Galass_Driver" commit -qm "wip: config"
run_chk "Galass_Driver" check && ko "secret accepté par le check"
grep -q 'secret probable' "$tmp/err.txt" || ko "blocage gitleaks non signalé : $(cat "$tmp/err.txt")"
grep -rqaF -- "$sec" "$out" "$tmp/err.txt" "$state" && ko "valeur du secret dans la sortie"
# L'état check n'est pas ok : le push doit refuser et ne rien envoyer.
run_chk "Galass_Driver" push && ko "push accepté après échec du check"
[ "$(git -C "$src/Galass_Driver.git" rev-parse refs/heads/feat/ms)" = "$h_before" ] || ko "secret poussé malgré le blocage"
git -C "$root/Galass_Driver" reset -q --hard "$h_before"
# Réécrire l'état propre pour la suite.
printf '%s\n' "$h_before" > "$state/Galass_Driver.head"
printf '%s\n' yes > "$state/Galass_Driver.modified"
printf '%s\n' ok > "$state/Galass_Driver.check"
ok "secret ghp_ : check refusé, non poussé, valeur absente"

# --- 5. clé ISA bloquée --------------------------------------------------------
key=$(rand_alnum 64)
printf '%s' "$key" > "$tmp/isa.key"; chmod 600 "$tmp/isa.key"
printf 'empreinte %s\n' "$key" > "$root/Galass_Driver/isa.txt"
git -C "$root/Galass_Driver" add isa.txt
git -C "$root/Galass_Driver" commit -qm "wip: empreinte"
EXTRA_ISA_KEY_FILE="$tmp/isa.key" run_chk "Galass_Driver" check && ko "clé ISA acceptée"
grep -q 'clé ISA' "$tmp/err.txt" || ko "blocage clé ISA non signalé : $(cat "$tmp/err.txt")"
grep -rqaF -- "$key" "$out" "$tmp/err.txt" "$state" && ko "clé ISA dans la sortie"
git -C "$root/Galass_Driver" reset -q --hard "$h_before"
printf '%s\n' "$h_before" > "$state/Galass_Driver.head"
printf '%s\n' ok > "$state/Galass_Driver.check"
ok "clé ISA : non poussée, jamais affichée"

# --- 6. modification de .github/workflows/ refusée -----------------------------
mkdir -p "$root/Galass_Driver/.github/workflows"
printf 'name: x\n' > "$root/Galass_Driver/.github/workflows/evil.yml"
git -C "$root/Galass_Driver" add .github/workflows/evil.yml
git -C "$root/Galass_Driver" commit -qm "wip: workflow"
run_chk "Galass_Driver" check && ko "changement de workflow accepté"
grep -q 'workflows' "$tmp/err.txt" || ko "blocage workflows non signalé : $(cat "$tmp/err.txt")"
git -C "$root/Galass_Driver" reset -q --hard "$h_before"
printf '%s\n' "$h_before" > "$state/Galass_Driver.head"
printf '%s\n' ok > "$state/Galass_Driver.check"
ok "modification de .github/workflows refusée"

# --- 7. non-fast-forward : jamais de force ------------------------------------
printf 'nouveau\n' > "$root/Galass_Driver/n.txt"
git -C "$root/Galass_Driver" add n.txt
git -C "$root/Galass_Driver" commit -qm "wip: n"
run_chk "Galass_Driver" check || ko "check avant non-ff en échec : $(cat "$tmp/err.txt")"
# Avancer le distant ailleurs, sans force côté script.
other="$tmp/other-driver"
git clone -q -b feat/ms "file://$src/Galass_Driver.git" "$other"
git -C "$other" config user.name Test; git -C "$other" config user.email test@example.invalid
printf 'ailleurs\n' > "$other/x.txt"
git -C "$other" add x.txt && git -C "$other" commit -qm "ailleurs"
git -C "$other" push -q "file://$src/Galass_Driver.git" "HEAD:refs/heads/feat/ms"
distant=$(git -C "$src/Galass_Driver.git" rev-parse refs/heads/feat/ms)
run_chk "Galass_Driver" push && ko "non-fast-forward accepté (force ?)"
grep -q 'rien n.a été forcé\|push refusé' "$tmp/err.txt" || ko "refus non-ff non signalé : $(cat "$tmp/err.txt")"
[ "$(git -C "$src/Galass_Driver.git" rev-parse refs/heads/feat/ms)" = "$distant" ] || ko "le distant a bougé (force)"
ok "non-fast-forward : refusé, distant intact (aucun force)"

# --- 8. main et branches interdites refusées à l'entrée -----------------------
for b in main master refs/heads/x fullrun-logs/test fullrun-prompts; do
  IN_BRANCH="$b" EXTRA_REPOS=Galass_Rider TARGET_REPO=Galass_backend \
    EXTRA_ROOT="$root" EXTRA_STATE="$state" EXTRA_SRC_DIR="$src" \
    "$script" checkout > "$out" 2>"$tmp/err.txt" && ko "branche interdite acceptée : $b"
done
ok "branches main/master/refs/fullrun-logs/fullrun-prompts refusées"

# --- 9. remote https simulé : jeton par l'environnement, jamais en argument ---
printf 'https\n' > "$root/Galass_Rider/d.txt"
git -C "$root/Galass_Rider" add d.txt
git -C "$root/Galass_Rider" commit -qm "wip: d"
EXTRA_ISA_KEY_FILE="" run_chk "Galass_Rider" check || ko "check Rider https en échec : $(cat "$tmp/err.txt") $(cat "$out")"
shim="$tmp/shim"; mkdir -p "$shim"; realgit=$(command -v git)
cat > "$shim/git" <<SHIM
#!/usr/bin/env bash
# Intercepte push (avec ou sans -C) ; le reste est délégué au vrai git.
for a in "\$@"; do
  if [ "\$a" = push ]; then
    printf '%s\n' "\$*" > "$tmp/push.argv"
    printf '%s' "\${GIT_CONFIG_KEY_1:-} \${GIT_CONFIG_VALUE_1:-}" > "$tmp/push.hdr"
    exit 0
  fi
done
exec "$realgit" "\$@"
SHIM
chmod +x "$shim/git"
# EXTRA_SRC_DIR vide -> URL https officielle + run_git auth. EXTRA_GIT intercepte le push.
EXTRA_REPOS=Galass_Rider TARGET_REPO=Galass_backend IN_BRANCH=feat/ms \
  EXTRA_ROOT="$root" EXTRA_STATE="$state" EXTRA_WORK="$work" \
  EXTRA_GIT="$shim/git" EXTRA_TOKEN_STDIN=1 \
  "$script" push > "$out" 2>"$tmp/err.txt" <<< "$fake_token" || ko "push https simulé en échec : $(cat "$tmp/err.txt") $(cat "$out")"
grep -q 'Push OK : Galass_Rider@feat/ms' "$out" || ko "push https non signalé : $(cat "$out")"
grep -qF -- "$fake_token" "$tmp/push.argv" && ko "jeton dans les arguments de git"
grep -q 'https://github.com/LordThiouk/Galass_Rider.git' "$tmp/push.argv" || ko "URL inattendue : $(cat "$tmp/push.argv")"
grep -q '@github.com' "$tmp/push.argv" && ko "identifiants dans l'URL"
want="http.https://github.com/.extraheader AUTHORIZATION: basic $(printf 'x-access-token:%s' "$fake_token" | base64 -w0)"
[ "$(cat "$tmp/push.hdr")" = "$want" ] || ko "en-tête d'authentification absent ou inattendu : [$(cat "$tmp/push.hdr")]"
# Le push a été simulé : le distant file:// n'a pas avancé, on ne marque pas pushed pour Rider ici
# (la PR du test 10 pose pushed=yes elle-même). On retire un pushed=yes accidentel.
rm -f "$state/Galass_Rider.pushed"
ok "remote https : jeton passé à git par son environnement seul (ni argument, ni URL)"

# --- 10. PR brouillon, jamais fusionnée, pas de PR si non poussé --------------
ghshim="$tmp/ghshim"; mkdir -p "$ghshim"
cat > "$ghshim/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$(dirname "$0")/../gh.argv"
case "$1 $2" in
  "pr list") echo 0; exit 0 ;;
  "pr create")
    printf '%s\n' "$@" > "$(dirname "$0")/../gh.create"
    echo "https://github.com/LordThiouk/Galass_Rider/pull/1"
    exit 0
    ;;
  "pr merge"|merge) echo "merge interdit dans le test" >&2; exit 1 ;;
  *) echo "gh unexpected: $*" >&2; exit 1 ;;
esac
GH
chmod +x "$ghshim/gh"
# Rider a été check'é mais on marque pushed=yes pour la PR (le push https n'a pas eu lieu).
printf 'yes\n' > "$state/Galass_Rider.pushed"
IN_JOB=testjob IN_BRANCH=feat/ms EXTRA_REPOS=Galass_Rider TARGET_REPO=Galass_backend \
  EXTRA_ROOT="$root" EXTRA_STATE="$state" EXTRA_SRC_DIR="$src" EXTRA_GH="$ghshim/gh" \
  EXTRA_PR_BASE=main EXTRA_TOKEN_STDIN=1 \
  "$script" pr > "$out" 2>"$tmp/err.txt" <<< "$fake_token" || ko "PR en échec : $(cat "$tmp/err.txt") $(cat "$out")"
grep -q 'PR en brouillon : https://github.com/LordThiouk/Galass_Rider/pull/1' "$out" || ko "URL de PR absente : $(cat "$out")"
grep -q -- '--draft' "$tmp/gh.create" || ko "flag --draft absent"
grep -q 'pr merge\|--merge' "$tmp/gh.create" "$tmp/gh.argv" && ko "tentative de fusion"
grep -qF -- "$fake_token" "$tmp/gh.create" "$tmp/gh.argv" "$out" && ko "jeton passé à gh en argument"
# Dépôt non poussé : pas de PR (on retire l'état pushed laissé par le 1er push propre).
rm -f "$state/Galass_Driver.pushed"
IN_JOB=testjob IN_BRANCH=feat/ms EXTRA_REPOS=Galass_Driver TARGET_REPO=Galass_backend \
  EXTRA_ROOT="$root" EXTRA_STATE="$state" EXTRA_SRC_DIR="$src" EXTRA_GH="$ghshim/gh" \
  "$script" pr > "$out" 2>"$tmp/err.txt" || ko "PR Driver inattendu en échec"
grep -q 'pas poussé, pas de PR' "$out" || ko "PR ouverte pour un dépôt non poussé : $(cat "$out")"
ok "PR : brouillon uniquement, jamais fusionnée, ignorée si non poussé"

# --- 11. checkout refuse un dépôt hors liste ----------------------------------
IN_BRANCH=feat/ms EXTRA_REPOS=lifeos TARGET_REPO=Galass_backend \
  EXTRA_ROOT="$root" EXTRA_STATE="$state" EXTRA_SRC_DIR="$src" \
  "$script" checkout > "$out" 2>"$tmp/err.txt" && ko "checkout lifeos accepté"
ok "checkout : dépôt hors liste refusé"

# --- 12. le jeton n'apparaît nulle part ---------------------------------------
# Recréer un passage avec jeton sur stdin (checkout réseau non fait ; push file:// n'en lit pas).
# On relance pr (déjà fait) et on cherche dans tout $tmp sauf le fichier où on l'a écrit nous-mêmes.
find "$tmp" -type f ! -name 'out-token.txt' -print0 | xargs -0 grep -qaF -- "$fake_token" \
  && ko "jeton retrouvé dans la sortie, l'état ou un dépôt"
# Le here-string de pr est dans le journal de test ? On a passé le jeton sur stdin, pas écrit dans un fichier.
# xargs grep sur $tmp ne devrait rien trouver. Si le ko se déclenche, c'est une fuite.
ok "jeton absent des sorties, de l'état et des dépôts"

# --- 13. clone et fetch authentifiés ; masque base64 sur stdout ---------------
# Faux git en tête du PATH : toute commande clone/fetch/pull sans en-tête d'auth échoue.
# Les URL https://github.com/LordThiouk/<repo>.git sont réécrites vers le dépôt nu local.
mkrepo Galass_backend main
bseed="$tmp/seed-Galass_backend"
git -C "$bseed" checkout -q -b feat/ms
printf 'auth\n' > "$bseed/auth.txt"
git -C "$bseed" add auth.txt && git -C "$bseed" commit -qm "feat start"
git -C "$bseed" push -q "$src/Galass_backend.git" "HEAD:refs/heads/feat/ms"

fakebin="$tmp/fakebin"; mkdir -p "$fakebin"
authlog="$tmp/fake-git.log"; : > "$authlog"
# Chemins injectés après coup : run_git auth lance git via env -i (plus de variables du test).
cat > "$fakebin/git" <<'FG'
#!/usr/bin/env bash
log="__LOG__"
src_root="__SRC__"
real=/usr/bin/git
auth=0
i=0
while [ "$i" -lt "${GIT_CONFIG_COUNT:-0}" ]; do
  eval "k=\${GIT_CONFIG_KEY_$i-}"
  eval "v=\${GIT_CONFIG_VALUE_$i-}"
  case "$k" in
    http.*.extraheader)
      case "$v" in
        AUTHORIZATION:\ basic\ *) auth=1 ;;
      esac
      ;;
  esac
  i=$((i + 1))
done
is_net=0
skip=0
args=()
for a in "$@"; do
  if [ "$skip" = 1 ]; then skip=0; args+=("$a"); continue; fi
  case "$a" in
    -C|--git-dir|--work-tree|--namespace) skip=1; args+=("$a"); continue ;;
    clone|fetch|pull|push|ls-remote) is_net=1 ;;
  esac
  # Réécriture seulement pour les commandes réseau : un set-url https doit rester nu.
  if [ "$is_net" = 1 ]; then
    case "$a" in
      https://github.com/LordThiouk/*.git|https://github.com/LordThiouk/*)
        repo=${a##*/}; repo=${repo%.git}
        a="file://${src_root}/${repo}.git"
        ;;
    esac
  fi
  args+=("$a")
done
printf '%s %s\n' "$auth" "${args[*]}" >> "$log"
if [ "$is_net" = 1 ] && [ "$auth" != 1 ]; then
  echo UNAUTH >> "$log"
  echo "fetch/clone/pull sans en-tête d'authentification" >&2
  exit 1
fi
# fetch/pull origin lit l'URL dans la config (https nue) : insteadOf la redirige en file://.
exec "$real" -c "url.file://${src_root}/.insteadOf=https://github.com/LordThiouk/" "${args[@]}"
FG
# shellcheck disable=SC2016
sed -i "s|__LOG__|$authlog|g; s|__SRC__|$src|g" "$fakebin/git"
chmod +x "$fakebin/git"
authroot="$tmp/auth-root"; authstate="$tmp/auth-state"
# Jeton seulement sur stdin, pas dans un fichier du $tmp (le test 12 a déjà scanné).
GITHUB_ACTIONS=1 PATH="$fakebin:$PATH" EXTRA_GIT="$fakebin/git" EXTRA_TOKEN_STDIN=1 \
  IN_BRANCH=feat/ms EXTRA_REPOS=Galass_backend TARGET_REPO=Galass_Driver \
  EXTRA_ROOT="$authroot" EXTRA_STATE="$authstate" \
  "$script" checkout > "$out" 2>"$tmp/err.txt" <<< "$fake_token" \
  || ko "checkout authentifié en échec : $(cat "$tmp/err.txt") $(cat "$out")"
[ -f "$authroot/Galass_backend/auth.txt" ] || ko "checkout authentifié incomplet"
grep -qE '(^| )clone ' "$authlog" || ko "clone absent du journal du faux git"
grep -qE '(^| )fetch ' "$authlog" || ko "fetch absent du journal du faux git"
# Chaque clone/fetch/pull doit avoir été authentifié (premier champ = 1).
while read -r flag rest; do
  [ "$flag" = UNAUTH ] && ko "clone/fetch/pull sans auth : $rest"
  case " $rest " in
    *" clone "*|*" fetch "*|*" pull "*)
      [ "$flag" = 1 ] || ko "commande réseau sans auth : $flag $rest"
      ;;
  esac
done < "$authlog"
grep -q '^UNAUTH' "$authlog" && ko "UNAUTH dans le journal du faux git"
b64=$(printf 'x-access-token:%s' "$fake_token" | base64 -w0)
grep -qF -- "::add-mask::$b64" "$out" || ko "masque base64 absent de stdout (add-mask non enregistré) : $(cat "$out")"
grep -qF -- "$fake_token" "$out" "$tmp/err.txt" && ko "jeton en clair dans la sortie du checkout authentifié"
ok "checkout : clone et fetch authentifiés, masque base64 sur stdout"

# --- 14. wip périodique des extra : propre, secret bloqué, main refusée -------
mkrepo galass-emu-actions-pub main
# Checkout file:// (sans réseau) sur une branche de fonctionnalité neuve.
rm -rf "$root/galass-emu-actions-pub"
IN_BRANCH=feat/ms EXTRA_REPOS=galass-emu-actions-pub TARGET_REPO=Galass_backend \
  EXTRA_ROOT="$root" EXTRA_STATE="$state" EXTRA_SRC_DIR="$src" \
  "$script" checkout > "$out" 2>"$tmp/err.txt" \
  || ko "checkout emu pour wip en échec : $(cat "$tmp/err.txt")"
printf 'wip-ok\n' > "$root/galass-emu-actions-pub/wip.txt"
git -C "$root/galass-emu-actions-pub" add wip.txt
git -C "$root/galass-emu-actions-pub" commit -qm "wip: ok"
wipst="$tmp/extra-wip"
IN_JOB=testjob IN_RUN=42 IN_BRANCH=feat/ms EXTRA_REPOS=galass-emu-actions-pub \
  TARGET_REPO=Galass_backend EXTRA_ROOT="$root" EXTRA_STATE="$state" \
  EXTRA_SRC_DIR="$src" EXTRA_WIP_STATE="$wipst" EXTRA_GITLEAKS="$gl" \
  "$script" wip-once > "$out" 2>"$tmp/err.txt" \
  || ko "wip-once propre en échec : $(cat "$tmp/err.txt") $(cat "$out")"
emu_head=$(git -C "$root/galass-emu-actions-pub" rev-parse HEAD)
[ "$(git -C "$src/galass-emu-actions-pub.git" rev-parse refs/heads/feat/ms)" = "$emu_head" ] \
  || ko "wip-once n'a pas poussé la branche de fonctionnalité"
grep -q 'wip poussé' "$out" "$wipst/galass-emu-actions-pub/status" \
  || ko "ligne de suivi wip poussé absente : $(cat "$out")"
ok "wip-once : commit propre poussé sur la branche de fonctionnalité"

# Secret : non poussé, valeur absente, distant intact.
sec2=$(fake_ghp)
h_emu=$(git -C "$src/galass-emu-actions-pub.git" rev-parse refs/heads/feat/ms)
printf 'export GITHUB_TOKEN=%s\n' "$sec2" > "$root/galass-emu-actions-pub/sec.txt"
git -C "$root/galass-emu-actions-pub" add sec.txt
git -C "$root/galass-emu-actions-pub" commit -qm "wip: secret"
IN_JOB=testjob IN_RUN=42 IN_BRANCH=feat/ms EXTRA_REPOS=galass-emu-actions-pub \
  TARGET_REPO=Galass_backend EXTRA_ROOT="$root" EXTRA_STATE="$state" \
  EXTRA_SRC_DIR="$src" EXTRA_WIP_STATE="$wipst" EXTRA_GITLEAKS="$gl" \
  "$script" wip-once > "$out" 2>"$tmp/err.txt" \
  || ko "wip-once secret en échec inattendu (doit être non fatal) : $(cat "$tmp/err.txt")"
grep -q 'secret probable' "$out" "$wipst/galass-emu-actions-pub/status" \
  || ko "secret non signalé par wip-once : $(cat "$out")"
[ "$(git -C "$src/galass-emu-actions-pub.git" rev-parse refs/heads/feat/ms)" = "$h_emu" ] \
  || ko "secret poussé par wip-once"
grep -rqaF -- "$sec2" "$out" "$tmp/err.txt" "$wipst" && ko "valeur du secret dans la sortie wip"
git -C "$root/galass-emu-actions-pub" reset -q --hard "$h_emu"
ok "wip-once : secret bloqué par gitleaks, non poussé"

# main refusée ; aucun --force dans les arguments.
IN_JOB=testjob IN_RUN=42 IN_BRANCH=main EXTRA_REPOS=galass-emu-actions-pub \
  TARGET_REPO=Galass_backend EXTRA_ROOT="$root" EXTRA_STATE="$state" \
  EXTRA_SRC_DIR="$src" EXTRA_WIP_STATE="$wipst" EXTRA_GITLEAKS="$gl" \
  "$script" wip-once > "$out" 2>"$tmp/err.txt" && ko "wip-once accepté sur main"
grep -q 'branche interdite' "$tmp/err.txt" || ko "refus de main non signalé : $(cat "$tmp/err.txt")"
# Intercepter un passage propre : le vrai git derrière un shim ne doit jamais voir --force.
force_shim="$tmp/force-shim"; mkdir -p "$force_shim"
realgit=$(command -v git)
cat > "$force_shim/git" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/wip.argv"
for a in "\$@"; do
  case "\$a" in --force|--force-with-lease|-f) echo FORCE >> "$tmp/wip.argv"; exit 1 ;; esac
done
exec "$realgit" "\$@"
SHIM
chmod +x "$force_shim/git"
printf 'wip2\n' >> "$root/galass-emu-actions-pub/wip.txt"
git -C "$root/galass-emu-actions-pub" add wip.txt
git -C "$root/galass-emu-actions-pub" commit -qm "wip: 2"
: > "$tmp/wip.argv"
IN_JOB=testjob IN_RUN=42 IN_BRANCH=feat/ms EXTRA_REPOS=galass-emu-actions-pub \
  TARGET_REPO=Galass_backend EXTRA_ROOT="$root" EXTRA_STATE="$state" \
  EXTRA_SRC_DIR="$src" EXTRA_WIP_STATE="$wipst" EXTRA_GITLEAKS="$gl" \
  PATH="$force_shim:$PATH" \
  "$script" wip-once > "$out" 2>"$tmp/err.txt" \
  || ko "wip-once (contrôle force) en échec : $(cat "$tmp/err.txt") $(cat "$out")"
grep -q FORCE "$tmp/wip.argv" && ko "wip-once a utilisé --force"
emu_head2=$(git -C "$root/galass-emu-actions-pub" rev-parse HEAD)
[ "$(git -C "$src/galass-emu-actions-pub.git" rev-parse refs/heads/feat/ms)" = "$emu_head2" ] \
  || ko "second wip non poussé"
ok "wip-once : main refusée, aucun force"

echo "PASS extra-repos : parse, checkout, push propre, secret, clé ISA, workflows, non-ff, main, PR brouillon, jeton caché, fetch authentifié, wip périodique"
