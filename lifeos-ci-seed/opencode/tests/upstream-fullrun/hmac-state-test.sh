#!/usr/bin/env bash
# Steps « Sauvegarder l'état FullRun » (id: save_state) et « Restaurer l'état FullRun » (id:
# restore_state) du workflow opencode-fullrun.yml : extrait les deux scripts bash embarqués (via
# python+yaml, comme chain-step-test.sh et start-step-test.sh) et les exécute avec un vrai tar/HOME
# isolé et un `gh` de rechange, pour prouver que la signature HMAC protège vraiment l'artefact
# d'état : une bonne signature passe, une signature fausse ou un chiffré modifié après signature
# est refusé SANS extraction, et une clé ISA_STAMP_KEY absente/vide échoue avec un message
# explicite et distinct — jamais la valeur de la clé elle-même, dans aucun des deux steps.
# Depuis la revue 2 (point 2), l'artefact publié est CHIFFRÉ (AES-256-CBC, clé dérivée de
# ISA_STAMP_KEY) : ce test vérifie aussi qu'aucun tar en clair n'est produit/publié, que le
# round-trip save→restore fonctionne, et qu'un déchiffrement en échec (chiffré corrompu mais
# correctement re-signé) est refusé sans extraction.
#   opencode/tests/hmac-state-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WF="$HERE/../../.github/workflows/opencode-fullrun.yml"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { echo "OK   $*"; }; ko() { echo "FAIL $*"; fail=1; }

# Clés générées à l'exécution (jamais de valeur en dur, même factice).
REAL_KEY="canari-$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"

# --- extraction des deux scripts depuis le YAML (jamais une copie figée) ---------------------------
python3 - "$WF" "$T/save.sh" "$T/restore.sh" <<'PY'
import sys, yaml
wf, out_save, out_restore = sys.argv[1], sys.argv[2], sys.argv[3]
y = yaml.safe_load(open(wf))
steps = y["jobs"]["fullrun"]["steps"]
header = "#!/usr/bin/env bash\nset -euo pipefail\n"

save = next(s for s in steps if s.get("id") == "save_state")
assert save["name"].startswith("Sauvegarder l'état FullRun"), "step 'save_state' renommé : adapter ce test"
open(out_save, "w").write(header + save["run"])

restore = next(s for s in steps if s.get("id") == "restore_state")
assert restore["name"].startswith("Restaurer l'état FullRun"), "step 'restore_state' renommé : adapter ce test"
open(out_restore, "w").write(header + restore["run"])
PY
chmod +x "$T/save.sh" "$T/restore.sh"

# --- chemin publié (statique, sur le YAML publié) : l'artefact uploadé est le CHIFFRÉ, jamais le tar
# en clair (dépôt public — revue 2, point 2) --------------------------------------------------------
python3 - "$WF" <<'PY' || fail=1
import sys, yaml
y = yaml.safe_load(open(sys.argv[1]))
steps = y["jobs"]["fullrun"]["steps"]
pub = next(s for s in steps if s.get("id") == "publish_state")
paths = pub["with"]["path"]
lines = [l.strip() for l in str(paths).splitlines()]
assert any(l.endswith("/state.tar.enc") for l in lines), "publish_state doit publier state.tar.enc : %r" % paths
assert not any(l.endswith("/state.tar") for l in lines), "publish_state publie encore le tar en clair : %r" % paths
print("OK   publish_state : seul l'artefact chiffré (state.tar.enc) + sa signature sont publiés")
PY

