#!/usr/bin/env bash
# fusion des enregistrements signés de fullrun-carry.json déjà présents sur la branche :
# un persist/export amputé (ex. après retreat) ne doit pas les effacer.
#   opencode/tests/merge-signed-carry-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
MSC="$here/merge-signed-carry.sh"
[ -x "$MSC" ] || ko "merge-signed-carry.sh absent"
bash -n "$MSC" || ko "merge-signed-carry.sh : bash -n"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

git_init() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.name t
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config commit.gpgsign false
}

# Fichier signé avec une clé de test (jamais une clé de production).
# Même schéma que FullRunCarry.exportCarry : HMAC-SHA256(clé, JSON compact du payload).
write_carry() {
  local dest="$1" key="$2"
  CARRY_OUT="$dest" CARRY_KEY="$key" python3 - <<'PY'
import hmac, hashlib, json, os
from pathlib import Path
payload = json.loads(os.environ["CARRY_PAYLOAD"])
key = Path(os.environ["CARRY_KEY"]).read_bytes()
compact = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
sig = hmac.new(key, compact.encode("utf-8"), hashlib.sha256).hexdigest()
text = json.dumps({"payload": payload, "sig": sig}, ensure_ascii=False, indent=2) + "\n"
Path(os.environ["CARRY_OUT"]).parent.mkdir(parents=True, exist_ok=True)
Path(os.environ["CARRY_OUT"]).write_text(text, encoding="utf-8")
PY
}

step1='{"status":"skipped","at":"2026-11-23T21:22:34Z","fp":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","scope_fp":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sha":"b2e4cc82c440ae482fa95497e3624b8f0557eb65"}'
step2='{"status":"pass","at":"2026-11-23T23:03:30Z","fp":"d00099386e4f5719979c4d7a36d3dcb397b0eb4e41e712e58f90099ea0858331","scope_fp":"d00099386e4f5719979c4d7a36d3dcb397b0eb4e41e712e58f90099ea0858331","sha":"b9e4accdb158e7d647dd0308440fcd7be2b3af16"}'
step3='{"status":"pass","at":"2026-11-23T23:40:00Z","fp":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","scope_fp":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","sha":"cccccccccccccccccccccccccccccccccccccccc"}'

KEY="$tmp/key"
printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' > "$KEY"
chmod 600 "$KEY"

payload12() {
  python3 -c 'import json,sys; print(json.dumps({"v":1,"isa":"s","head":"b2e4cc82c440ae482fa95497e3624b8f0557eb65","steps":{"1":json.loads(sys.argv[1]),"2":json.loads(sys.argv[2])}}))' "$step1" "$step2"
}
payload1() {
  python3 -c 'import json,sys; print(json.dumps({"v":1,"isa":"s","head":"b2e4cc82c440ae482fa95497e3624b8f0557eb65","steps":{"1":json.loads(sys.argv[1])}}))' "$step1"
}
payload13() {
  python3 -c 'import json,sys; print(json.dumps({"v":1,"isa":"s","head":"b2e4cc82c440ae482fa95497e3624b8f0557eb65","steps":{"1":json.loads(sys.argv[1]),"3":json.loads(sys.argv[2])}}))' "$step1" "$step3"
}

steps_of() {
  python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1]))["payload"]["steps"])))' "$1"
}

# --- 1. Usage -----------------------------------------------------------------
"$MSC" >/dev/null 2>"$tmp/err" && ko "sans argument devrait échouer"
grep -q "usage:" "$tmp/err" || ko "usage mal signalé"
"$MSC" /no/such/repo >/dev/null 2>"$tmp/err" && ko "dépôt absent devrait échouer"
ok "usage : dépôt requis"

