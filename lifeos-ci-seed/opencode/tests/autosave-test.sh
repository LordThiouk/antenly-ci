#!/usr/bin/env bash
# Test local de la sauvegarde automatique (autosave.sh, via wippush.sh) sur de vrais dépôts git et un
# vrai gitleaks. Prouve en particulier :
#  A. un commit `wip(carry)` / `wip(autosave)` ne déclenche pas la porte de clôture (aucun de ses mots
#     n'est dans la regex de la porte, lue dans le plugin LifeOS quand il est présent) ;
#  B. un fichier interdit (.env, clés, keystores, google-services, comptes de service, secrets PSP, builds,
#     dépendances…) n'est jamais commité, jamais poussé, et reste intact dans l'arbre ;
#  C. une fuite (faux jeton généré à l'exécution) n'est ni commitée ni poussée, sa valeur n'apparaît nulle part.
# + jamais `git add -A`, index de l'agent intact, verrou d'index, mauvaise branche, gitleaks absent = rien commité.
#   opencode/tests/autosave-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
gl=$(find_gitleaks "$tmp") || ko "gitleaks introuvable"
AS="$here/autosave.sh"
export AS_GITLEAKS="$gl" AS_TMP="$tmp" AS_DENY_FILE="$here/autosave-deny.txt" AS_BRANCH=feat/test

newrepo() { # $1 = dossier
  rm -rf "$1"; git init -q -b feat/test "$1"
  git -C "$1" config user.name Test; git -C "$1" config user.email test@example.invalid
  mkdir -p "$1/MEMORY/WORK/s" "$1/.fullrun" "$1/src" "$1/docs"
  printf -- '---\nphase: climbing\n---\n' > "$1/MEMORY/WORK/s/ISA.md"
  printf 'v1\n' > "$1/src/mod.py"; printf 'gone\n' > "$1/src/old.py"
  git -C "$1" add -A && git -C "$1" commit -qm base
}
run_as() { AS_REPO="$1" bash "$AS" > "$tmp/out.txt" 2>&1; }
files_ever() { git -C "$1" log --all --name-only --format= | sort -u; }

# --- 0. jamais git add -A / add . / add --all -------------------------------------------------
grep -nE 'git[^#]*\badd\b[^#]*(-A\b|--all\b|[[:space:]]\.([[:space:]]|$))' "$AS" | grep -v '^[0-9]*:#' && ko "autosave.sh contient un git add aveugle"
grep -nE 'as_git add -- "\$\{LP\[@\]\}"' "$AS" >/dev/null || ko "git add nominatif littéral (:(literal)) attendu"
ok "aucun git add -A / . / --all : seuls des chemins nommés sont ajoutés"

# --- A. carry + checkpoint : commit wip(carry), index de l'agent intact, porte de clôture muette -------
R="$tmp/a"; newrepo "$R"
printf '{"payload":{"v":1,"isa":"s","head":"","steps":{}},"sig":"x"}\n' > "$R/MEMORY/WORK/s/fullrun-carry.json"
printf '{"version":1,"job":"j","steps":{"1":{"status":"done"}},"verdicts":[]}\n' > "$R/.fullrun/j_checkpoint.json"
printf '{"k":"v"}\n' > "$R/credentials.json"; git -C "$R" add -f credentials.json   # indexé par l'agent, interdit pour l'autosave
h0=$(git -C "$R" rev-parse HEAD)
run_as "$R"
h1=$(git -C "$R" rev-parse HEAD)
[ "$h1" != "$h0" ] || ko "aucun commit wip(carry) : $(cat "$tmp/out.txt")"
msg=$(git -C "$R" log -1 --format=%s)
[ "$msg" = "wip(carry): reprise du run" ] || ko "message inattendu : $msg"
got=$(git -C "$R" show --name-only --format= HEAD | sort | tr '\n' ' ')
[ "$got" = ".fullrun/j_checkpoint.json MEMORY/WORK/s/fullrun-carry.json " ] || ko "fichiers du commit wip(carry) : $got"
[ "$(git -C "$R" diff --cached --name-only)" = "credentials.json" ] || ko "l'index de l'agent a été touché : $(git -C "$R" diff --cached --name-only)"
files_ever "$R" | grep -qx credentials.json && ko "credentials.json indexé par l'agent a été commité par l'autosave"
ok "carry + checkpoint commités en wip(carry) ; l'index de l'agent reste tel quel (credentials.json toujours indexé, non commité)"

