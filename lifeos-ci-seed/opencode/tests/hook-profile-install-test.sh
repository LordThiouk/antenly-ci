#!/usr/bin/env bash
# Installation du profil hook-profiles/fullrun.json depuis le checkout LifeOS :
# copie vers dir/hook-profiles (chemin lu par le plugin), refus si un garde-fou
# est dans disable, et le workflow appelle bien le script.
#   opencode/tests/hook-profile-install-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(cd "$here/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"

bin="$here/install-hook-profile.sh"
yml="$root/.github/workflows/opencode-fullrun.yml"
[ -x "$bin" ] || ko "install-hook-profile.sh absent ou non exécutable"
[ -f "$yml" ] || ko "opencode-fullrun.yml absent"

grep -q 'install-hook-profile.sh' "$yml" || ko "le workflow n'appelle pas install-hook-profile.sh"
# Appel depuis le checkout LifeOS vers la config opencode
grep -E -q 'install-hook-profile\.sh"[[:space:]]+"\$L"[[:space:]]+"\$C"' "$yml" \
  || grep -E -q 'install-hook-profile\.sh[[:space:]]+"\$L"[[:space:]]+"\$C"' "$yml" \
  || ko "le workflow doit appeler install-hook-profile.sh \"\$L\" \"\$C\""
ok "workflow installe hook-profiles depuis le checkout LifeOS"

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

mk_lifeos() {
  # $1 = contenu JSON de fullrun.json
  local d="$tmp/lifeos"
  rm -rf "$d"
  mkdir -p "$d/opencode/hook-profiles" "$d/opencode/plugins"
  printf '%s\n' "$1" > "$d/opencode/hook-profiles/fullrun.json"
  printf '%s\n' "$d"
}

mk_dest() {
  local d="$tmp/config"
  rm -rf "$d"
  mkdir -p "$d/plugins"
  printf '%s\n' "$d"
}

good='{"disable":["EventLogger.hook.ts","AgentInvocation.hook.ts"]}'
life=$(mk_lifeos "$good")
dest=$(mk_dest)
out=$("$bin" "$life" "$dest" 2>&1) || ko "profil secondaire légitime refusé : $out"
[ -f "$dest/hook-profiles/fullrun.json" ] || ko "fullrun.json non copié"
[ -f "$dest/plugins/../hook-profiles/fullrun.json" ] || ko "chemin plugins/../hook-profiles/fullrun.json illisible"
ok "profil légitime copié, lisible depuis plugins/"

# Garde-fou nu
life=$(mk_lifeos '{"disable":["EventLogger.hook.ts","PreToolGuard"]}')
dest=$(mk_dest)
if "$bin" "$life" "$dest" >/dev/null 2>"$tmp/err"; then
  ko "un disable PreToolGuard aurait dû échouer"
fi
grep -q 'garde-fous' "$tmp/err" && grep -q 'PreToolGuard' "$tmp/err" \
  || ko "le refus d'un garde-fou n'est pas signalé : $(cat "$tmp/err")"
[ ! -e "$dest/hook-profiles" ] || ko "une copie a été faite malgré un garde-fou coupé"
ok "refus PreToolGuard, aucune copie"

# Garde-fou avec suffixe .hook.ts
life=$(mk_lifeos '{"disable":["Safety.hook.ts"]}')
dest=$(mk_dest)
if "$bin" "$life" "$dest" >/dev/null 2>"$tmp/err"; then
  ko "un disable Safety.hook.ts aurait dû échouer"
fi
grep -q 'Safety.hook.ts' "$tmp/err" || ko "Safety.hook.ts non mentionné : $(cat "$tmp/err")"
ok "refus Safety.hook.ts"

# Fichier manquant
rm -rf "$tmp/lifeos-empty"
mkdir -p "$tmp/lifeos-empty/opencode"
dest=$(mk_dest)
if "$bin" "$tmp/lifeos-empty" "$dest" >/dev/null 2>"$tmp/err"; then
  ko "un checkout sans hook-profiles aurait dû échouer"
fi
grep -qi 'hook-profiles' "$tmp/err" || ko "absence de hook-profiles mal signalée : $(cat "$tmp/err")"
ok "échec si hook-profiles est absent du checkout LifeOS"

# JSON invalide
life=$(mk_lifeos '{"nope":[]}')
dest=$(mk_dest)
if "$bin" "$life" "$dest" >/dev/null 2>"$tmp/err"; then
  ko "un JSON sans disable aurait dû échouer"
fi
ok "échec si fullrun.json est invalide"

# Usage
if "$bin" >/dev/null 2>"$tmp/err"; then
  ko "sans arguments le script devrait rendre 2"
fi
rc=0
"$bin" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || ko "usage attendu exit 2 (rc=$rc)"
ok "usage : exit 2"

echo "PASS hook-profile-install : copie LifeOS, chemin plugin, refus des garde-fous"
