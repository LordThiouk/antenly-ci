#!/usr/bin/env bash
# Outil figé preannot : déclenche le workflow preannot existant (ci.yml, job
# preannot-ina) du même dépôt, attend un verdict borné, télécharge les artefacts
# éventuels. Jetons : aucun en clair dans l'environnement d'opencode ni dans la
# sortie ; `gh` est simulé, aucun appel réseau réel, aucun vrai workflow.
#   opencode/tests/preannot-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/opencode/tests/lib.sh"

wf="$here/.github/workflows/opencode-fullrun.yml"
sh="$here/opencode/preannot.sh"
pre="$here/opencode/ci-preamble.md"
[ -f "$wf" ] || ko "workflow introuvable : $wf"
[ -x "$sh" ] || ko "preannot.sh introuvable ou non exécutable"
[ -f "$pre" ] || ko "ci-preamble.md introuvable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. intégration FullRun : installation figée, jeton root, gardes intactes -----
grep -q '\$CI_DIR/opencode/preannot.sh' "$wf" || ko "le workflow n'installe pas preannot.sh"
grep -q 'preannot.state' "$wf" || ko "état figé preannot.state absent du workflow"
grep -q 'preannot.token' "$wf" || ko "fichier de jeton preannot.token absent du workflow"
grep -q 'chmod 0600' "$wf" || ko "le jeton preannot doit être en 0600"
grep -q 'fullrun-preannot' "$wf" || ko "sudoers preannot absent"
grep -q 'preannot.sh run' "$wf" || ko "sudoers doit autoriser seulement preannot.sh run"
# Le jeton vient du GITHUB_TOKEN déjà disponible : aucun secret supplémentaire.
grep -q 'secrets.GITHUB_TOKEN' "$wf" || ko "le workflow doit utiliser GITHUB_TOKEN (aucun second jeton)"
grep -qE 'secrets\.[A-Z_]*PREANNOT[A-Z_]*' "$wf" && ko "aucun nouveau secret preannot ne doit être créé"

# Boucle d'intégrité post-run : l'outil doit y figurer.
awk '/for tool in /{print; exit}' "$wf" > "$tmp/integrity.txt"
grep -q 'preannot.sh' "$tmp/integrity.txt" || ko "preannot.sh absent de la boucle d'intégrité des outils figés"

# Permissions : le dispatch same-repo exige actions: write.
awk '/^permissions:/{p=1; print; next} p && /^[A-Za-z]/{exit} p{print}' "$wf" > "$tmp/perms.txt"
grep -q 'actions: write' "$tmp/perms.txt" || ko "permissions du FullRun : actions: write manquant"
grep -q 'contents: read' "$tmp/perms.txt" || ko "permissions : contents: read retiré (garde affaiblie)"
ok "workflow : outil figé, jeton root 0600, actions: write, boucle d'intégrité"

# Gardes FullRun non affaiblies.
for g in 'MemoryMax=' 'gitleaks' 'wippush.sh' 'done_check.sh' 'idle_minutes'; do
  grep -q -- "$g" "$wf" || ko "garde FullRun disparue : $g"
done
ok "gardes FullRun intactes (mémoire, gitleaks, wippush, done_check, silence)"

# Guidage : la commande figée, et l'interdiction de gh pour l'agent, restent écrites.
grep -q '/opt/fullrun-tools/preannot.sh' "$pre" || ko "ci-preamble.md ne cite pas l'outil figé"
grep -q 'Pas de `git push`, pas de `gh`' "$pre" || ko "l'interdiction de gh pour l'agent a été retirée"
ok "préambule : commande figée documentée, gh toujours interdit à l'agent"