# --- gh de rechange pour restore_state : "run download" copie dans $D ce que le test a préparé dans
# $T/fake_artifact/, "api .../artifacts" renvoie un id bidon, "api -X DELETE" ne fait rien -----------
mkdir -p "$T/fakes"
cat >"$T/fakes/gh" <<S
#!/usr/bin/env bash
if [ "\$1" = run ] && [ "\$2" = download ]; then
  dir=""
  prev=""
  for a in "\$@"; do
    [ "\$prev" = --dir ] && dir="\$a"
    prev="\$a"
  done
  if [ -f "$T/download_fail" ]; then exit 1; fi
  mkdir -p "\$dir"
  [ -f "$T/fake_artifact/state.tar.enc" ] && cp "$T/fake_artifact/state.tar.enc" "\$dir/state.tar.enc"
  [ -f "$T/fake_artifact/state.sig" ] && cp "$T/fake_artifact/state.sig" "\$dir/state.sig"
  exit 0
fi
if [ "\$1" = api ]; then
  for a in "\$@"; do
    case "\$a" in *DELETE*) echo deleted >> "$T/gh_delete_called"; exit 0 ;; esac
  done
  echo '"fake-artifact-id"'
  exit 0
fi
exit 0
S
chmod +x "$T/fakes/gh"

run_save() { # variables d'environnement passées en arguments ; $T/home préparé par l'appelant
  rm -f "$T/save_out" "$T/save_log"
  mkdir -p "$T/home"
  : >"$T/save_out"
  env -i PATH="/usr/bin:/bin" HOME="$T/home" RUNNER_TEMP="$T/runnertmp-save" \
    GITHUB_OUTPUT="$T/save_out" \
    "$@" bash "$T/save.sh" >"$T/save_log" 2>&1
  echo $?
}

run_restore() { # variables d'environnement passées en arguments ; $T/fake_artifact rempli au besoin
  rm -rf "$T/home" "$T/restore_log" "$T/gh_delete_called" "$T/restore_out" "$T/restore_summary"
  mkdir -p "$T/home"
  : >"$T/restore_out"; : >"$T/restore_summary"
  # GITHUB_OUTPUT/STEP_SUMMARY réels : restore_state publie désormais un verdict
  # (status=restored|missing|refused) consommé par la gate du step chain.
  env -i PATH="$T/fakes:/usr/bin:/bin" HOME="$T/home" RUNNER_TEMP="$T/runnertmp-restore" \
    GITHUB_REPOSITORY="LordThiouk/galass-ci" IN_JOB=job1 \
    GITHUB_OUTPUT="$T/restore_out" GITHUB_STEP_SUMMARY="$T/restore_summary" \
    "$@" bash "$T/restore.sh" >"$T/restore_log" 2>&1
  echo $?
}

state_restored() { [ -s "$T/home/.claude/LIFEOS/MEMORY/STATE/fullrun/marker" ]; }

sign_with() { # $1 = fichier, $2 = clé ; la clé ne circule que par l'environnement (jamais argv)
  ISA_STAMP_KEY="$2" python3 -c "import hmac,hashlib,os,sys; key=os.environb[b'ISA_STAMP_KEY']; data=open(sys.argv[1],'rb').read(); print(hmac.new(key,data,hashlib.sha256).hexdigest())" "$1"
}

reset_artifact() { # remet dans $T/fake_artifact le chiffré et la bonne signature produits par save_state
  cp "$dir/state.tar.enc" "$T/fake_artifact/state.tar.enc"
  cp "$dir/state.sig" "$T/fake_artifact/state.sig"
}

# --- A. save_state, clé présente, état non vide : artefact CHIFFRÉ + signature, has_state=true -----
mkdir -p "$T/home/.claude/LIFEOS/MEMORY/STATE/fullrun"
echo contenu > "$T/home/.claude/LIFEOS/MEMORY/STATE/fullrun/marker"
rc=$(run_save ISA_STAMP_KEY="$REAL_KEY")
[ "$rc" = 0 ] && ok "save_state : clé présente ⇒ exit 0" || ko "save_state exit=$rc : $(cat "$T/save_log")"
grep -qx "has_state=true" "$T/save_out" 2>/dev/null && ok "save_state : has_state=true" || ko "has_state absent/faux : $(cat "$T/save_out")"
dir=$(grep '^dir=' "$T/save_out" | cut -d= -f2-)
[ -s "$dir/state.tar.enc" ] && [ -s "$dir/state.sig" ] && ok "save_state : state.tar.enc + state.sig produits" \
  || ko "state.tar.enc/sig manquants dans $dir"