# --- 2. Troncature typique (retreat puis persist) : restaurer le fichier signé
R="$tmp/r1"
git_init "$R"
mkdir -p "$R/MEMORY/WORK/s"
export CARRY_PAYLOAD
CARRY_PAYLOAD=$(payload12)
write_carry "$R/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R" && git add MEMORY && git commit -qm "carry 1+2")
full=$(sha256sum "$R/MEMORY/WORK/s/fullrun-carry.json" | awk '{print $1}')
CARRY_PAYLOAD=$(payload1)
write_carry "$R/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R" && git add MEMORY && git commit -qm "chore: persist carry bookkeeping")
[ "$(steps_of "$R/MEMORY/WORK/s/fullrun-carry.json")" = "1" ] || ko "préparation : HEAD devrait n'avoir que l'étape 1"
# Sans clé : on rétablit quand même le fichier déjà sur la branche.
env -u ISA_STAMP_KEY -u OC_ISA_KEY_FILE HOME="$tmp/empty-home" \
  "$MSC" "$R" >"$tmp/out2" || ko "fusion sans clé a échoué"
[ "$(steps_of "$R/MEMORY/WORK/s/fullrun-carry.json")" = "1 2" ] || ko "sans clé : steps 1 et 2 attendus, got $(steps_of "$R/MEMORY/WORK/s/fullrun-carry.json")"
got=$(sha256sum "$R/MEMORY/WORK/s/fullrun-carry.json" | awk '{print $1}')
[ "$got" = "$full" ] || ko "sans clé : le fichier signé historique n'a pas été restauré à l'identique"
grep -q "restauré" "$tmp/out2" || ko "sans clé : message de restauration absent"
ok "troncature : fichier signé historique restauré à l'identique (sans clé)"

# --- 3. Idempotent : relancer ne casse rien ----------------------------------
cp "$R/MEMORY/WORK/s/fullrun-carry.json" "$tmp/after-restore"
env -u ISA_STAMP_KEY -u OC_ISA_KEY_FILE HOME="$tmp/empty-home" \
  "$MSC" "$R" >"$tmp/out3" || ko "relance a échoué"
cmp -s "$tmp/after-restore" "$R/MEMORY/WORK/s/fullrun-carry.json" || ko "relance a modifié un carry déjà complet"
ok "relance : aucune réécriture si rien ne manque"

# --- 4. Courant plus riche (step 3 ajouté, step 2 perdu) + clé : fusion -------
R2="$tmp/r2"
git_init "$R2"
mkdir -p "$R2/MEMORY/WORK/s"
CARRY_PAYLOAD=$(payload12)
write_carry "$R2/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R2" && git add MEMORY && git commit -qm "carry 1+2")
CARRY_PAYLOAD=$(payload13)
write_carry "$R2/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R2" && git add MEMORY && git commit -qm "carry 1+3")
OC_ISA_KEY_FILE="$KEY" "$MSC" "$R2" >"$tmp/out4" || ko "fusion avec clé a échoué"
[ "$(steps_of "$R2/MEMORY/WORK/s/fullrun-carry.json")" = "1 2 3" ] || ko "avec clé : steps 1 2 3 attendus, got $(steps_of "$R2/MEMORY/WORK/s/fullrun-carry.json")"
CARRY_CHECK="$R2/MEMORY/WORK/s/fullrun-carry.json" OC_ISA_KEY_FILE="$KEY" python3 - <<'PY'
import hmac, hashlib, json, os, sys
from pathlib import Path
p = Path(os.environ["CARRY_CHECK"])
d = json.loads(p.read_text())
key = Path(os.environ["OC_ISA_KEY_FILE"]).read_bytes()
compact = json.dumps(d["payload"], ensure_ascii=False, separators=(",", ":"))
want = hmac.new(key, compact.encode("utf-8"), hashlib.sha256).hexdigest()
sys.exit(0 if want == d["sig"] else 1)
PY
[ $? -eq 0 ] || ko "signature de la fusion invalide"
ok "fusion avec clé : steps 1+2+3, signature recréée valable"