# --- 2. le script ne peut pas fuir par un mode verbeux ---------------------------
grep -nE '^\s*set -x' "$sh" && ko "preannot.sh ne doit jamais activer set -x"
grep -q 'WORKFLOW="ci.yml"' "$sh" || ko "le workflow branché doit être ci.yml (preannot existant)"
grep -q 'REPO="LordThiouk/antenly-ci"' "$sh" || ko "le dépôt doit rester LordThiouk/antenly-ci"
grep -qE 'gh workflow run .*--ref' "$sh" && ko "ne pas passer --ref : la ref est l'input de ci.yml, pas celle d'antenly-ci"
ok "script : ci.yml du même dépôt, sans set -x, sans --ref"

# --- 3. run en échec : verdict, extrait borné/masqué, artefact téléchargé --------
tok="pre-tok-$(rand_alnum 24)"
printf '%s\n' "$tok" > "$tmp/token"
chmod 600 "$tmp/token"
: > "$tmp/gh.log"

cat > "$tmp/mock-gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${PREANNOT_GH_LOG:?}"
cmd="${1:-}"; shift || true
case "$cmd" in
  workflow)
    [ "${1:-}" = run ] || exit 2
    exit 0
    ;;
  api)
    path=""
    for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "$path" in
      */actions/runs/*/artifacts) printf '%s\n' '{"total_count":1,"artifacts":[{"name":"preannot"}]}' ;;
      *) exit 1 ;;
    esac
    ;;
  run)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        # Un run d'un autre ref (à ignorer) puis le nôtre : le titre fait foi.
        printf '%s\n' '[{"databaseId":111,"createdAt":"2099-01-01T00:00:00Z","displayTitle":"CI antenly@autre","url":"https://example.test/111"},{"databaseId":4242,"createdAt":"2099-01-01T00:00:00Z","displayTitle":"CI antenly@feat/multi","url":"https://example.test/4242"}]'
        ;;
      view)
        id="${1:-}"
        if printf '%s\n' "$*" | grep -q -- '--log-failed'; then
          i=1
          while [ "$i" -le 200 ]; do
            if [ "$i" -eq 195 ]; then
              echo "fail line ${i} token=${PREANNOT_FAKE_TOKEN:-secret} boom"
            else
              echo "fail line ${i} xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            fi
            i=$((i + 1))
          done
        else
          printf '%s\n' '{"status":"completed","conclusion":"failure","url":"https://example.test/4242"}'
        fi
        ;;
      download)
        id="${1:-}"; shift || true
        dest=""
        while [ $# -gt 0 ]; do
          case "$1" in -D) dest="${2:-}"; shift 2 ;; *) shift ;; esac
        done
        mkdir -p "$dest"
        printf 'junit\n' > "$dest/preannot.xml"
        ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh"

export PREANNOT_GH="$tmp/mock-gh"
export PREANNOT_GH_LOG="$tmp/gh.log"
export PREANNOT_TOKEN_FILE="$tmp/token"
export PREANNOT_FAKE_TOKEN="$tok"
export OC_BRANCH="feat/multi"
export PREANNOT_TIMEOUT_SEC=5
export PREANNOT_POLL_SEC=0
export PREANNOT_LOG_TAIL=20
export PREANNOT_LOG_WIDTH=120
export PREANNOT_ART_DIR="$tmp/art"
export GITHUB_ACTIONS=true

set +e
out=$("$sh" run 2>&1)
rc=$?
set -e
[ "$rc" -eq 1 ] || ko "run en échec simulé devrait sortir 1, obtenu $rc : $out"
printf '%s' "$out" | grep -q 'verdict=failure' || ko "verdict d'échec manquant : $out"
printf '%s' "$out" | grep -q 'run=4242' || ko "le run du bon ref (4242) doit être choisi : $out"
printf '%s' "$out" | grep -q 'extrait des logs' || ko "extrait de logs manquant en échec"
n=$(printf '%s\n' "$out" | grep -c 'fail line' || true)
[ "$n" -le 20 ] || ko "extrait trop long ($n lignes, max 20)"
printf '%s' "$out" | grep -q 'fail line 195' || ko "l'extrait devrait garder la fin du journal"
printf '%s' "$out" | grep -q 'token=\*\*\*' || ko "le jeton dans l'extrait doit être masqué"
printf '%s' "$out" | grep -Fq "$tok" && ko "jeton fuité dans la sortie"
grep -Fq "$tok" "$tmp/gh.log" && ko "jeton fuité dans les arguments de gh"
[ -f "$tmp/art/preannot-4242/preannot.xml" ] || ko "artefact non téléchargé dans le dossier du job"
printf '%s' "$out" | grep -q 'artefact : 1 téléchargé(s)' || ko "annonce d'artefact manquante : $out"
ok "run : verdict + extrait borné et masqué + artefact, sans fuite"

# Déclenchement : ci.yml, même dépôt, input ref de travail.
grep -q 'workflow run ci.yml -R LordThiouk/antenly-ci -f ref=feat/multi' "$tmp/gh.log" \
  || ko "déclenchement incorrect : $(cat "$tmp/gh.log")"
grep -q -- '--ref' "$tmp/gh.log" && ko "le déclenchement ne doit pas utiliser --ref"
ok "déclenchement : ci.yml -R antenly-ci -f ref=<branche>"

# --- 4. run en succès : pas d'extrait, artefact absent ---------------------------
cat > "$tmp/mock-gh-ok" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${PREANNOT_GH_LOG:?}"
cmd="${1:-}"; shift || true
case "$cmd" in
  workflow) exit 0 ;;
  api)
    path=""
    for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "$path" in */actions/runs/*/artifacts) printf '%s\n' '{"total_count":0,"artifacts":[]}' ;; *) exit 1 ;; esac
    ;;
  run)
    sub="${1:-}"
    case "$sub" in
      list) printf '%s\n' '[{"databaseId":7,"createdAt":"2099-01-01T00:00:00Z","displayTitle":"CI antenly@feat/multi","url":"https://example.test/7"}]' ;;
      view) printf '%s\n' '{"status":"completed","conclusion":"success","url":"https://example.test/7"}' ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh-ok"
: > "$tmp/gh.log"
out=$(PREANNOT_GH="$tmp/mock-gh-ok" "$sh" run 2>&1) || ko "run succès simulé a échoué : $out"
printf '%s' "$out" | grep -q 'verdict=success' || ko "verdict succès manquant : $out"
printf '%s' "$out" | grep -q 'extrait des logs' && ko "pas d'extrait de logs en succès"
printf '%s' "$out" | grep -q 'artefact : aucun' || ko "absence d'artefact non annoncée : $out"
ok "run : succès sans extrait, artefact absent annoncé"

# --- 5. timeout borné ------------------------------------------------------------
cat > "$tmp/mock-gh-hang" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; shift || true
case "$cmd" in
  workflow) exit 0 ;;
  run)
    sub="${1:-}"
    case "$sub" in
      list) printf '%s\n' '[{"databaseId":9,"createdAt":"2099-01-01T00:00:00Z","displayTitle":"CI antenly@feat/multi","url":"https://example.test/9"}]' ;;
      view) printf '%s\n' '{"status":"in_progress","conclusion":"","url":"https://example.test/9"}' ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh-hang"
set +e
out=$(PREANNOT_GH="$tmp/mock-gh-hang" PREANNOT_TIMEOUT_SEC=1 PREANNOT_POLL_SEC=0 "$sh" run 2>&1)
rc=$?
set -e
[ "$rc" -eq 124 ] || ko "timeout devrait sortir 124, obtenu $rc : $out"
printf '%s' "$out" | grep -q 'verdict=timeout' || ko "verdict timeout manquant : $out"
ok "run : timeout borné (124)"

# --- 6. refus : branche absente, ref invalide, hors FullRun ----------------------
if out=$(OC_BRANCH="" "$sh" run 2>&1); then ko "une branche vide aurait dû être refusée"; fi
printf '%s' "$out" | grep -q 'branche de travail manquante' || ko "refus sans message clair : $out"
if out=$(OC_BRANCH="feat/../main" "$sh" run 2>&1); then ko "une ref avec .. aurait dû être refusée"; fi
printf '%s' "$out" | grep -q 'ref refusée' || ko "refus de ref sans message clair : $out"
if out=$(OC_BRANCH="main" "$sh" run 2>&1); then ko "main aurait dû être refusé"; fi
printf '%s' "$out" | grep -q 'branche de fonctionnalité' || ko "refus de main sans message clair : $out"
set +e
out=$(env -u GITHUB_ACTIONS -u PREANNOT_GH OC_BRANCH="feat/multi" PREANNOT_TOKEN_FILE="$tmp/token" "$sh" run 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || ko "hors FullRun, l'outil aurait dû refuser"
printf '%s' "$out" | grep -q 'refus : lancer seulement depuis le FullRun' || ko "refus hors FullRun sans message clair : $out"
ok "refus : branche vide, ref invalide, main, hors FullRun"

# --- 7. verdict borné au job preannot-ina, pas au run entier ---------------------
# ci.yml porte huit jobs : un échec rust/secrets ne doit ni valider ni invalider preannot.
cat > "$tmp/mock-gh-jobs" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${PREANNOT_GH_LOG:?}"
cmd="${1:-}"; shift || true
case "$cmd" in
  workflow) exit 0 ;;
  api)
    path=""
    for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "$path" in */actions/runs/*/artifacts) printf '%s\n' '{"total_count":0,"artifacts":[]}' ;; *) exit 1 ;; esac
    ;;
  run)
    sub="${1:-}"
    case "$sub" in
      list) printf '%s\n' '[{"databaseId":55,"createdAt":"2099-01-01T00:00:00Z","displayTitle":"CI antenly@feat/multi","url":"https://example.test/55"}]' ;;
      view) printf '%s\n' '{"status":"completed","conclusion":"failure","url":"https://example.test/55","jobs":[{"name":"rust","conclusion":"failure"},{"name":"preannot-ina","conclusion":"success"},{"name":"report-status","conclusion":"failure"}]}' ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh-jobs"
: > "$tmp/gh.log"
out=$(PREANNOT_GH="$tmp/mock-gh-jobs" "$sh" run 2>&1) || ko "run avec job preannot vert a échoué : $out"
printf '%s' "$out" | grep -q 'verdict=success' || ko "verdict du job preannot-ina attendu : $out"
printf '%s' "$out" | grep -q 'verdict_de=job preannot-ina' || ko "verdict non attribué au job : $out"
printf '%s' "$out" | grep -q 'extrait des logs' && ko "pas d'extrait quand preannot-ina est vert"
ok "run : verdict lu sur le job preannot-ina (run global en échec ignoré)"

# --- 8. le jeton n'est jamais un argument de processus ---------------------------
# Le filtre de journal reçoit le jeton par l'environnement : `ps` reste propre.
real_py=$(command -v python3)
mkdir -p "$tmp/bin"
cat > "$tmp/bin/python3" <<SPY
#!/usr/bin/env bash
printf '%s\\n' "\$*" >>"\${PREANNOT_SPY_LOG:?}"
exec "$real_py" "\$@"
SPY
chmod +x "$tmp/bin/python3"
: > "$tmp/spy.log"
set +e
out=$(PATH="$tmp/bin:$PATH" PREANNOT_GH="$tmp/mock-gh" PREANNOT_SPY_LOG="$tmp/spy.log" \
      PREANNOT_ART_DIR="$tmp/art2" "$sh" run 2>&1)
rc=$?
set -e
[ "$rc" -eq 1 ] || ko "run en échec simulé (spy) devrait sortir 1, obtenu $rc : $out"
[ -s "$tmp/spy.log" ] || ko "le mouchard python3 n'a rien vu (test invalide)"
grep -Fq "$tok" "$tmp/spy.log" && ko "jeton présent dans les arguments d'un processus"
printf '%s' "$out" | grep -q 'token=\*\*\*' || ko "le jeton n'est plus masqué dans l'extrait"
ok "jeton jamais en argument de processus, toujours masqué dans l'extrait"

echo "tous les contrôles preannot sont passés"