# Dépôt public (revue 2, point 2) : le tar en clair ne doit jamais exister dans le dossier publié,
# et le chiffré ne doit contenir aucun fragment du clair (ici le mot « contenu » du marker).
[ ! -e "$dir/state.tar" ] && ok "save_state : state.tar en clair supprimé (jamais publié)" \
  || ko "state.tar en clair encore présent dans $dir (serait publié)"
! grep -q "contenu" "$dir/state.tar.enc" 2>/dev/null \
  && ok "save_state : le clair (contenu du marker) n'est pas lisible dans le chiffré" \
  || ko "state.tar.enc contient du clair en clair !"
! grep -q "$REAL_KEY" "$T/save_log" && ok "save_state : la clé n'apparaît jamais dans la sortie du step" \
  || ko "la clé apparaît dans la sortie de save_state !"
mkdir -p "$T/fake_artifact"
cp "$dir/state.tar.enc" "$T/fake_artifact/state.tar.enc"
cp "$dir/state.sig" "$T/fake_artifact/state.sig"

# --- B. restore_state, même clé, artefact intact : signature vérifiée, état restauré ----------------
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999)
[ "$rc" = 0 ] && ok "restore_state : signature correcte ⇒ exit 0" || ko "restore_state exit=$rc : $(cat "$T/restore_log")"
state_restored && ok "restore_state : signature correcte ⇒ état restauré (round-trip save→restore OK)" \
  || ko "état non restauré malgré une signature correcte : $(cat "$T/restore_log")"
grep -q "État FullRun restauré" "$T/restore_log" && ok "restore_state : message de restauration présent" \
  || ko "message de restauration absent : $(cat "$T/restore_log")"
grep -qx "status=restored" "$T/restore_out" && ok "restore_state : status=restored publié (gate du step chain)" \
  || ko "status=restored absent : $(cat "$T/restore_out")"
[ -s "$T/gh_delete_called" ] && ok "restore_state : artefact supprimé après usage (à usage unique)" \
  || ko "suppression de l'artefact non appelée"
! grep -q "$REAL_KEY" "$T/restore_log" && ok "restore_state : la clé n'apparaît jamais dans la sortie du step" \
  || ko "la clé apparaît dans la sortie de restore_state !"

# --- C. restore_state, chiffré modifié APRÈS signature : signature invalide, aucun déchiffrement,
# aucune extraction --------------------------------------------------------------------------------
cp "$T/fake_artifact/state.tar.enc" "$T/fake_artifact/state.tar.enc.orig"
printf 'octet-ajoute-apres-signature' >> "$T/fake_artifact/state.tar.enc"
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999)
[ "$rc" = 0 ] && ok "restore_state : chiffré modifié ⇒ exit 0 (cold start, jamais un échec dur)" \
  || ko "restore_state exit=$rc : $(cat "$T/restore_log")"
state_restored && ko "chiffré modifié : état restauré quand même !" \
  || ok "restore_state : chiffré modifié après signature ⇒ aucune extraction"
grep -q "signature invalide ou archive illisible" "$T/restore_log" && ok "restore_state : message « signature invalide » (générique, pas « clé absente »)" \
  || ko "message attendu absent : $(cat "$T/restore_log")"
grep -qx "status=refused" "$T/restore_out" && ok "restore_state : chiffré modifié ⇒ status=refused (la chaîne s'arrête)" \
  || ko "status=refused absent : $(cat "$T/restore_out")"
cp "$T/fake_artifact/state.tar.enc.orig" "$T/fake_artifact/state.tar.enc"

# --- D. restore_state, signature fausse (hex aléatoire, même archive) : rejetée, aucune extraction -
printf '%064x' 1 > "$T/fake_artifact/state.sig"
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999)
state_restored && ko "signature fausse : état restauré quand même !" \
  || ok "restore_state : signature fausse ⇒ aucune extraction"
