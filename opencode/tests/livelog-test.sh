#!/usr/bin/env bash
# Test local du journal en direct (livelog.sh) contre un dépôt git nu local, sans réseau réel :
# instantané en clair, instantané chiffré quand gitleaks trouve un secret après masquage, envoi
# impossible borné, journal de fin posé par-dessus sans force, démon arrêté par SIGTERM, jeton
# jamais dans la sortie ni l'état. Si sudo est dispo : en root, un lien vers un fichier root est
# lu avec les droits de l'utilisateur (donc refusé).
#   opencode/tests/livelog-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
key="${AGE_KEY:-$HOME/.config/age/fullrun-logs.key}"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
gl=$(find_gitleaks "$tmp") || ko "gitleaks introuvable"
command -v age >/dev/null || ko "age absent"
remote="$tmp/remote.git"; git init -q --bare "$remote"
export LIVE_STATE="$tmp/state" LIVE_LOG="$tmp/opencode.log" LIVE_JOB=testjob LIVE_RUN=42 \
       LIVE_REMOTE="file://$remote" LIVE_GITLEAKS="$gl" LIVE_TRIES=2 LIVE_TIMEOUT=10
BR=fullrun-logs/testjob-42
fake_token="TESTPUSHTOKEN$(rand_alnum 24)"
out="$tmp/out.txt"

# --- 1. instantané en clair -------------------------------------------------------------------
printf '[suivi] début\nLifeOS | Algorithm | Build\n' > "$LIVE_LOG"
printf '%s\n' "$fake_token" | LIVE_TOKEN_STDIN=1 "$here/livelog.sh" snapshot > "$out" 2>&1 || ko "snapshot en échec"
grep -q 'envoyé (clair)' "$out" || ko "instantané clair non envoyé : $(cat "$out")"
c1=$(git -C "$remote" rev-parse "refs/heads/$BR") || ko "branche $BR absente du dépôt distant"
[ "$(git -C "$remote" ls-tree -r --name-only "$c1")" = ".fullrun/logs/testjob-42.log" ] || ko "arbre inattendu"
git -C "$remote" show "$c1:.fullrun/logs/testjob-42.log" | grep -q 'LifeOS | Algorithm | Build' || ko "contenu absent"
ok "instantané en clair poussé sur $BR"

# --- 2. secret que le masquage ne connaît pas (glpat-) : l'instantané part chiffré -----------
sec=$(fake_glpat)
printf 'export GITLAB_TOKEN=%s\nsuite du travail\n' "$sec" >> "$LIVE_LOG"
"$here/livelog.sh" snapshot > "$out" 2>&1 || ko "snapshot 2 en échec"
grep -q 'envoyé (chiffré)' "$out" || ko "instantané non chiffré : $(cat "$out")"
c2=$(git -C "$remote" rev-parse "refs/heads/$BR")
[ "$(git -C "$remote" rev-parse "$c2^")" = "$c1" ] || ko "pas un commit normal au-dessus du précédent"
[ "$(git -C "$remote" ls-tree -r --name-only "$c2")" = ".fullrun/logs/testjob-42.age" ] || ko "le clair est resté dans l'arbre"
git -C "$remote" log -p --all --text | grep -qF -- "$sec" && ko "secret en clair dans le dépôt distant"
ok "secret détecté : instantané chiffré, aucun clair dans l'historique distant"
if [ -f "$key" ]; then
  mkdir -p "$tmp/x"
  git -C "$remote" show "$c2:.fullrun/logs/testjob-42.age" | age -d -i "$key" | tar -xz -C "$tmp/x" || ko "déchiffrement impossible"
  grep -q 'suite du travail' "$tmp/x/opencode.log" || ko "journal déchiffré incomplet"
  jq -e 'length >= 1' "$tmp/x/gitleaks.json" >/dev/null || ko "rapport gitleaks absent"
  ok "instantané chiffré : age -d -i ~/.config/age/fullrun-logs.key le déchiffre"
fi

# --- 3. dépôt distant injoignable : essais bornés, pas d'erreur, état local conservé ---------
t0=$(date +%s)
LIVE_REMOTE="file://$tmp/absent.git" "$here/livelog.sh" snapshot > "$out" 2>&1 || ko "snapshot doit rendre 0"
dt=$(( $(date +%s) - t0 ))
grep -q 'envoi impossible' "$out" || ko "échec d'envoi non signalé"
[ "$dt" -le 30 ] || ko "échec d'envoi trop long (${dt} s)"
[ "$(git -C "$remote" rev-parse "refs/heads/$BR")" = "$c2" ] || ko "le distant a bougé"
ok "envoi impossible : on passe en ${dt} s, le run n'est pas touché"
# Le passage suivant rattrape l'instantané manqué (chaîne linéaire, pas de force).
"$here/livelog.sh" snapshot > "$out" 2>&1
c3=$(git -C "$remote" rev-parse "refs/heads/$BR")
[ "$(git -C "$remote" rev-list --count "$c3")" = 4 ] || ko "chaîne attendue : 4 commits"
ok "passage suivant : instantané manqué rattrapé (4 commits linéaires)"