# Porte de clôture du plugin LifeOS : regex lue dans le plugin si présent, sinon copie de référence.
plugin="${LIFEOS_PLUGIN:-$here/../../lifeos/opencode/plugins/lifeos-hooks.ts}"
python3 - "$plugin" "$(git -C "$R" log -1 --format=%s)" "wip(autosave): arbre de travail" <<'PY' || ko "un message d'autosave déclencherait la porte de clôture"
import re, sys
plugin, msgs = sys.argv[1], sys.argv[2:]
pat = r"clos|clôtur|cloture|complete|phase|tick|coch|\[x\]|verdict|v[ée]rif|\bisa\b|isc"   # copie de référence
try:
    m = re.search(r"const closingCommit[^\n]*\n[^\n]*?if \(/([^\n]*?)/i\.test\(c\)\)", open(plugin, encoding="utf-8").read())
    if m:
        pat = m.group(1)
        print("regex lue dans le plugin LifeOS")
except OSError:
    print("plugin absent : regex de référence")
for t in msgs:
    cmd = f'git commit -q -m "{t}" -- fichier'
    if re.search(pat, cmd, re.I):
        print("DÉCLENCHE la porte :", cmd); sys.exit(1)
PY
ok "A. les messages wip(carry) et wip(autosave) ne déclenchent pas la porte de clôture"

# --- B. fichiers interdits : jamais commités, jamais poussés, intacts dans l'arbre -----------------
R="$tmp/b"; newrepo "$R"
mkdir -p "$R/storage/logs" "$R/vendor/lib" "$R/android/app" "$R/core/config"
printf 'APP_KEY=x\n' > "$R/core/.env"; printf 'A=1\n' > "$R/.env.production"; printf '{"k":"v"}\n' > "$R/credentials.json"
printf '{"p":"x"}\n' > "$R/android/app/google-services.json"; printf 'storePassword=x\n' > "$R/android/key.properties"
printf 'x\n' > "$R/android/upload.jks"; printf '{"t":"x"}\n' > "$R/core/service-account.json"
printf '{"t":"x"}\n' > "$R/core/firebase-adminsdk-abc.json"; printf 'x\n' > "$R/core/config/gateway_parameter.php"
printf 'x\n' > "$R/storage/logs/laravel.log"; printf 'x\n' > "$R/vendor/lib/a.php"; printf 'x\n' > "$R/app-release.apk"
printf 'x\n' > "$R/secret.pem"
ln -s /etc/passwd "$R/src/lien.py"
head -c 6291456 /dev/zero | tr '\0' 'a' > "$R/src/gros.txt"
printf 'a\0b\n' > "$R/src/bin.dat"
printf 'v2\n' > "$R/src/mod.py"; rm -f "$R/src/old.py"
printf 'ok\n' > "$R/src/ok.py"; printf 'note\n' > "$R/docs/note.md"
run_as "$R"
ever=$(files_ever "$R")
for bad in core/.env .env.production credentials.json android/app/google-services.json android/key.properties android/upload.jks \
           core/service-account.json core/firebase-adminsdk-abc.json core/config/gateway_parameter.php storage/logs/laravel.log \
           vendor/lib/a.php app-release.apk secret.pem src/lien.py src/gros.txt src/bin.dat; do
  printf '%s\n' "$ever" | grep -qxF "$bad" && ko "fichier interdit commité : $bad"
  [ -e "$R/$bad" ] || [ -L "$R/$bad" ] || ko "fichier interdit supprimé de l'arbre : $bad"
done
for good in src/ok.py docs/note.md src/mod.py src/old.py; do
  printf '%s\n' "$ever" | grep -qxF "$good" || ko "fichier autorisé non sauvé : $good"
done
[ "$(git -C "$R" show HEAD:src/mod.py)" = "v2" ] || ko "modification autorisée non commitée"
git -C "$R" cat-file -e HEAD:src/old.py 2>/dev/null && ko "suppression autorisée non commitée"
git -C "$R" status --porcelain -uall | grep -q '^?? credentials.json$' || ko "credentials.json devrait rester non suivi dans l'arbre"
grep -q 'non commité — liste d.exclusion' "$tmp/out.txt" || ko "raison d'exclusion non annoncée : $(cat "$tmp/out.txt")"
ok "B. 16 fichiers interdits (.env, clés, keystore, google-services, comptes de service, secrets PSP, logs, vendor, apk, lien, gros, binaire) jamais commités ; 4 autorisés sauvés"