grep -q "signature invalide ou archive illisible" "$T/restore_log" && ok "restore_state : signature fausse ⇒ même message générique" \
  || ko "message attendu absent : $(cat "$T/restore_log")"
grep -qx "status=refused" "$T/restore_out" && ok "restore_state : signature fausse ⇒ status=refused" \
  || ko "status=refused absent : $(cat "$T/restore_out")"
# resigne correctement pour les cas suivants
cp "$dir/state.sig" "$T/fake_artifact/state.sig"

# --- D2. restore_state, signature VALIDE mais produite avec une AUTRE clé (même chiffré intact) :
# même longueur de hexdigest, donc le format de la signature ne la trahit pas — seul le HMAC avec la
# vraie clé la rejette, et aucune extraction n'a lieu ------------------------------------------------
OTHER_KEY="canari-$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
sign_with "$T/fake_artifact/state.tar.enc" "$OTHER_KEY" > "$T/fake_artifact/state.sig"
other_sig=$(cat "$T/fake_artifact/state.sig")
[[ "$other_sig" =~ ^[0-9a-f]{64}$ ]] && ok "autre clé : signature au bon format (64 hex, indiscernable d'une vraie)" \
  || ko "autre clé : signature mal formée : $other_sig"
[ "$other_sig" != "$(cat "$dir/state.sig")" ] && ok "autre clé : signature bien différente de celle de la vraie clé" \
  || ko "autre clé : signature identique à la vraie — le cas ne prouverait rien"
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999)
[ "$rc" = 0 ] && ok "autre clé : exit 0 (cold start)" || ko "autre clé : exit=$rc : $(cat "$T/restore_log")"
state_restored && ko "autre clé : état restauré quand même !" \
  || ok "restore_state : signature valide d'une autre clé ⇒ aucune extraction (HMAC rejette)"
grep -qx "status=refused" "$T/restore_out" && ok "restore_state : signature d'une autre clé ⇒ status=refused" \
  || ko "status=refused absent : $(cat "$T/restore_out")"
! grep -q "$OTHER_KEY" "$T/restore_log" && ok "autre clé : aucune clé dans la sortie du step" \
  || ko "une clé apparaît dans la sortie de restore_state !"

# --- D3. restore_state, chiffré CORROMPU mais RE-SIGNÉ correctement avec la vraie clé : le HMAC
# passe, le déchiffrement échoue ⇒ status=refused, aucune extraction. Prouve que l'échec de
# déchiffrement est bien géré (pas seulement le rejet de signature des cas C/D/D2).
# Corruption : le dernier octet est RETIRÉ (longueur non multiple de 16 ⇒ openssl échoue de façon
# déterministe) — une simple substitution du dernier octet ne ferait échouer le padding PKCS#7 que
# dans ~255/256 des cas, donc un test qui échouerait parfois au hasard.
reset_artifact
truncate -s -1 "$T/fake_artifact/state.tar.enc"
sign_with "$T/fake_artifact/state.tar.enc" "$REAL_KEY" > "$T/fake_artifact/state.sig"
# Preuve que la signature posée est bien VALIDE pour ce chiffré corrompu (même calcul que le step) :
# le refus attendu ne peut donc venir que du déchiffrement, jamais d'un HMAC invalide.
sig_recalc=$(sign_with "$T/fake_artifact/state.tar.enc" "$REAL_KEY")
[ "$sig_recalc" = "$(cat "$T/fake_artifact/state.sig")" ] \
  && ok "chiffré corrompu re-signé : HMAC valide pour la vraie clé (échec attendu = déchiffrement)" \
  || ko "chiffré corrompu : la signature re-posée n'est pas valide, le cas ne prouve rien"
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999)
[ "$rc" = 0 ] && ok "chiffré corrompu re-signé : exit 0 (cold start)" || ko "chiffré corrompu : exit=$rc : $(cat "$T/restore_log")"
state_restored && ko "chiffré corrompu : état restauré quand même !" \
  || ok "restore_state : déchiffrement en échec ⇒ aucune extraction"
