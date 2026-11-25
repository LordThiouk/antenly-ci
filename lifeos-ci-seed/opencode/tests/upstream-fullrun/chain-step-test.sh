#!/usr/bin/env bash
# Step « Décision de chaînage (chain_enabled) » du workflow opencode-fullrun.yml : extrait le script
# bash embarqué (via python+yaml, comme start-step-test.sh le fait pour la garde) et l'exécute avec
# des GITHUB_OUTPUT/GITHUB_STEP_SUMMARY réels et des bun/gh/jq contrôlés, pour prouver B1 (gate
# check/push avant toute lecture d'état), M1 (OC_STOP vide = arrêt), le hors-un (chain_max), M3
# (next/prev_run_id transmis au dispatch), le DISPATCH_TOKEN jamais dans l'env de bun, l'ordre des
# steps save_state/publish_state avant chain (statique, sur le YAML) et la gate correspondante
# (échec de l'un ou l'autre ⇒ zéro dispatch, jamais masqué par un redispatch à l'aveugle).
#   opencode/tests/chain-step-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WF="$HERE/../../../.github/workflows/opencode-fullrun.yml"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok() { echo "OK   $*"; }; ko() { echo "FAIL $*"; fail=1; }

# --- extraction du script du step « chain » depuis le YAML (jamais une copie figée dans ce test :
# toujours le script réellement publié) ------------------------------------------------------------
# Le script est repris TEL QUEL, sans aucune substitution : son `export PATH` durci est donc
# réellement exercé. C'est voulu — la version précédente de ce test remplaçait la ligne PATH par
# `$FAKES_DIR:$PATH`, ce qui rendait bun trouvable et faisait passer le test alors que la CI cassait
# (bun installé par setup-bun dans ~/.bun/bin, hors du PATH durci). Les outils de rechange (bun, gh)
# sont donc posés dans `$HOME/.bun/bin` du HOME jetable du test — exactement l'emplacement réel — et
# les cas ci-dessous échouent si le script cesse d'y chercher bun.
python3 - "$WF" "$T/chain.sh" <<'PY'
import sys, yaml
wf, out = sys.argv[1], sys.argv[2]
y = yaml.safe_load(open(wf))
steps = y["jobs"]["fullrun"]["steps"]
step = next(s for s in steps if s.get("id") == "chain")
assert step["name"].startswith("Décision de chaînage"), "step 'chain' renommé : adapter ce test"
# défaults.run.shell du workflow = "bash --noprofile --norc -euo pipefail {0}" : répliqué ici,
# jamais une variante plus permissive qui masquerait un bug qui ne se voit que sous -e/-u/pipefail.
open(out, "w").write("#!/usr/bin/env bash\nset -euo pipefail\n" + step["run"])
PY
chmod +x "$T/chain.sh"

# --- ordre des steps (ce correctif) : save_state et publish_state doivent précéder chain dans le
# YAML — jamais après, pour que l'artefact existe déjà quand le lien suivant, une fois dispatché par
# chain, tente de le restaurer (sinon course : le lien suivant peut démarrer et tenter la restauration
# avant que ce lien-ci ait fini de publier son propre artefact) --------------------------------------
python3 - "$WF" <<'PY' || fail=1
import sys, yaml
y = yaml.safe_load(open(sys.argv[1]))
steps = y["jobs"]["fullrun"]["steps"]
ids = [s.get("id") for s in steps]
i_save = ids.index("save_state")
i_pub = ids.index("publish_state")
i_chain = ids.index("chain")
assert i_save < i_chain, "save_state doit précéder chain (ordre actuel : %r)" % ids
assert i_pub < i_chain, "publish_state doit précéder chain (ordre actuel : %r)" % ids
assert i_save < i_pub, "save_state doit précéder publish_state"
print("OK   ordre : save_state puis publish_state, tous deux avant chain")
PY