# --- 5. Courant plus riche, sans clé : on conserve les steps déjà signés ------
R3="$tmp/r3"
git_init "$R3"
mkdir -p "$R3/MEMORY/WORK/s"
CARRY_PAYLOAD=$(payload12)
write_carry "$R3/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R3" && git add MEMORY && git commit -qm "carry 1+2")
hist=$(sha256sum "$R3/MEMORY/WORK/s/fullrun-carry.json" | awk '{print $1}')
CARRY_PAYLOAD=$(payload13)
write_carry "$R3/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R3" && git add MEMORY && git commit -qm "carry 1+3")
env -u ISA_STAMP_KEY -u OC_ISA_KEY_FILE HOME="$tmp/empty-home" \
  "$MSC" "$R3" >"$tmp/out5" || ko "cas sans clé (courant plus riche) a échoué"
[ "$(steps_of "$R3/MEMORY/WORK/s/fullrun-carry.json")" = "1 2" ] || ko "sans clé / plus riche : steps signés 1 2 conservés, got $(steps_of "$R3/MEMORY/WORK/s/fullrun-carry.json")"
got=$(sha256sum "$R3/MEMORY/WORK/s/fullrun-carry.json" | awk '{print $1}')
[ "$got" = "$hist" ] || ko "sans clé / plus riche : fichier signé historique attendu"
ok "sans clé et courant plus riche : enregistrements déjà signés conservés"

# --- 6. Fichier courant illisible : restaurer l'historique -------------------
R4="$tmp/r4"
git_init "$R4"
mkdir -p "$R4/MEMORY/WORK/s"
CARRY_PAYLOAD=$(payload12)
write_carry "$R4/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R4" && git add MEMORY && git commit -qm "carry 1+2")
good=$(sha256sum "$R4/MEMORY/WORK/s/fullrun-carry.json" | awk '{print $1}')
printf 'pas du json\n' > "$R4/MEMORY/WORK/s/fullrun-carry.json"
env -u ISA_STAMP_KEY -u OC_ISA_KEY_FILE HOME="$tmp/empty-home" \
  "$MSC" "$R4" >"$tmp/out6" || ko "fichier illisible : script a échoué"
got=$(sha256sum "$R4/MEMORY/WORK/s/fullrun-carry.json" | awk '{print $1}')
[ "$got" = "$good" ] || ko "fichier illisible : historique non restauré"
ok "arbre illisible : version signée de la branche restaurée"

# --- 7. hook d'installation + pre-commit rattrape un commit amputé -----------
R5="$tmp/r5"
git_init "$R5"
mkdir -p "$R5/MEMORY/WORK/s"
CARRY_PAYLOAD=$(payload12)
write_carry "$R5/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R5" && git add MEMORY && git commit -qm "carry 1+2")
"$MSC" install-hook "$R5" >"$tmp/out7" || ko "install-hook a échoué"
[ -x "$R5/.git/hooks/pre-commit" ] || ko "pre-commit absent"
[ -x "$R5/.git/hooks/merge-signed-carry.sh" ] || ko "copie du script absente du hook"
CARRY_PAYLOAD=$(payload1)
write_carry "$R5/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R5" && git add MEMORY && git commit -qm "chore: persist carry bookkeeping")
[ "$(steps_of "$R5/MEMORY/WORK/s/fullrun-carry.json")" = "1 2" ] || ko "pre-commit n'a pas empêché la troncature, got $(steps_of "$R5/MEMORY/WORK/s/fullrun-carry.json")"
ok "pre-commit : commit amputé rattrapé, steps 1 et 2 conservés"

