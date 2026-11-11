#!/usr/bin/env bash
# Test local du journal chiffré quand gitleaks bloque le push : un dépôt avec un faux jeton
# GitHub (généré ici) doit être bloqué, l'archive .age produite, et la clé privée de la box doit
# la déchiffrer. La clé privée n'est utilisée que par `age -d -i`, jamais affichée ni copiée.
#   opencode/tests/leaklog-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
key="${AGE_KEY:-$HOME/.config/age/fullrun-logs.key}"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
gl=$(find_gitleaks "$tmp") || ko "gitleaks introuvable"
ok "gitleaks : $("$gl" version 2>/dev/null | head -n1)"
command -v age >/dev/null || ko "age absent"
tok=$(fake_ghp)

# --- 1. dépôt piège : gitleaks (mode git, comme le step de contrôle) doit bloquer ----------
repo="$tmp/repo"
git init -q "$repo" || ko "git init"
printf 'GITHUB_TOKEN = "%s"\n' "$tok" > "$repo/config.py"
{ git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q -m "ajout config"; } \
  || ko "commit piège"
report="$tmp/gitleaks.json"; rc=0
"$gl" git --no-banner --redact --report-path "$report" --log-opts=HEAD "$repo" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || ko "gitleaks n'a pas bloqué (code $rc, 1 attendu)"
ok "gitleaks bloque le faux jeton ghp_ (exit 1)"
jq -e '[.[] | select(.File | test("config\\.py$"))] | length >= 1' "$report" >/dev/null || ko "rapport sans le fichier fautif"
grep -qF -- "$tok" "$report" && ko "valeur du secret dans le rapport gitleaks"
ok "rapport gitleaks : fichier, ligne, règle ; valeur masquée"

# --- 2. journal masqué + archive chiffrée --------------------------------------------------
raw="$tmp/opencode.log"
printf '[suivi] run de test\ntoken = %s\nfin du journal\n' "$tok" > "$raw"
red="$tmp/log.redacted"
OC_ISA_KEY_FILE=/dev/null OC_LOG_MAX=1048576 "$here/redact-log.sh" "$raw" "$red" || ko "redact-log.sh en échec"
grep -qF -- "$tok" "$red" && ko "journal masqué contient encore le jeton"
ok "journal masqué (jeton retiré)"
out="$tmp/artifact"
f=$("$here/leaklog.sh" "$red" "$report" testjob 123456789 "$out" gitleaks \
     "https://example.invalid/run/1" "fullrun/test" "0123456789abcdef0123456789abcdef01234567") || ko "leaklog.sh en échec"
[ "$f" = "$out/fullrun-log-testjob-123456789.age" ] || ko "nom d'archive inattendu : $f"
[ "$(ls -A "$out")" = "fullrun-log-testjob-123456789.age" ] || ko "autre fichier que l'archive dans la sortie"
[ "$(head -c 21 "$f")" = "age-encryption.org/v1" ] || ko "ce n'est pas une archive age"
grep -qaF -- "fin du journal" "$f" && ko "texte du journal visible dans l'archive"
ok "archive chiffrée : $(basename "$f") ($(wc -c < "$f") octets), rien en clair"

# --- 3. déchiffrement avec la clé privée de la box -----------------------------------------
[ -f "$key" ] || ko "clé privée absente : déchiffrement non vérifiable"
mkdir -p "$tmp/x"
age -d -i "$key" "$f" | tar -xz -C "$tmp/x" || ko "age -d ou tar en échec"
for n in opencode.log gitleaks.json meta.txt; do [ -s "$tmp/x/$n" ] || ko "$n manquant"; done
grep -qF "fin du journal" "$tmp/x/opencode.log" || ko "journal déchiffré incomplet"
grep -rqF -- "$tok" "$tmp/x" && ko "secret en clair dans l'archive déchiffrée"
jq -e 'length >= 1 and (.[0] | keys == ["Commit","Description","EndLine","File","RuleID","StartLine"])' \
  "$tmp/x/gitleaks.json" >/dev/null || ko "rapport déchiffré : champs inattendus"
ok "age -d -i ~/.config/age/fullrun-logs.key déchiffre : journal + rapport (fichier/ligne/règle seulement)"

# --- 4. destinataire invalide : échec propre, aucun fichier ---------------------------------
rm -rf "$out"
OC_LOG_RECIPIENT=pas-une-cle "$here/leaklog.sh" "$red" - testjob 1 "$out" gitleaks >/dev/null 2>&1 && ko "accepte un destinataire invalide"
[ ! -e "$out/fullrun-log-testjob-1.age" ] || ko "archive écrite malgré l'erreur"
ok "destinataire invalide refusé, rien écrit"

echo "PASS leaklog : gitleaks bloque, archive .age produite et déchiffrable, aucun secret en clair"
