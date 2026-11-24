#!/usr/bin/env bash
# Tests quota + models.txt (sans réseau, sans secret).
#   opencode/tests/quota-test.sh
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
quota="$here/quota.sh"
[ -x "$quota" ] || { echo "FAIL quota.sh absent : $quota" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/logs"

models="$tmp/models.txt"
cat > "$models" <<'M'
# ordre de priorité
opencode/deepseek-v4.1-flash-free

opencode/mimo-v2.6-flash-free
opencode/iceman-free
M

pass=0
ok() { pass=$((pass + 1)); }
bad() { echo "FAIL $1" >&2; exit 1; }

# models.txt valide.
bash "$quota" validate "$models" >/dev/null || bad "models.txt valide refusé"
ok

# models.txt avec un modèle non -free : refus.
badmodels="$tmp/bad.txt"
cat > "$badmodels" <<'M'
opencode/deepseek-v4.1-flash-free
opencode/premium-paid
M
if bash "$quota" validate "$badmodels" >/dev/null 2>&1; then
  bad "models.txt avec modèle payant accepté"
fi
ok

run_next() {
  local rc=0 out=""
  out=$(bash "$quota" next "$@" 2>"$tmp/err") || rc=$?
  printf '%s\n' "$out"
  return "$rc"
}

# 1. Vraie erreur 429 dans le journal interne -> bascule vers le suivant.
printf '2026-11-24T10:00:00Z ERROR provider 429 Too Many Requests\n' > "$tmp/logs/oc.log"
rc=0
out=$(run_next "$models" "opencode/deepseek-v4.1-flash-free" --internal-log-dir "$tmp/logs") || rc=$?
[ "$rc" -eq 10 ] || bad "vraie erreur 429 : code $rc au lieu de 10 ($(cat "$tmp/err"))"
[ "$out" = "opencode/mimo-v2.6-flash-free" ] || bad "vraie erreur 429 : modèle suivant [$out]"
ok

# 2. Ligne d'erreur explicite (rate limit) -> bascule.
printf 'ERROR AI_APICallError: rate limit exceeded\n' > "$tmp/logs/oc2.log"
rc=0
out=$(run_next "$models" "opencode/deepseek-v4.1-flash-free" --internal-log-dir "$tmp/logs") || rc=$?
[ "$rc" -eq 10 ] || bad "rate limit : code $rc au lieu de 10"
ok

# 3. Sortie avec diff et bloc de code mentionnant quota : PAS de bascule.
outfile="$tmp/output-diff.txt"
cat > "$outfile" <<'O'
Le fichier contient le mot quota mais c'est du contenu.
diff --git a/x b/x
@@ -1 +1 @@
+ quota exceeded in a fake diff
--- quota exhausted
```
Error: quota exceeded
429 Too Many Requests
```
Fin normale.
O
rc=0
out=$(run_next "$models" "opencode/deepseek-v4.1-flash-free" --output "$outfile") || rc=$?
[ "$rc" -eq 0 ] || bad "diff/bloc de code a déclenché la bascule (code $rc, sortie [$out])"
[ -z "$out" ] || bad "diff/bloc de code : sortie inattendue [$out]"
ok

# 4. Deuxième modèle aussi épuisé -> statut quota, aucun lien suivant.
rc=0
out=$(run_next "$models" "opencode/iceman-free" --internal-log-dir "$tmp/logs") || rc=$?
[ "$rc" -eq 20 ] || bad "second modèle épuisé : code $rc au lieu de 20"
[ "$out" = "QUOTA_EXHAUSTED" ] || bad "second modèle épuisé : sortie [$out]"
ok

# 5. Sortie réelle d'erreur fournisseur -> bascule.
errout="$tmp/output-err.txt"
printf 'AI_APICallError: 429 rate limit\n' > "$errout"
rc=0
out=$(run_next "$models" "opencode/deepseek-v4.1-flash-free" --output "$errout") || rc=$?
[ "$rc" -eq 10 ] || bad "sortie erreur : code $rc au lieu de 10"
ok

# 6. La détection est bornée par --since-file : un vieux journal est ignoré.
touch -t 202001010000 "$tmp/logs/oc.log" "$tmp/logs/oc2.log"
marker="$tmp/marker"
touch "$marker"
rc=0
out=$(run_next "$models" "opencode/deepseek-v4.1-flash-free" --internal-log-dir "$tmp/logs" --since-file "$marker") || rc=$?
[ "$rc" -eq 0 ] || bad "journal antérieur au marqueur pris en compte (code $rc)"
ok

echo "PASS quota-test : $pass cas"