# --- 4. journal de fin posé par-dessus (comme le step de contrôle puis le step push) ---------
work="$tmp/antenly"; git init -q "$work"
tip=$(tr -dc '0-9a-f' < "$LIVE_STATE/tip")
git -C "$work" fetch -q "$LIVE_STATE/live.bundle" "refs/heads/live:refs/fullrun-live/tip" || ko "lecture du paquet impossible"
[ "$(git -C "$work" rev-parse refs/fullrun-live/tip)" = "$tip" ] || ko "paquet ≠ tip"
blob=$(printf 'journal final\n' | git -C "$work" hash-object -w --stdin)
idx="$tmp/idx"
GIT_INDEX_FILE="$idx" git -C "$work" update-index --add --cacheinfo "100644,$blob,.fullrun/logs/testjob-42.log"
tree=$(GIT_INDEX_FILE="$idx" git -C "$work" write-tree)
fin=$(git -C "$work" -c user.name=t -c user.email=t@example.invalid commit-tree "$tree" -p "$tip" -m fin)
git -C "$work" push -q "file://$remote" "$fin:refs/heads/$BR" || ko "journal de fin refusé (non fast-forward ?)"
ok "journal de fin poussé par-dessus sans force"

# --- 5. démon : jeton sur stdin, instantanés réguliers, arrêt propre sur SIGTERM -------------
export LIVE_STATE="$tmp/state2" LIVE_RUN=43
printf 'journal du démon\n' > "$LIVE_LOG"
printf '%s\n' "$fake_token" | LIVE_TOKEN_STDIN=1 LIVE_FIRST=1 LIVE_INTERVAL=2 "$here/livelog.sh" daemon > "$tmp/daemon.out" 2>&1 &
pid=$!
for _ in $(seq 1 40); do [ "$(grep -c 'envoyé (clair)' "$tmp/daemon.out" 2>/dev/null)" -ge 2 ] && break; sleep 0.5; done
[ "$(grep -c 'envoyé (clair)' "$tmp/daemon.out")" -ge 2 ] || ko "le démon n'a pas poussé deux instantanés"
kill -TERM "$pid"
for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
kill -0 "$pid" 2>/dev/null && { kill -KILL "$pid"; ko "le démon ne s'arrête pas sur SIGTERM"; }
grep -q 'arrêté' "$tmp/daemon.out" || ko "arrêt non signalé"
ok "démon : instantanés toutes les 2 s, arrêt propre sur SIGTERM"

# --- 5b. remote https : faux git (aucun réseau) qui vérifie comment le jeton arrive --------
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
printf 'journal https\n' > "$LIVE_LOG"
printf '%s\n' "$fake_token" | PATH="$shim:$PATH" LIVE_STATE="$tmp/state4" LIVE_RUN=45 \
  LIVE_REMOTE=https://github.com/LordThiouk/antenly.git LIVE_TOKEN_STDIN=1 "$here/livelog.sh" snapshot > "$out" 2>&1
grep -q 'envoyé (clair)' "$out" || ko "push https simulé en échec : $(cat "$out")"
grep -qF -- "$fake_token" "$tmp/push.argv" && ko "jeton dans les arguments de git"
grep -q 'https://github.com/LordThiouk/antenly.git' "$tmp/push.argv" || ko "URL inattendue"
grep -q '@github.com' "$tmp/push.argv" && ko "identifiants dans l'URL"
want="http.https://github.com/.extraheader AUTHORIZATION: basic $(printf 'x-access-token:%s' "$fake_token" | base64 -w0)"
[ "$(cat "$tmp/push.hdr")" = "$want" ] || ko "en-tête d'authentification absent ou inattendu"
rm -f "$tmp/push.argv" "$tmp/push.hdr"
ok "remote https : jeton passé à git par son environnement seul (ni argument, ni URL)"

# --- 6. le jeton n'apparaît nulle part -------------------------------------------------------
grep -rqaF -- "$fake_token" "$tmp/state" "$tmp/state2" "$tmp/state4" "$tmp/daemon.out" "$out" "$remote" && ko "jeton retrouvé dans la sortie ou l'état"
ok "jeton absent des sorties, de l'état et du dépôt"

# --- 7. root : lecture du journal avec les droits de l'utilisateur ---------------------------
if sudo -n true 2>/dev/null; then
  sudo -n sh -c "umask 077; echo secret-root > '$tmp/root-only'"
  ln -sf "$tmp/root-only" "$tmp/link.log"
  sudo -n env -i PATH="$(dirname "$gl"):/usr/local/bin:/usr/bin:/bin" LIVE_STATE="$tmp/state3" LIVE_LOG="$tmp/link.log" \
    LIVE_JOB=testjob LIVE_RUN=44 LIVE_REMOTE="file://$remote" LIVE_GITLEAKS="$gl" \
    LIVE_READ_UID="$(id -u)" LIVE_READ_GID="$(id -g)" "$here/livelog.sh" snapshot 2>&1 | cat > "$out"
  grep -q 'illisible' "$out" || ko "root a lu un fichier interdit à l'utilisateur : $(cat "$out")"
  git -C "$remote" rev-parse -q --verify refs/heads/fullrun-logs/testjob-44 >/dev/null && ko "branche créée malgré tout"
  sudo -n rm -rf "$tmp/root-only" "$tmp/state3"
  ok "en root : lien vers un fichier root refusé (lecture avec les droits du run)"
else
  echo "SKIP cas root (sudo indisponible)"
fi

echo "PASS livelog : clair, chiffré, échec borné, fin par-dessus, démon, jeton jamais exposé"
