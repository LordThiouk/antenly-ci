#!/usr/bin/env bash
# Tests de opencode/split-diff.sh : jamais un fichier coupé en deux morceaux, un fichier seul plus
# gros que le seuil reste un morceau à lui seul, diff vide -> un seul morceau vide, manifest.txt
# correct, codes de sortie (64 entrée invalide, 0 ok).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SD="$HERE/../split-diff.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "ok $1"; pass=$((pass + 1)); }
ko() { echo "ko $1"; fail=$((fail + 1)); }

mkfile_diff() { # $1=nom $2=nb_lignes -> écrit un faux diff --git pour un fichier de N lignes de contenu
  local name="$1" n="$2" i
  printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -0,0 +1,%d @@\n' "$name" "$name" "$name" "$name" "$n"
  for ((i = 0; i < n; i++)); do printf '+ligne %d\n' "$i"; done
}

# --- 1. entrée invalide (64) ---
out=$(bash "$SD" --out-dir "$T/o1" --max-lines 5 </dev/null 2>&1); rc=$?
[ "$rc" -eq 64 ] || true  # max-lines=5 < 10 -> invalide
bash "$SD" --max-lines 800 </dev/null >/tmp/.sd1 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "1a --out-dir manquant -> 64" || ko "1a rc=$rc"
bash "$SD" --out-dir "$T/o1b" --max-lines 5 </dev/null >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "1b --max-lines trop petit -> 64" || ko "1b rc=$rc"

# --- 2. diff vide -> un seul morceau vide, jamais zéro morceau ---
rm -rf "$T/o2"
: | bash "$SD" --out-dir "$T/o2" --max-lines 100 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -f "$T/o2/chunk-0001.diff" ] && [ ! -s "$T/o2/chunk-0001.diff" ] \
  && [ ! -f "$T/o2/chunk-0002.diff" ] \
  && ok "2 diff vide -> un seul morceau vide" || ko "2 [$(ls "$T/o2" 2>/dev/null)]"

# --- 3. petit diff (un seul fichier, sous le seuil) -> un seul morceau ---
rm -rf "$T/o3"
mkfile_diff fichierA.txt 5 | bash "$SD" --out-dir "$T/o3" --max-lines 100 >/dev/null 2>&1
[ -f "$T/o3/chunk-0001.diff" ] && [ ! -f "$T/o3/chunk-0002.diff" ] \
  && grep -q "diff --git a/fichierA.txt" "$T/o3/chunk-0001.diff" \
  && ok "3 petit diff -> un seul morceau, fichier intact" || ko "3 [$(ls "$T/o3" 2>/dev/null)]"

# --- 4. gros diff multi-fichiers -> plusieurs morceaux, AUCUN fichier coupé en deux ---
rm -rf "$T/o4"
{ mkfile_diff gros1.txt 60; mkfile_diff gros2.txt 60; mkfile_diff gros3.txt 60; } \
  | bash "$SD" --out-dir "$T/o4" --max-lines 100 >/dev/null 2>&1
n_chunks=$(ls "$T/o4"/chunk-*.diff 2>/dev/null | wc -l)
[ "$n_chunks" -ge 2 ] && ok "4a gros diff -> plusieurs morceaux ($n_chunks)" || ko "4a un seul morceau ($n_chunks) pour 3 fichiers de 60 lignes avec seuil 100"
# Chaque fichier (son "diff --git") n'apparaît que dans UN SEUL morceau.
split_ok=1
for f in gros1.txt gros2.txt gros3.txt; do
  count=$(grep -l "diff --git a/$f " "$T/o4"/chunk-*.diff 2>/dev/null | wc -l)
  [ "$count" -eq 1 ] || { split_ok=0; ko "4b $f apparaît dans $count morceau(x) (attendu 1)"; }
done
[ "$split_ok" -eq 1 ] && ok "4b chaque fichier dans exactement un morceau, jamais coupé en deux"

# --- 5. UN SEUL fichier plus gros que le seuil : reste un morceau à lui seul, jamais tronqué -------
rm -rf "$T/o5"
mkfile_diff enorme.txt 500 | bash "$SD" --out-dir "$T/o5" --max-lines 100 >/dev/null 2>&1
n_chunks5=$(ls "$T/o5"/chunk-*.diff 2>/dev/null | wc -l)
[ "$n_chunks5" -eq 1 ] && ok "5a un seul fichier > seuil -> reste un seul morceau (jamais tronqué)" || ko "5a $n_chunks5 morceaux"
lines5=$(wc -l < "$T/o5/chunk-0001.diff")
[ "$lines5" -gt 100 ] && ok "5b le morceau garde TOUT le fichier ($lines5 lignes, > seuil 100)" || ko "5b $lines5 lignes (fichier tronqué ?)"

# --- 6. manifest.txt : une ligne par morceau, nombre de lignes et noms de fichiers cohérents ------
rm -rf "$T/o6"
{ mkfile_diff a.txt 10; mkfile_diff b.txt 10; } | bash "$SD" --out-dir "$T/o6" --max-lines 100 >/dev/null 2>&1
[ -f "$T/o6/manifest.txt" ] && grep -q "chunk-0001.diff" "$T/o6/manifest.txt" \
  && grep -q "a.txt" "$T/o6/manifest.txt" && grep -q "b.txt" "$T/o6/manifest.txt" \
  && ok "6 manifest.txt présent et nomme les fichiers du morceau" || ko "6 [$(cat "$T/o6/manifest.txt" 2>/dev/null)]"

# --- 7. --source fichier (pas seulement stdin) -------------------------------------------------
rm -rf "$T/o7"
mkfile_diff c.txt 5 > "$T/in7.diff"
bash "$SD" --out-dir "$T/o7" --max-lines 100 --source "$T/in7.diff" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -f "$T/o7/chunk-0001.diff" ] && grep -q "c.txt" "$T/o7/chunk-0001.diff" \
  && ok "7 --source fichier fonctionne (pas seulement stdin)" || ko "7 rc=$rc"
bash "$SD" --out-dir "$T/o7b" --max-lines 100 --source "$T/absent.diff" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 64 ] && ok "7b --source introuvable -> 64" || ko "7b rc=$rc"

echo "résumé : $pass ok, $fail ko"
[ "$fail" -eq 0 ]