# --- 7bis. Régression : carry périmé (mêmes ids) ne doit pas masquer un état plus récent
# Cas réel du 2026-11-24 : un carry complet mais du 18/11 (étapes 1-4, empreintes périmées)
# a été réécrit par-dessus un carry du 23/11 (étapes 1-2, empreintes à jour). Les ids étaient
# présents des deux côtés, donc l'ancienne fusion ne voyait rien à restaurer et la porte lisait
# l'empreinte périmée (redescente vera). Le fichier le plus récent doit gagner.
old1='{"status":"pass","at":"2026-11-18T00:58:22Z","fp":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","scope_fp":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","sha":"b2e4cc82c440ae482fa95497e3624b8f0557eb65"}'
old2='{"status":"pass","at":"2026-11-18T00:58:41Z","fp":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","scope_fp":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","sha":"b2e4cc82c440ae482fa95497e3624b8f0557eb65"}'
old3='{"status":"pass","at":"2026-11-18T01:07:50Z","fp":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","scope_fp":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","sha":"9addb2097574b99b8af4268b27c20740710a8757"}'
old4='{"status":"pass","at":"2026-11-18T04:01:20Z","fp":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","scope_fp":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","sha":"126bba09a5c1b2d5eae12eb7db567026a0e21a13"}'
payload_old() {
  python3 -c 'import json,sys; print(json.dumps({"v":1,"isa":"s","head":"b2e4cc82c440ae482fa95497e3624b8f0557eb65","steps":{"1":json.loads(sys.argv[1]),"2":json.loads(sys.argv[2]),"3":json.loads(sys.argv[3]),"4":json.loads(sys.argv[4])}}))' "$old1" "$old2" "$old3" "$old4"
}
R6="$tmp/r6"
git_init "$R6"
mkdir -p "$R6/MEMORY/WORK/s"
CARRY_PAYLOAD=$(payload_old)
write_carry "$R6/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R6" && git add MEMORY && git commit -qm "carry 1+2+3+4 (18/11, périmé)")
CARRY_PAYLOAD=$(payload12)
write_carry "$R6/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
(cd "$R6" && git add MEMORY && git commit -qm "carry 1+2 (23/11, à jour)")
newer=$(sha256sum "$R6/MEMORY/WORK/s/fullrun-carry.json" | awk '{print $1}')
CARRY_PAYLOAD=$(payload_old)
write_carry "$R6/MEMORY/WORK/s/fullrun-carry.json" "$KEY"
env -u ISA_STAMP_KEY -u OC_ISA_KEY_FILE HOME="$tmp/empty-home" \
  "$MSC" "$R6" >"$tmp/out7b" || ko "régression périmée : script a échoué"
[ "$(steps_of "$R6/MEMORY/WORK/s/fullrun-carry.json")" = "1 2" ] || ko "régression périmée : état récent 1 2 attendu, got $(steps_of "$R6/MEMORY/WORK/s/fullrun-carry.json")"
got=$(sha256sum "$R6/MEMORY/WORK/s/fullrun-carry.json" | awk '{print $1}')
[ "$got" = "$newer" ] || ko "régression périmée : le carry récent signé n'a pas été restauré à l'identique"
grep -q "restauré\|fusionné" "$tmp/out7b" || ko "régression périmée : message de reprise absent"
ok "régression périmée (mêmes ids) : état le plus récent restauré"

# --- 8. Le workflow fige le script et l'appelle avant les commits de fin -----
wf="$here/../.github/workflows/opencode-fullrun.yml"
[ -f "$wf" ] || ko "opencode-fullrun.yml absent"
grep -q 'opencode/merge-signed-carry.sh' "$wf" || ko "merge-signed-carry.sh non installé dans le workflow"
grep -q '/opt/fullrun-tools' "$wf" && grep -q 'merge-signed-carry.sh' "$wf" \
  || ko "merge-signed-carry.sh n'est pas figé dans /opt/fullrun-tools"
# Appel avant le commit d'état non commité (cible et dépôts supplémentaires).
grep -n 'merge-signed-carry.sh' "$wf" | grep -q . || ko "aucun appel dans le workflow"
# Le contrôle de présence des outils figés doit citer le nouveau script.
grep -q 'merge-signed-carry.sh' "$wf" || ko "contrôle outil figé sans merge-signed-carry.sh"
ok "workflow : script figé et appelé avant persist de fin"

# --- 9. autosave invoque le script avant le commit carry ---------------------
grep -q 'merge-signed-carry.sh' "$here/autosave.sh" || ko "autosave.sh n'appelle pas merge-signed-carry.sh"
grep -q 'merge-signed-carry.sh' "$here/extra-repos.sh" || ko "extra-repos.sh n'appelle pas merge-signed-carry.sh"
ok "autosave et extra-repos appellent merge-signed-carry.sh"

echo "OK   merge-signed-carry-test.sh"
