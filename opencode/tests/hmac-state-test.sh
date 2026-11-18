#!/usr/bin/env bash
# Steps « Sauvegarder l'état FullRun » (id: save_state) et « Restaurer l'état FullRun » (id:
# restore_state) du workflow opencode-fullrun.yml : extrait les deux scripts bash embarqués (via
# python+yaml, comme chain-step-test.sh et start-step-test.sh) et les exécute avec un vrai tar/HOME
# isolé et un `gh` de rechange, pour prouver que la signature HMAC protège vraiment l'artefact
# d'état : une bonne signature passe, une signature fausse ou une archive modifiée après signature
# est refusée SANS extraction, et une clé ISA_STAMP_KEY absente/vide échoue avec un message
# explicite et distinct — jamais la valeur de la clé elle-même, dans aucun des deux steps.
#   opencode/tests/hmac-state-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WF="$HERE/../../.github/workflows/opencode-fullrun.yml"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { echo "OK   $*"; }; ko() { echo "FAIL $*"; fail=1; }

REAL_KEY="cle-secrete-de-test-ne-jamais-afficher-9f3e7a"

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
  [ -f "$T/fake_artifact/state.tar" ] && cp "$T/fake_artifact/state.tar" "\$dir/state.tar"
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
  rm -rf "$T/home" "$T/restore_log" "$T/gh_delete_called"
  mkdir -p "$T/home"
  env -i PATH="$T/fakes:/usr/bin:/bin" HOME="$T/home" RUNNER_TEMP="$T/runnertmp-restore" \
    GITHUB_REPOSITORY="LordThiouk/antenly-ci" IN_JOB=job1 \
    "$@" bash "$T/restore.sh" >"$T/restore_log" 2>&1
  echo $?
}

state_restored() { [ -s "$T/home/.claude/LIFEOS/MEMORY/STATE/fullrun/marker" ]; }

# --- A. save_state, clé présente, état non vide : signature produite, has_state=true ---------------
mkdir -p "$T/home/.claude/LIFEOS/MEMORY/STATE/fullrun"
echo contenu > "$T/home/.claude/LIFEOS/MEMORY/STATE/fullrun/marker"
rc=$(run_save ISA_STAMP_KEY="$REAL_KEY")
[ "$rc" = 0 ] && ok "save_state : clé présente ⇒ exit 0" || ko "save_state exit=$rc : $(cat "$T/save_log")"
grep -qx "has_state=true" "$T/save_out" 2>/dev/null && ok "save_state : has_state=true" || ko "has_state absent/faux : $(cat "$T/save_out")"
dir=$(grep '^dir=' "$T/save_out" | cut -d= -f2-)
[ -s "$dir/state.tar" ] && [ -s "$dir/state.sig" ] && ok "save_state : state.tar + state.sig produits" \
  || ko "tar/sig manquants dans $dir"
! grep -q "$REAL_KEY" "$T/save_log" && ok "save_state : la clé n'apparaît jamais dans la sortie du step" \
  || ko "la clé apparaît dans la sortie de save_state !"
mkdir -p "$T/fake_artifact"
cp "$dir/state.tar" "$T/fake_artifact/state.tar"
cp "$dir/state.sig" "$T/fake_artifact/state.sig"

# --- B. restore_state, même clé, artefact intact : signature vérifiée, état restauré ----------------
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999)
[ "$rc" = 0 ] && ok "restore_state : signature correcte ⇒ exit 0" || ko "restore_state exit=$rc : $(cat "$T/restore_log")"
state_restored && ok "restore_state : signature correcte ⇒ état restauré (round-trip save→restore OK)" \
  || ko "état non restauré malgré une signature correcte : $(cat "$T/restore_log")"
grep -q "État FullRun restauré" "$T/restore_log" && ok "restore_state : message de restauration présent" \
  || ko "message de restauration absent : $(cat "$T/restore_log")"
[ -s "$T/gh_delete_called" ] && ok "restore_state : artefact supprimé après usage (à usage unique)" \
  || ko "suppression de l'artefact non appelée"
! grep -q "$REAL_KEY" "$T/restore_log" && ok "restore_state : la clé n'apparaît jamais dans la sortie du step" \
  || ko "la clé apparaît dans la sortie de restore_state !"

# --- C. restore_state, archive modifiée APRÈS signature : signature invalide, aucune extraction ----
cp "$T/fake_artifact/state.tar" "$T/fake_artifact/state.tar.orig"
printf 'octet-ajoute-apres-signature' >> "$T/fake_artifact/state.tar"
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999)
[ "$rc" = 0 ] && ok "restore_state : archive modifiée ⇒ exit 0 (cold start, jamais un échec dur)" \
  || ko "restore_state exit=$rc : $(cat "$T/restore_log")"
state_restored && ko "archive modifiée : état restauré quand même !" \
  || ok "restore_state : archive modifiée après signature ⇒ aucune extraction"
grep -q "signature invalide ou archive illisible" "$T/restore_log" && ok "restore_state : message « signature invalide » (générique, pas « clé absente »)" \
  || ko "message attendu absent : $(cat "$T/restore_log")"
cp "$T/fake_artifact/state.tar.orig" "$T/fake_artifact/state.tar"

# --- D. restore_state, signature fausse (hex aléatoire, même archive) : rejetée, aucune extraction -
printf '%064x' 1 > "$T/fake_artifact/state.sig"
rc=$(run_restore GH_TOKEN=x ISA_STAMP_KEY="$REAL_KEY" PREV_RUN_ID=999)
state_restored && ko "signature fausse : état restauré quand même !" \
  || ok "restore_state : signature fausse ⇒ aucune extraction"
grep -q "signature invalide ou archive illisible" "$T/restore_log" && ok "restore_state : signature fausse ⇒ même message générique" \
  || ko "message attendu absent : $(cat "$T/restore_log")"
# resigne correctement pour les cas suivants
cp "$dir/state.sig" "$T/fake_artifact/state.sig"

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