# --- B2. nom de fichier « magique » (:(top)*) : git le lirait comme un motif et prendrait tout l'arbre ----
R="$tmp/b2"; newrepo "$R"
printf '{"k":"v"}\n' > "$R/keys.json"; printf 'A=1\n' > "$R/.env"; printf 'ok\n' > "$R/src/ok.py"
for magic in ':(top)*' ':(glob)**' ':(top)' ':^src' ':(literal)x'; do printf 'm\n' > "$R/$magic"; done
run_as "$R"
ever=$(files_ever "$R")
for bad in keys.json .env; do
  printf '%s\n' "$ever" | grep -qxF "$bad" && ko "B2. fichier interdit commité via un nom magique : $bad"
  [ -e "$R/$bad" ] || ko "B2. fichier interdit supprimé : $bad"
done
printf '%s\n' "$ever" | grep -qxF 'src/ok.py' || ko "B2. fichier autorisé non sauvé"
printf '%s\n' "$ever" | grep -qxF ':(top)*' || ko "B2. le fichier au nom magique devrait être sauvé comme un fichier ordinaire"
n=$(git -C "$R" rev-list --count HEAD); [ "$n" -le 2 ] || ko "B2. trop de commits ($n)"
ok "B2. fichiers nommés :(top)*, :(glob)**, :(top), :^src : traités comme des noms ordinaires, keys.json et .env jamais commités"

# --- C. fuite : ni commitée ni poussée, valeur jamais affichée ----------------------------------
R="$tmp/c"; newrepo "$R"
remote="$tmp/c-remote.git"; git init -q --bare "$remote"
git -C "$R" push -q "$remote" HEAD:refs/heads/feat/test; git -C "$remote" symbolic-ref HEAD refs/heads/feat/test
base=$(git -C "$R" rev-parse HEAD)
sec=$(fake_ghp)
printf 'export GITHUB_TOKEN=%s\n' "$sec" > "$R/src/leak.py"
printf 'propre=1\n' > "$R/src/clean.py"
export WIP_STATE="$tmp/state" WIP_REPO="$R" WIP_BRANCH=feat/test WIP_JOB=testjob WIP_RUN=42 \
       WIP_REMOTE="file://$remote" WIP_GITLEAKS="$gl" WIP_BASE_SHA="$base" WIP_TRIES=1 WIP_TIMEOUT=10 \
       WIP_AUTOSAVE_DENY="$here/autosave-deny.txt"
rm -rf "$WIP_STATE"
printf 'JETONFACTICE%s\n' "$(rand_alnum 20)" | WIP_TOKEN_STDIN=1 "$here/wippush.sh" once > "$tmp/wip.out" 2>&1
git -C "$R" log --all -p --format= | grep -qF -- "$sec" && ko "le secret est dans l'historique local"
git -C "$remote" log --all -p --format= | grep -qF -- "$sec" && ko "le secret a été POUSSÉ"
files_ever "$R" | grep -qx 'src/leak.py' && ko "leak.py commité"
git -C "$remote" log --all --name-only --format= | grep -qx 'src/leak.py' && ko "leak.py poussé"
[ -e "$R/src/leak.py" ] || ko "le fichier qui fuit a été supprimé de l'arbre"
git -C "$remote" log --all --name-only --format= | grep -qx 'src/clean.py' || ko "le fichier propre n'a pas été sauvé et poussé : $(cat "$tmp/wip.out")"
grep -q 'autosave : secret probable dans leak.py, non commité' "$tmp/wip.out" || ko "ligne de fuite absente : $(cat "$tmp/wip.out")"
grep -qaF -- "$sec" "$tmp/wip.out" "$WIP_STATE/status" && ko "valeur du secret dans la sortie"
ok "C. fuite : leak.py ni commité ni poussé (valeur absente partout), clean.py sauvé et poussé"

