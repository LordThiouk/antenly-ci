#!/usr/bin/env bash
# Test local du push périodique des wip (wippush.sh) contre un dépôt nu local, sans réseau réel :
# cas propre (push normal), rien de neuf (silence), secret factice ghp_ bloqué (aucun push, nom de
# fichier seulement), clé ISA bloquée, non-fast-forward refusé (jamais de force), jeton jamais dans
# les arguments ni la sortie, démon arrêté par SIGTERM, main refusée. gitleaks réel (version épinglée
# du workflow) ; si absent, téléchargé et vérifié par tests/lib.sh.
#   opencode/tests/wippush-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
gl=$(find_gitleaks "$tmp") || ko "gitleaks introuvable"
remote="$tmp/remote.git"; git init -q --bare "$remote"
work="$tmp/work"; git init -q -b feat/test "$work"
git -C "$work" config user.name Test; git -C "$work" config user.email test@example.invalid
printf 'depart\n' > "$work/README.md"
git -C "$work" add README.md && git -C "$work" commit -qm "base"
base=$(git -C "$work" rev-parse HEAD)
git -C "$work" push -q "$remote" "HEAD:refs/heads/feat/test"
git -C "$remote" symbolic-ref HEAD refs/heads/feat/test
export WIP_STATE="$tmp/state" WIP_REPO="$work" WIP_BRANCH=feat/test WIP_JOB=testjob WIP_RUN=42 \
       WIP_REMOTE="file://$remote" WIP_GITLEAKS="$gl" WIP_BASE_SHA="$base" WIP_TRIES=1 WIP_TIMEOUT=10
fake_token="TESTPUSHTOKEN$(rand_alnum 24)"
out="$tmp/out.txt"
remote_head() { git -C "$remote" rev-parse -q --verify "refs/heads/feat/test"; }
run_once() { printf '%s\n' "$fake_token" | WIP_TOKEN_STDIN=1 "$here/wippush.sh" once > "$out" 2>&1; }
line() { tr -dc '0-9a-f' < "$WIP_STATE/pushed"; }

# --- 1. cas propre : le commit du run est poussé, ligne [suivi], état mis à jour --------------
printf 'travail\n' > "$work/a.txt"; git -C "$work" add a.txt; git -C "$work" commit -qm "wip: a"
h1=$(git -C "$work" rev-parse HEAD)
run_once
[ "$(remote_head)" = "$h1" ] || ko "commit non poussé : $(cat "$out")"
grep -qF "[suivi] wip poussé ${h1:0:7}" "$out" || ko "ligne [suivi] de push absente : $(cat "$out")"
[ "$(line)" = "$h1" ] || ko "état du dernier SHA poussé incohérent"
ok "cas propre : wip poussé ${h1:0:7} sur feat/test"

# --- 2. rien de neuf : aucun second push -----------------------------------------------------
run_once
grep -q 'poussé' "$out" && ko "push inutile signalé alors que rien n'a changé : $(cat "$out")"
[ "$(remote_head)" = "$h1" ] || ko "le distant a bougé sans nouveau commit"
ok "rien de neuf : silence, aucun push"

# --- 3. secret factice ghp_ : aucun push, nom de fichier seul, secret jamais affiché ---------
sec=$(fake_ghp)
printf 'export GITHUB_TOKEN=%s\n' "$sec" > "$work/secret.txt"
git -C "$work" add secret.txt; git -C "$work" commit -qm "wip: config"
run_once
[ "$(remote_head)" = "$h1" ] || ko "secret poussé malgré le blocage"
grep -q 'wip non poussé : secret probable dans secret.txt' "$out" || ko "ligne de blocage inattendue : $(cat "$out")"
grep -qaF -- "$sec" "$out" "$WIP_STATE/status" && ko "valeur du secret dans la sortie"
[ "$(line)" = "$h1" ] || ko "le dernier SHA poussé a bougé malgré le blocage"
ok "secret ghp_ : non poussé, fichier cité, valeur absente"

# --- 4. clé ISA dans les commits : bloquée comme le contrôle final ---------------------------
git -C "$work" reset -q --hard "$h1"
key=$(rand_alnum 64)
printf '%s' "$key" > "$tmp/isa.key"; chmod 600 "$tmp/isa.key"
printf 'empreinte %s\n' "$key" > "$work/isa.txt"
git -C "$work" add isa.txt; git -C "$work" commit -qm "wip: empreinte"
printf '%s\n' "$fake_token" | WIP_TOKEN_STDIN=1 WIP_ISA_KEY_FILE="$tmp/isa.key" "$here/wippush.sh" once > "$out" 2>&1
[ "$(remote_head)" = "$h1" ] || ko "clé ISA poussée malgré le blocage"
grep -q 'non poussé : la clé ISA apparaît' "$out" || ko "blocage clé ISA non signalé : $(cat "$out")"
grep -qaF -- "$key" "$out" "$WIP_STATE/status" && ko "clé ISA dans la sortie"
git -C "$work" reset -q --hard "$h1"
ok "clé ISA : non poussée, jamais affichée"

# --- 5. non fast-forward : push refusé, jamais de force --------------------------------------
other="$tmp/other"; git clone -q "$remote" "$other"
git -C "$other" checkout -q -B feat/test origin/feat/test
git -C "$other" config user.name Other; git -C "$other" config user.email other@example.invalid
printf 'distant\n' > "$other/b.txt"; git -C "$other" add b.txt; git -C "$other" commit -qm "distant: b"
git -C "$other" push -q origin feat/test
r1=$(remote_head)
printf 'local\n' > "$work/c.txt"; git -C "$work" add c.txt; git -C "$work" commit -qm "wip: c"
run_once
[ "$(remote_head)" = "$r1" ] || ko "force-push probable : le distant a été réécrit"
grep -q 'non poussé : envoi refusé' "$out" || ko "refus non fast-forward non signalé : $(cat "$out")"
ok "non fast-forward : refusé, distant intact (aucun force)"