# --- bun/gh de rechange, pilotés par des fichiers dans $T — posés dans $HOME/.bun/bin du HOME
# jetable (l'emplacement réel de setup-bun), pour que le PATH durci du script les trouve ------------
mkdir -p "$T/home/.bun/bin"
cat >"$T/home/.bun/bin/bun" <<S
#!/usr/bin/env bash
echo "\$DISPATCH_TOKEN" > "$T/bun_saw_dispatch_token"  # vide si -u DISPATCH_TOKEN a fonctionné
echo called >> "$T/bun_called"
cat "$T/bun_output.json"
S
cat >"$T/home/.bun/bin/gh" <<S
#!/usr/bin/env bash
if [ "\$1" = workflow ] && [ "\$2" = run ]; then
  echo "\$@" > "$T/gh_dispatch_args"
  [ -f "$T/gh_dispatch_fail" ] && exit 1
  exit 0
fi
exit 0
S
chmod +x "$T/home/.bun/bin"/*
export FAKES_DIR="$T/home/.bun/bin"

run_chain() { # variables d'environnement passées en arguments ; bun_output.json doit déjà exister
  rm -f "$T/out" "$T/summary" "$T/bun_called" "$T/bun_saw_dispatch_token" "$T/gh_dispatch_args"
  : >"$T/out"; : >"$T/summary"; : >"$T/err"
  # SAVE_STATE_OUTCOME/HAS_STATE/PUBLISH_STATE_OUTCOME : défauts "cas normal, rien à sauvegarder"
  # (save_state réussi mais dossier d'état vide ⇒ has_state=false ⇒ publish_state "skipped" par sa
  # propre condition, jamais un échec) — les tests B1/M1/hors-un/M3 ci-dessus ne touchent pas à ces
  # variables et doivent continuer de dispatcher normalement ; seuls les tests dédiés ci-dessous les
  # surchargent pour vérifier la nouvelle gate (ordre des steps : save_state/publish_state avant chain).
  env -i PATH="$PATH" HOME="$T/home" FAKES_DIR="$FAKES_DIR" GITHUB_OUTPUT="$T/out" GITHUB_STEP_SUMMARY="$T/summary" \
    GITHUB_REF_NAME=fullrun-job-chain GITHUB_WORKSPACE="$T" \
    ANTENLY_DIR="$T/antenly" LIFEOS_DIR="$T/lifeos" \
    IN_BRANCH=feat-x IN_JOB=job1 IN_PROMPT=prompts:p.md IN_PROMPT_BUILD=prompts:b.md \
    IN_PROMPT_VERIFY=prompts:v.md IN_PROMPT_CLOSE=prompts:c.md IN_LIFEOS_REF=main \
    OC_MODEL_MAIN=opencode/m-free OC_MODEL_MAX=opencode/x-free \
    OC_MODEL_CHAIN=opencode/f-free IN_AGENT_IDLE_MIN= IN_IDLE_MIN=20 IN_DONE_AGENTS=Max \
    IN_WIP_PUSH_MIN=30 IN_HF_CORPUS= OC_ISA_PATH="MEMORY/WORK/x/ISA.md" \
    IN_CHAIN_PHASE=build IN_CHAIN_PROGRESS=0/20 IN_PREV_RUN_ID= RUN_ID=111000 \
    RESTORE_STATE_OUTCOME= RESTORE_STATE_STATUS= \
    DISPATCH_TOKEN=secrettoken123 \
    SAVE_STATE_OUTCOME=success HAS_STATE=false PUBLISH_STATE_OUTCOME=skipped \
    "$@" bash "$T/chain.sh" 2>"$T/err"
}

out_eq() { grep -qx "$1=$2" "$T/out" 2>/dev/null; }

mkdir -p "$T/antenly/MEMORY/WORK/x"
: >"$T/antenly/MEMORY/WORK/x/ISA.md"
printf '%s\n' '{"exit":"suite_a_faire","reason":"ok","next":"t2"}' > "$T/bun_output.json"

# --- B1 : check en échec ⇒ block=true, AVANT toute lecture d'état (bun jamais appelé) --------------
run_chain OC_STOP=ok CHECK_OUTCOME=failure CHECK_REASON=gitleaks PUSH_OUTCOME=success
out_eq block true && ok "B1 : check en échec ⇒ block=true" || ko "B1 check-échec : $(cat "$T/out")"
[ ! -f "$T/bun_called" ] && ok "B1 : état ISA jamais lu (bun non appelé) quand check a échoué" || ko "B1 : bun appelé malgré check en échec"
grep -q "reason=.*gitleaks" "$T/out" 2>/dev/null && ok "B1 : raison du check propagée" || ko "B1 : raison absente : $(cat "$T/out")"

# --- B1 : push en échec ⇒ block=true, bun jamais appelé --------------------------------------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=failure
out_eq block true && ok "B1 : push en échec ⇒ block=true" || ko "B1 push-échec : $(cat "$T/out")"
[ ! -f "$T/bun_called" ] && ok "B1 : état ISA jamais lu quand push a échoué" || ko "B1 : bun appelé malgré push en échec"

# --- B1 : push skipped (jamais lancé, ex. check KO en amont) ⇒ aussi block=true --------------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=skipped
out_eq block true && ok "B1 : push skipped ⇒ block=true (jamais traité comme un succès)" || ko "B1 push-skipped : $(cat "$T/out")"

# --- B1 : check et push au vert ⇒ la décision continue normalement (bun appelé) --------------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success
[ -f "$T/bun_called" ] && ok "B1 : check et push au vert ⇒ état ISA lu normalement" || ko "B1 : bun jamais appelé alors que check/push au vert"
out_eq continue true && ok "B1 : chaîne continue quand tout est vert" || ko "B1 : continue absent : $(cat "$T/out")"

# --- M1 : OC_STOP vide (step oc tué par GitHub avant d'écrire sa sortie) ⇒ arrêt, jamais ignoré ----
run_chain OC_STOP= CHECK_OUTCOME=success PUSH_OUTCOME=success
out_eq block true && ok "M1 : OC_STOP vide ⇒ block=true (jamais un dispatch à l'aveugle)" || ko "M1 OC_STOP vide : $(cat "$T/out")"
[ ! -f "$T/bun_called" ] && ok "M1 : OC_STOP vide ⇒ état ISA jamais lu" || ko "M1 : bun appelé malgré OC_STOP vide"

# --- hors-un chain_max : count+1 == max ⇒ bloqué (strict <, jamais <=) ------------------------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success IN_CHAIN_PROGRESS=19/20
out_eq block true && ok "hors-un : chain_count+1 == chain_max ⇒ bloqué (strict <)" || ko "hors-un : $(cat "$T/out")"
grep -q "chain_max atteint" "$T/out" 2>/dev/null && ok "hors-un : raison nommée" || ko "hors-un : raison absente : $(cat "$T/out")"

# --- DISPATCH_TOKEN jamais dans l'env de bun (env -u DISPATCH_TOKEN) -------------------------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success IN_CHAIN_PROGRESS=0/20
[ -f "$T/bun_saw_dispatch_token" ] && [ -z "$(cat "$T/bun_saw_dispatch_token")" ] \
  && ok "DISPATCH_TOKEN absent de l'environnement de bun" || ko "DISPATCH_TOKEN visible par bun : $(cat "$T/bun_saw_dispatch_token" 2>/dev/null)"

# --- ordre des steps (ce correctif) : save_state en échec ⇒ block=true, zéro dispatch --------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success \
  SAVE_STATE_OUTCOME=failure HAS_STATE=false PUBLISH_STATE_OUTCOME=skipped
out_eq block true && ok "save_state en échec ⇒ block=true (artefact non fiable)" || ko "save_state échec : $(cat "$T/out")"
[ ! -f "$T/gh_dispatch_args" ] && ok "save_state en échec ⇒ zéro dispatch (gh workflow run jamais appelé)" \
  || ko "save_state échec : dispatch quand même envoyé : $(cat "$T/gh_dispatch_args")"

# --- publication en échec (has_state=true, donc publish_state a vraiment tourné) ⇒ block=true,
# zéro dispatch : jamais un prev_run_id envoyé dont l'artefact n'existe pas ou n'est pas fiable ------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success \
  SAVE_STATE_OUTCOME=success HAS_STATE=true PUBLISH_STATE_OUTCOME=failure
out_eq block true && ok "publish_state en échec (has_state=true) ⇒ block=true" || ko "publish_state échec : $(cat "$T/out")"
[ ! -f "$T/gh_dispatch_args" ] && ok "publish_state en échec ⇒ zéro dispatch" \
  || ko "publish_state échec : dispatch quand même envoyé : $(cat "$T/gh_dispatch_args")"

# --- has_state=false ⇒ publish_state "skipped" par sa propre condition (rien à publier) : ce n'est
# PAS un échec (premiers liens avant tout état runtime) — le dispatch doit continuer normalement -----
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success \
  SAVE_STATE_OUTCOME=success HAS_STATE=false PUBLISH_STATE_OUTCOME=skipped
out_eq continue true && ok "publish_state skipped (has_state=false) ⇒ dispatch normal (pas un échec)" \
  || ko "has_state=false à tort bloqué : $(cat "$T/out")"

# --- save_state + publish_state réussis (has_state=true) ⇒ dispatch normal -------------------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success \
  SAVE_STATE_OUTCOME=success HAS_STATE=true PUBLISH_STATE_OUTCOME=success
out_eq continue true && ok "save_state + publish_state réussis (has_state=true) ⇒ dispatch normal" \
  || ko "succès à tort bloqué : $(cat "$T/out")"

# --- restauration de l'état du lien précédent : un artefact REFUSÉ (signature invalide, clé
# absente, archive illisible) arrête la chaîne — jamais un cold start silencieux qui pourrait refaire
# ou sauter une tâche ------------------------------------------------------------------------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success IN_PREV_RUN_ID=4242 \
  RESTORE_STATE_OUTCOME=success RESTORE_STATE_STATUS=refused
out_eq block true && ok "restore_state refusé ⇒ block=true" || ko "restore refusé : $(cat "$T/out")"
[ ! -f "$T/gh_dispatch_args" ] && ok "restore_state refusé ⇒ zéro dispatch" \
  || ko "restore refusé : dispatch quand même envoyé : $(cat "$T/gh_dispatch_args")"

# --- restauration ABSENTE (aucun artefact pour ce run : cas normal des premiers liens, qui n'ont
# aucun état runtime à transmettre) : tolérée, le dispatch continue ---------------------------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success IN_PREV_RUN_ID=4242 \
  RESTORE_STATE_OUTCOME=success RESTORE_STATE_STATUS=missing
out_eq continue true && ok "restore_state missing (premier lien sans état) ⇒ dispatch normal" \
  || ko "restore missing à tort bloqué : $(cat "$T/out")"

# --- restore_state planté (outcome ≠ success) alors que prev_run_id est fourni ⇒ block -------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success IN_PREV_RUN_ID=4242 \
  RESTORE_STATE_OUTCOME=failure RESTORE_STATE_STATUS=
out_eq block true && ok "restore_state en échec (prev_run_id fourni) ⇒ block=true" \
  || ko "restore en échec : $(cat "$T/out")"

# --- sans prev_run_id, le step restore_state est « skipped » par sa propre condition : aucune gate
# de restauration ne doit s'appliquer (premier lien d'une chaîne) -----------------------------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success IN_PREV_RUN_ID= \
  RESTORE_STATE_OUTCOME=skipped RESTORE_STATE_STATUS=
out_eq continue true && ok "sans prev_run_id ⇒ restore_state ignoré, dispatch normal" \
  || ko "premier lien à tort bloqué : $(cat "$T/out")"

# --- M3 : next (phase build, reste en build) transmis au dispatch, prev_run_id = ce run ------------
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success IN_CHAIN_PROGRESS=0/20 RUN_ID=999777
args=$(cat "$T/gh_dispatch_args" 2>/dev/null || echo "")
[[ "$args" == *"-f next=t2"* ]] && ok "M3 : next=t2 transmis au dispatch (reste en build)" || ko "M3 next absent/faux : $args"
[[ "$args" == *"-f prev_run_id=999777"* ]] && ok "B2 : prev_run_id=ce run transmis au dispatch" || ko "B2 prev_run_id absent/faux : $args"

# --- M3 : changement de phase (build -> verify, next=5) : next NON imposé à la nouvelle phase ------
printf '%s\n' '{"exit":"suite_a_faire","reason":"ok","next":"5"}' > "$T/bun_output.json"
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success IN_CHAIN_PROGRESS=0/20
args=$(cat "$T/gh_dispatch_args" 2>/dev/null || echo "")
[[ "$args" == *"-f chain_phase=verify"* ]] && ok "M3 : changement de phase build->verify détecté" || ko "phase inattendue : $args"
[[ "$args" == *"-f next="* && "$args" != *"-f next=5"* ]] && ok "M3 : next non imposé à la nouvelle phase (vide)" || ko "M3 : next=5 imposé à tort à verify : $args"

# --- kind = echec : bloqué, raison propagée --------------------------------------------------------
printf '%s\n' '{"exit":"echec","reason":"timeout agent"}' > "$T/bun_output.json"
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success
out_eq block true && ok "kind=echec : bloqué" || ko "kind=echec : $(cat "$T/out")"
grep -q "timeout agent" "$T/out" 2>/dev/null && ok "kind=echec : raison propagée" || ko "raison absente : $(cat "$T/out")"

# --- kind = termine : chaîne terminée, jamais bloquée (block=false) --------------------------------
printf '%s\n' '{"exit":"termine","reason":"run clos"}' > "$T/bun_output.json"
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success
out_eq block false && ok "kind=termine : block=false (chaîne close, pas un échec)" || ko "kind=termine : $(cat "$T/out")"
out_eq continue false && ok "kind=termine : continue=false" || ko "kind=termine continue : $(cat "$T/out")"

# --- unit --isa illisible : kind/reason journalisés dans GITHUB_STEP_SUMMARY -----------------------
printf '%s\n' 'pas du json' > "$T/bun_output.json"
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success
out_eq block true && ok "unit --isa illisible : bloqué" || ko "illisible : $(cat "$T/out")"
grep -q "kind=" "$T/summary" 2>/dev/null && ok "unit --isa illisible : kind/reason journalisés dans le résumé" || ko "résumé sans trace : $(cat "$T/summary")"

# --- unit --isa illisible : la sortie BRUTE n'est JAMAIS recrachée en entier dans un log public
# (dépôt public — revue 2, point 1). Le jeton est GÉNÉRÉ à l'exécution, jamais une valeur fixe ici.
# Doit vérifier : jetons masqués, sauts de ligne repliés (une ligne « ::… » injectée deviendrait une
# workflow command), « :: » échappé et troncature à exactement 400 caractères.
tok=$(printf 'ghp_%s' "$(head -c 256 /dev/urandom | base64 -w0 | tr -dc 'A-Za-z0-9' | head -c 36)")
{
  printf '%s\n' "$tok"
  # Run de 600 alphanumériques : avalé par la règle « 40+ caractères de jeton » du masquage.
  head -c 600 /dev/zero | tr '\0' 'A'
  printf '\n::warning::injecte\n'
  # Remplissage SANS run de 40+ caractères de la classe [A-Za-z0-9_+/=-] (les points cassent les
  # runs) : une fois le reste masqué, il reste bien plus de 400 caractères — la troncature est donc
  # réellement exercée, sinon la dernière assertion ne prouverait rien.
  python3 -c "import sys; sys.stdout.write('ab.ab' * 150)"
} > "$T/bun_output.json"
run_chain OC_STOP=ok CHECK_OUTCOME=success PUSH_OUTCOME=success
out_eq block true && ok "safe_raw : unit --isa illisible ⇒ bloqué" || ko "safe_raw : $(cat "$T/out")"
grep -qF "::error::unit --isa sortie illisible" "$T/err" \
  && ok "safe_raw : message d'erreur présent sur stderr" || ko "safe_raw : message absent : $(cat "$T/err")"
! grep -qF "$tok" "$T/err" \
  && ok "safe_raw : le jeton généré n'apparaît jamais dans le log" || ko "safe_raw : fuite du jeton dans stderr"
grep -qF "[REDACTED]" "$T/err" \
  && ok "safe_raw : motifs de jeton masqués ([REDACTED])" || ko "safe_raw : aucun marqueur de masquage : $(cat "$T/err")"
raw_len=$(python3 - "$T/err" <<'PY'
import sys
line = next(l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8", errors="replace")
            if "::error::unit --isa sortie illisible" in l)
print(len(line.split(" : ", 1)[1]))
PY
)
[ "$raw_len" = 400 ] \
  && ok "safe_raw : partie brute tronquée à exactement 400 caractères" \
  || ko "safe_raw : troncature attendue à 400 caractères (obtenu « $raw_len »)"
! grep -q '^::warning::injecte' "$T/err" \
  && ok "safe_raw : aucune workflow command injectée en début de ligne (newlines repliées)" \
  || ko "safe_raw : injection « ::warning:: » en début de ligne : $(cat "$T/err")"



# --- step « guard » : même hors-un (chain_count == chain_max) bloqué dès la garde, avant le step oc,
# et le motif ^[0-9]{1,3}$ plafonne déjà chain_count à 999 (le second contrôle -gt 999 retiré, mort,
# ne change rien d'observable) -----------------------------------------------------------------------
python3 - "$WF" "$T/guard.sh" <<'PY'
import sys, yaml
wf, out = sys.argv[1], sys.argv[2]
y = yaml.safe_load(open(wf))
steps = y["jobs"]["fullrun"]["steps"]
step = next(s for s in steps if s.get("id") == "guard")
open(out, "w").write("#!/usr/bin/env bash\nset -euo pipefail\n" + step["run"])
PY
chmod +x "$T/guard.sh"
run_guard() {
  env -i PATH="/usr/bin:/bin" GITHUB_OUTPUT="$T/gout" GITHUB_ENV="$T/genv" RUNNER_TEMP="$T" \
    IN_BRANCH=feat-x IN_JOB=job1 IN_PROMPT=prompts:p.md IN_LIFEOS_REF=main IN_HF_CORPUS= \
    OC_ISA_PATH="MEMORY/WORK/x/ISA.md" IN_IDLE_MIN=20 IN_AGENT_IDLE_MIN= IN_START_STEP= \
    IN_DONE_AGENTS=Max IN_WIP_PUSH_MIN=30 IN_CHAIN_PHASE=build IN_PREV_RUN_ID= IN_NEXT= \
    IN_STOP_AFTER_STEP= IN_TARGET_AGENT= \
    IN_PROMPT_BUILD=prompts:b.md IN_PROMPT_VERIFY=prompts:v.md IN_PROMPT_CLOSE=prompts:c.md \
    OC_MODEL_MAIN=opencode/m-free OC_MODEL_MAX=opencode/x-free \
    OC_MODEL_CHAIN= "$@" bash "$T/guard.sh" >"$T/guard_out" 2>&1
}
: >"$T/gout"; : >"$T/genv"
run_guard IN_CHAIN_ENABLED=true IN_CHAIN_PROGRESS=19/20
[ $? -eq 0 ] && ok "garde : chain_count=19 < chain_max=20 accepté" || ko "garde : 19<20 refusé : $(cat "$T/guard_out")"
run_guard IN_CHAIN_ENABLED=true IN_CHAIN_PROGRESS=20/20
rc=$?
[ "$rc" -ne 0 ] && grep -q "dépasse déjà chain_max" "$T/guard_out" && ok "garde : hors-un corrigé — chain_count==chain_max refusé (strict <)" \
  || ko "garde : chain_count==chain_max accepté à tort (rc=$rc) : $(cat "$T/guard_out")"
run_guard IN_CHAIN_ENABLED=true IN_CHAIN_PROGRESS=1000/20
rc=$?
[ "$rc" -ne 0 ] && grep -q "chain_progress invalide" "$T/guard_out" && ok "garde : chain_count=1000 toujours refusé (format rejeté, >3 chiffres)" \
  || ko "garde : chain_count=1000 : $(cat "$T/guard_out")"

exit $fail