grep -qx "status=refused" "$T/restore_out" && ok "restore_state : déchiffrement en échec ⇒ status=refused (la chaîne s'arrête)" \
  || ko "status=refused absent : $(cat "$T/restore_out")"
! grep -q "État FullRun restauré" "$T/restore_log" \
  && ok "chiffré corrompu : jamais de message de restauration" || ko "restauration annoncée à tort"
reset_artifact

# --- E. restore_state, ISA_STAMP_KEY absente : message EXPLICITE et DISTINCT, aucune extraction,
# jamais confondu avec « signature invalide » (cas C/D) --------------------------------------------
rc=$(run_restore GH_TOKEN=x PREV_RUN_ID=999)  # ISA_STAMP_KEY non fournie
[ "$rc" = 0 ] && ok "restore_state : clé absente ⇒ exit 0 (cold start, jamais un échec dur)" \
  || ko "restore_state exit=$rc : $(cat "$T/restore_log")"
state_restored && ko "clé absente : état restauré quand même !" \
  || ok "restore_state : clé absente ⇒ aucune extraction"
grep -q "ISA_STAMP_KEY absente ou vide" "$T/restore_log" && ok "restore_state : message explicite « ISA_STAMP_KEY absente ou vide »" \
  || ko "message explicite absent : $(cat "$T/restore_log")"
! grep -q "signature invalide ou archive illisible" "$T/restore_log" && ok "restore_state : clé absente ⇒ jamais confondu avec le message « signature invalide »" \
  || ko "clé absente a déclenché le message générique au lieu du message dédié"
grep -qx "status=refused" "$T/restore_out" && ok "restore_state : clé absente ⇒ status=refused" \
  || ko "status=refused absent : $(cat "$T/restore_out")"

# --- H. restore_state, artefact introuvable (aucun état publié par le lien précédent — cas normal
# des premiers liens) : status=missing, exit 0, jamais confondu avec un refus ----------------------
touch "$T/download_fail"
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999)
rm -f "$T/download_fail"
[ "$rc" = 0 ] && ok "restore_state : artefact introuvable ⇒ exit 0 (cold start assumé)" \
  || ko "restore_state exit=$rc : $(cat "$T/restore_log")"
grep -qx "status=missing" "$T/restore_out" && ok "restore_state : artefact introuvable ⇒ status=missing (toléré par la gate)" \
  || ko "status=missing absent : $(cat "$T/restore_out")"

# --- H2 (B1). has_state=true ET téléchargement en échec (403, réseau, expiration) : ce n'est PAS une
# absence légitime. Le step échoue (exit 1), status=failed, aucun état restauré, chaîne arrêtée ------
touch "$T/download_fail"
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999 HAS_STATE_PREV=true)
rm -f "$T/download_fail"
[ "$rc" != 0 ] && ok "B1 : has_state=true + download KO ⇒ le step échoue (exit $rc), pas de cold start silencieux" \
  || ko "B1 : has_state=true + download KO accepté (exit 0) : $(cat "$T/restore_log")"
grep -qx "status=failed" "$T/restore_out" && ok "B1 : status=failed publié (la gate du step chain arrête la chaîne)" \
  || ko "B1 : status=failed absent : $(cat "$T/restore_out")"
! grep -qx "status=missing" "$T/restore_out" && ok "B1 : jamais status=missing quand l'état était attendu" \
  || ko "B1 : status=missing publié à tort"
state_restored && ko "B1 : un état a été restauré malgré l'échec" || ok "B1 : aucun état restauré"

# has_state=false + téléchargement en échec : absence légitime (rien n'avait été publié) ⇒ missing, exit 0
touch "$T/download_fail"
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999 HAS_STATE_PREV=false)
rm -f "$T/download_fail"
{ [ "$rc" = 0 ] && grep -qx "status=missing" "$T/restore_out"; } \
  && ok "B1 : has_state=false + download KO ⇒ missing toléré (absence légitime)" \
  || ko "B1 : has_state=false + download KO : rc=$rc $(cat "$T/restore_out")"

