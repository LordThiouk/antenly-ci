#!/usr/bin/env bash
# Test du journal chiffré quand gitleaks bloque le push : un dépôt avec un faux jeton GitHub
# (généré ici) doit être bloqué, l'archive .age produite, et la clé privée correspondante doit la
# déchiffrer. Sur la box, la clé est ~/.config/age/fullrun-logs.key (destinataire du dépôt) ;
# en CI elle n'existe pas, donc le test fabrique une paire jetable et chiffre pour elle : le
# déchiffrement reste vérifié partout. La clé n'est jamais affichée ni copiée hors du $tmp.
#   opencode/tests/leaklog-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
key="${AGE_KEY:-$HOME/.config/age/fullrun-logs.key}"
# Destinataire : celui du dépôt sur la box, une clé jetable ailleurs (CI sans clé privée).
rcp_env=()
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

# --- 2b. journal > MAX : tronqué AVANT perl, milieu omis, canaris début/fin gardés ----------
big="$tmp/big.log"; bred="$tmp/big.redacted"
head_c="CANARY-DEBUT-$(rand_alnum 12)"; mid_c="MILIEU-A-SUPPRIMER-$(rand_alnum 12)"; tail_c="CANARY-FIN-$(rand_alnum 12)"
{ printf '%s\n' "$head_c"; head -c 5000 /dev/zero | tr '\0' 'a'; printf '\n%s\n' "$mid_c";
  head -c 5000 /dev/zero | tr '\0' 'b'; printf '\n%s\n' "$tail_c"; } > "$big"
MAX=2000
OC_ISA_KEY_FILE=/dev/null OC_LOG_MAX=$MAX "$here/redact-log.sh" "$big" "$bred" || ko "redact-log.sh (gros journal) en échec"
[ "$(wc -c < "$bred")" -le "$MAX" ] || ko "journal masqué > MAX ($(wc -c < "$bred") > $MAX)"
grep -qF -- "$mid_c" "$bred" && ko "milieu non omis malgré la troncature"
grep -qF -- "$head_c" "$bred" || ko "canari de début perdu"
grep -qF -- "$tail_c" "$bred" || ko "canari de fin perdu"
grep -q 'journal tronqué' "$bred" || ko "bandeau de troncature absent"
h=$(grep -n 'head -c' "$here/redact-log.sh" | head -n1 | cut -d: -f1)
p=$(grep -n 'perl -0777' "$here/redact-log.sh" | grep -v ':#' | head -n1 | cut -d: -f1)
[ -n "$h" ] && [ -n "$p" ] && [ "$h" -lt "$p" ] || ko "troncature non placée avant perl ($h/$p)"
ok "journal > MAX : tronqué avant perl, milieu omis, canaris début/fin gardés"
if [ ! -f "$key" ]; then
  age-keygen -o "$tmp/jetable.key" >/dev/null 2>&1 || ko "age-keygen en échec"
  key="$tmp/jetable.key"
  rcp_env=(OC_LOG_RECIPIENT="$(age-keygen -y "$key")")
  ok "clé privée absente : paire age jetable pour vérifier le déchiffrement"
fi
out="$tmp/artifact"
f=$(env "${rcp_env[@]}" "$here/leaklog.sh" "$red" "$report" testjob 123456789 "$out" gitleaks \
     "https://example.invalid/run/1" "fullrun/test" "0123456789abcdef0123456789abcdef01234567") || ko "leaklog.sh en échec"
[ "$f" = "$out/fullrun-log-testjob-123456789.age" ] || ko "nom d'archive inattendu : $f"
[ "$(ls -A "$out")" = "fullrun-log-testjob-123456789.age" ] || ko "autre fichier que l'archive dans la sortie"
[ "$(head -c 21 "$f")" = "age-encryption.org/v1" ] || ko "ce n'est pas une archive age"
grep -qaF -- "fin du journal" "$f" && ko "texte du journal visible dans l'archive"
ok "archive chiffrée : $(basename "$f") ($(wc -c < "$f") octets), rien en clair"

# --- 3. déchiffrement avec la clé privée (celle de la box, ou la jetable) -------------------
[ -f "$key" ] || ko "clé privée absente : déchiffrement non vérifiable"
mkdir -p "$tmp/x"
age -d -i "$key" "$f" | tar -xz -C "$tmp/x" || ko "age -d ou tar en échec"
for n in opencode.log gitleaks.json meta.txt; do [ -s "$tmp/x/$n" ] || ko "$n manquant"; done
grep -qF "fin du journal" "$tmp/x/opencode.log" || ko "journal déchiffré incomplet"
grep -rqF -- "$tok" "$tmp/x" && ko "secret en clair dans l'archive déchiffrée"
jq -e 'length >= 1 and (.[0] | keys == ["Commit","Description","EndLine","File","RuleID","StartLine"])' \
  "$tmp/x/gitleaks.json" >/dev/null || ko "rapport déchiffré : champs inattendus"
ok "age -d -i <clé privée> déchiffre : journal + rapport (fichier/ligne/règle seulement)"

# --- 4. destinataire invalide : échec propre, aucun fichier ---------------------------------
rm -rf "$out"
OC_LOG_RECIPIENT=pas-une-cle "$here/leaklog.sh" "$red" - testjob 1 "$out" gitleaks >/dev/null 2>&1 && ko "accepte un destinataire invalide"
[ ! -e "$out/fullrun-log-testjob-1.age" ] || ko "archive écrite malgré l'erreur"
ok "destinataire invalide refusé, rien écrit"

echo "PASS leaklog : gitleaks bloque, archive .age produite et déchiffrable, aucun secret en clair"