# Un commit déjà fait avec un secret reste bloqué par le contrôle de plage de wippush (inchangé).
printf 'export GITHUB_TOKEN=%s\n' "$sec" > "$R/src/leak2.py"
git -C "$R" add src/leak2.py; git -C "$R" commit -qm "wip: a la main"
before=$(git -C "$remote" rev-parse refs/heads/feat/test)
printf 'JETONFACTICE%s\n' "$(rand_alnum 20)" | WIP_TOKEN_STDIN=1 "$here/wippush.sh" once > "$tmp/wip.out" 2>&1
[ "$(git -C "$remote" rev-parse refs/heads/feat/test)" = "$before" ] || ko "un commit contenant un secret a été poussé"
grep -q 'wip non poussé : secret probable' "$tmp/wip.out" || ko "blocage du push attendu : $(cat "$tmp/wip.out")"
ok "C. un commit contenant une fuite bloque le push (contrôle de plage de wippush)"
unset WIP_STATE WIP_REPO WIP_BRANCH WIP_JOB WIP_RUN WIP_REMOTE WIP_GITLEAKS WIP_BASE_SHA WIP_TRIES WIP_TIMEOUT WIP_AUTOSAVE_DENY

# --- D. garde-fous de passage ---------------------------------------------------------------------
R="$tmp/d"; newrepo "$R"; printf 'x=1\n' > "$R/src/new.py"
h=$(git -C "$R" rev-parse HEAD)
touch "$R/.git/index.lock"; run_as "$R"; rm -f "$R/.git/index.lock"
[ "$(git -C "$R" rev-parse HEAD)" = "$h" ] || ko "commit malgré index.lock"
grep -q "index occupé" "$tmp/out.txt" || ko "message index.lock absent"
git -C "$R" checkout -q -b autre; run_as "$R"
[ "$(git -C "$R" rev-parse HEAD)" = "$h" ] || ko "commit sur une autre branche"
git -C "$R" checkout -q feat/test
AS_GITLEAKS=/nonexistent/gitleaks run_as "$R"
[ "$(git -C "$R" rev-parse HEAD)" = "$h" ] || ko "commit sans contrôle gitleaks"
[ -z "$(git -C "$R" diff --cached --name-only)" ] || ko "index laissé sale après échec du contrôle"
grep -q "gitleaks impossible" "$tmp/out.txt" || ko "message fail-closed absent : $(cat "$tmp/out.txt")"
AS_DENY_FILE=/nonexistent run_as "$R"
[ "$(git -C "$R" rev-parse HEAD)" = "$h" ] || ko "commit sans liste d'exclusion"
ok "D. index.lock, autre branche, gitleaks absent (index remis), liste d'exclusion absente : rien commité"

# --- E. un passage sans changement ne fait rien ---------------------------------------------------
R="$tmp/e"; newrepo "$R"; h=$(git -C "$R" rev-parse HEAD); run_as "$R"
[ "$(git -C "$R" rev-parse HEAD)" = "$h" ] && [ ! -s "$tmp/out.txt" ] || ko "bruit ou commit sans changement"
ok "E. arbre propre : silence, aucun commit"

# --- F. démon root, dépôt d'un autre propriétaire (CI) : commit fait comme propriétaire, aucun fichier root dans .git
if [ "$(id -u)" = 0 ] && command -v setpriv >/dev/null 2>&1; then
  R="$tmp/f"; newrepo "$R"; printf 'v=1\n' > "$R/src/nouveau.py"
  printf '{"version":1,"job":"j","steps":{},"verdicts":[]}\n' > "$R/.fullrun/j_checkpoint.json"
  chown -R 1000:1000 "$R"; chmod 755 "$tmp"
  h=$(git -C "$R" rev-parse HEAD 2>/dev/null || git -c safe.directory='*' -C "$R" rev-parse HEAD)
  AS_TMP="$tmp" run_as "$R"
  h2=$(git -c safe.directory='*' -C "$R" rev-parse HEAD)
  [ "$h2" != "$h" ] || ko "aucun commit sur un dépôt d'un autre propriétaire : $(cat "$tmp/out.txt")"
  root_owned=$(find "$R/.git" -user 0 2>/dev/null | head -3)
  [ -z "$root_owned" ] || ko "fichiers root créés dans .git : $root_owned"
  git -c safe.directory='*' -C "$R" log --format=%s -2 | grep -q 'wip(autosave)' || ko "commit wip(autosave) absent"
  ok "F. dépôt d'un autre propriétaire : commits faits comme propriétaire, aucun fichier root dans .git"
else
  ok "F. ignoré (pas root ou setpriv absent)"
fi