# DELETE en échec : jamais avalé en silence (warning explicite + ligne de résumé), mais pas fatal
cat >"$T/fakes/gh-del-ko" <<S
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in *DELETE*) exit 1 ;; esac; done
exec "$T/fakes/gh" "\$@"
S
chmod +x "$T/fakes/gh-del-ko"
cp "$T/fakes/gh" "$T/fakes/gh.real"; sed -i "s#exec \"$T/fakes/gh\"#exec \"$T/fakes/gh.real\"#" "$T/fakes/gh-del-ko"
mv "$T/fakes/gh" "$T/fakes/gh.keep"; cp "$T/fakes/gh-del-ko" "$T/fakes/gh"
reset_artifact
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999 HAS_STATE_PREV=true)
mv "$T/fakes/gh.keep" "$T/fakes/gh"
[ "$rc" = 0 ] && grep -q "suppression de l'artefact d'état .* en échec" "$T/restore_log" \
  && grep -q "usage unique non garanti" "$T/restore_summary" \
  && ok "B1 : DELETE en échec ⇒ warning explicite + résumé (plus avalé en silence)" \
  || ko "B1 : DELETE en échec silencieux : rc=$rc log=$(cat "$T/restore_log")"

# Statique : actions: write déclaré (sans lui, DELETE répond 403)
python3 - "$WF" <<'PY' || fail=1
import sys, yaml
y = yaml.safe_load(open(sys.argv[1]))
perms = y["permissions"]
assert perms.get("actions") == "write", "permissions.actions doit valoir write (restore_state supprime l'artefact) : %r" % perms
assert perms.get("contents") == "read", "contents doit rester read : %r" % perms
print("OK   B1 : permissions = contents: read + actions: write")
PY

# --- F. save_state, ISA_STAMP_KEY absente : échec explicite (exit 1), jamais de signature produite,
# jamais la clé affichée (vide ici, donc rien à masquer, mais le message ne doit rien contenir de
# sensible) -------------------------------------------------------------------------------------------
rm -rf "$T/home"; mkdir -p "$T/home/.claude/LIFEOS/MEMORY/STATE/fullrun"
echo contenu > "$T/home/.claude/LIFEOS/MEMORY/STATE/fullrun/marker"
rc=$(run_save)  # ISA_STAMP_KEY non fournie
[ "$rc" = 1 ] && ok "save_state : clé absente ⇒ exit 1 (échec explicite, jamais une signature avec clé vide)" \
  || ko "save_state exit=$rc (attendu 1) : $(cat "$T/save_log")"
grep -q "ISA_STAMP_KEY absente ou vide" "$T/save_log" && ok "save_state : message explicite « ISA_STAMP_KEY absente ou vide »" \
  || ko "message explicite absent : $(cat "$T/save_log")"
! grep -qx "has_state=true" "$T/save_out" 2>/dev/null && ok "save_state : clé absente ⇒ has_state jamais mis à true" \
  || ko "has_state=true écrit malgré la clé absente"

# --- G. save_state, dossier d'état absent/vide : rien à signer, exit 0, has_state=false (cas normal,
# distinct du cas « clé absente » — pas de régression du comportement existant) ----------------------
rm -rf "$T/home"; mkdir -p "$T/home"
rc=$(run_save ISA_STAMP_KEY="$REAL_KEY")
[ "$rc" = 0 ] && ok "save_state : dossier d'état vide ⇒ exit 0 (rien à signer, pas un échec)" \
  || ko "save_state exit=$rc : $(cat "$T/save_log")"
grep -qx "has_state=false" "$T/save_out" 2>/dev/null && ok "save_state : dossier d'état vide ⇒ has_state=false" \
  || ko "has_state=false attendu : $(cat "$T/save_out")"

exit $fail