# --- 6. remote https simulé : jeton par l'environnement seul, jamais en argument -------------
shim="$tmp/shim"; mkdir -p "$shim"; realgit=$(command -v git)
cat > "$shim/git" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = push ]; then
  printf '%s\n' "\$*" > "$tmp/push.argv"
  printf '%s' "\${GIT_CONFIG_KEY_1:-} \${GIT_CONFIG_VALUE_1:-}" > "$tmp/push.hdr"
  exit 0
fi
exec "$realgit" "\$@"
SHIM
chmod +x "$shim/git"
git -C "$work" fetch -q "$remote" "+refs/heads/feat/test:refs/remotes/distant/feat/test"
git -C "$work" reset -q --hard refs/remotes/distant/feat/test
printf 'https\n' > "$work/d.txt"; git -C "$work" add d.txt; git -C "$work" commit -qm "wip: d"
printf '%s\n' "$fake_token" | PATH="$shim:$PATH" WIP_TOKEN_STDIN=1 WIP_STATE="$tmp/state-h" \
  WIP_REMOTE=https://github.com/LordThiouk/antenly.git "$here/wippush.sh" once > "$out" 2>&1
grep -q 'wip poussé' "$out" || ko "push https simulé en échec : $(cat "$out")"
grep -qF -- "$fake_token" "$tmp/push.argv" && ko "jeton dans les arguments de git"
grep -q 'https://github.com/LordThiouk/antenly.git' "$tmp/push.argv" || ko "URL inattendue"
grep -q '@github.com' "$tmp/push.argv" && ko "identifiants dans l'URL"
want="http.https://github.com/.extraheader AUTHORIZATION: basic $(printf 'x-access-token:%s' "$fake_token" | base64 -w0)"
[ "$(cat "$tmp/push.hdr")" = "$want" ] || ko "en-tête d'authentification absent ou inattendu"
ok "remote https : jeton passé à git par son environnement seul (ni argument, ni URL)"

# --- 7. démon : passages réguliers, arrêt propre sur SIGTERM ---------------------------------
remote2="$tmp/remote2.git"; git init -q --bare "$remote2"
w2="$tmp/work2"; git init -q -b feat/d "$w2"
git -C "$w2" config user.name Test; git -C "$w2" config user.email test@example.invalid
printf 'base\n' > "$w2/README.md"; git -C "$w2" add README.md; git -C "$w2" commit -qm base
git -C "$w2" push -q "$remote2" "HEAD:refs/heads/feat/d"
b2=$(git -C "$w2" rev-parse HEAD)
export WIP_STATE="$tmp/state2" WIP_REPO="$w2" WIP_BRANCH=feat/d WIP_RUN=43 WIP_REMOTE="file://$remote2" WIP_BASE_SHA="$b2"
dout="$tmp/daemon.out"
printf '%s\n' "$fake_token" | WIP_TOKEN_STDIN=1 WIP_FIRST=1 WIP_INTERVAL_SEC=2 \
  "$here/wippush.sh" daemon > "$dout" 2>&1 &
pid=$!
sleep 1
printf 'un\n' > "$w2/one.txt"; git -C "$w2" add one.txt; git -C "$w2" commit -qm "wip: un"
for _ in $(seq 1 40); do [ "$(grep -c 'wip poussé' "$dout" 2>/dev/null)" -ge 1 ] && break; sleep 0.5; done
printf 'deux\n' > "$w2/two.txt"; git -C "$w2" add two.txt; git -C "$w2" commit -qm "wip: deux"
for _ in $(seq 1 40); do [ "$(grep -c 'wip poussé' "$dout" 2>/dev/null)" -ge 2 ] && break; sleep 0.5; done
[ "$(grep -c 'wip poussé' "$dout")" -ge 2 ] || ko "le démon n'a pas poussé deux commits : $(cat "$dout")"
[ "$(git -C "$remote2" rev-parse refs/heads/feat/d)" = "$(git -C "$w2" rev-parse HEAD)" ] || ko "le démon n'a pas suivi le HEAD"
kill -TERM "$pid"
for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
kill -0 "$pid" 2>/dev/null && { kill -KILL "$pid"; ko "le démon ne s'arrête pas sur SIGTERM"; }
grep -q 'arrêté' "$dout" || ko "arrêt non signalé"
ok "démon : deux pushes, arrêt propre sur SIGTERM"

# --- 8. main et branches interdites refusées -------------------------------------------------
for b in main master refs/heads/x fullrun-logs/test; do
  WIP_BRANCH="$b" WIP_STATE="$tmp/state3" "$here/wippush.sh" once > "$out" 2>&1 && ko "branche interdite acceptée : $b"
done
ok "branches main/master/refs/fullrun-logs refusées à l'entrée"

# --- 9. le jeton n'apparaît nulle part -------------------------------------------------------
grep -rqaF -- "$fake_token" "$tmp/state" "$tmp/state-h" "$tmp/state2" "$dout" "$out" "$remote" "$remote2" \
  && ko "jeton retrouvé dans la sortie, l'état ou un dépôt"
ok "jeton absent des sorties, de l'état et des dépôts"

echo "PASS wippush : propre, silence, secret bloqué, clé ISA, non-fast-forward, jeton caché, démon, main refusée"
