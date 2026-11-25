#!/usr/bin/env bash
# Option with_emulators du FullRun : entrée (défaut false), outil emu-e2e.sh
# (déclenchement distant sur galass-emu-actions-pub), pas de secrets e2e sur
# galass-ci, pas de FreeLLM ni d'appel HTTP direct à un modèle.
#   opencode/tests/with-emulators-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
# shellcheck source=opencode/allowed-repos.sh
. "$here/allowed-repos.sh"

wf="$here/../.github/workflows/opencode-fullrun.yml"
sh="$here/emu-e2e.sh"
[ -f "$wf" ] || ko "workflow introuvable : $wf"
[ -x "$sh" ] || ko "emu-e2e.sh introuvable ou non exécutable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. liste blanche inchangée ----------------------------------------------
allowed_repo galass-emu-actions-pub || ko "galass-emu-actions-pub doit rester dans la liste blanche"
allowed_repo Galass_Rider || ko "Galass_Rider doit rester dans la liste blanche"
allowed_repo Galass_Driver || ko "Galass_Driver doit rester dans la liste blanche"
ok "liste blanche : dépôts Galass et emu inchangés"

# --- 2. prompt : chemin figé, pas de secret, pas de FreeLLM / HTTP modèle -----
blk=$("$sh" prompt-block)
printf '%s' "$blk" | grep -q '/opt/fullrun-tools/emu-e2e.sh' || ko "prompt sans le chemin figé emu-e2e.sh"
printf '%s' "$blk" | grep -q 'artemis-staging-e2e.yml' || ko "prompt sans le workflow emu"
printf '%s' "$blk" | grep -q 'galass-emu-actions-pub' || ko "prompt sans le dépôt emu"
printf '%s' "$blk" | grep -qi 'pas de FreeLLM' || ko "prompt doit interdire FreeLLM"
printf '%s' "$blk" | grep -q 'opencode/deepseek-v4.1-flash-free' || ko "prompt sans le modèle opencode/*-free par défaut"
printf '%s' "$blk" | grep -q 'opencode/\*-free' || ko "prompt doit rappeler les modèles opencode/*-free"
printf '%s' "$blk" | grep -qE 'https?://opencode.ai|OPENAI_API_KEY|OPENAI_BASE_URL|FREELLMAPI|GALASS_STAGING_URL|GALASS_E2E_|DEBUG_KEYSTORE' \
  && ko "prompt ne doit pas contenir d'URL d'API modèle ni de nom de secret e2e"
mkdir -p "$tmp/oc"
printf 'preamble\n' > "$tmp/oc/prompt.md"
OC_WORK="$tmp/oc" "$sh" append-prompt >/dev/null
grep -q '/opt/fullrun-tools/emu-e2e.sh' "$tmp/oc/prompt.md" || ko "append-prompt n'a pas écrit le bloc"
ok "prompt-block / append-prompt : outil distant, sans secret"

# --- 3. resolve-refs et run : gh mocké, jeton jamais affiché ------------------
tok="e2e-tok-$(rand_alnum 24)"
printf '%s\n' "$tok" > "$tmp/token"
chmod 600 "$tmp/token"
: > "$tmp/gh.log"
# Branches simulées : Rider a la branche de travail, Driver non → main.
cat > "$tmp/mock-gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${EMU_E2E_GH_LOG:?}"
cmd="${1:-}"; shift || true
case "$cmd" in
  api)
    silent=0 path=""
    for a in "$@"; do
      case "$a" in
        --silent) silent=1 ;;
        repos/*) path="$a" ;;
      esac
    done
    case "$path" in
      repos/LordThiouk/Galass_Rider/branches/feat%2Fmulti) exit 0 ;;
      repos/LordThiouk/Galass_Driver/branches/feat%2Fmulti) exit 1 ;;
      *) exit 1 ;;
    esac
    ;;
  workflow)
    [ "${1:-}" = run ] || exit 2
    printf '%s\n' "$*" >> "${EMU_E2E_GH_LOG}.dispatch"
    exit 0
    ;;
  run)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        # Un run créé juste après le since du script. headBranch=main : galass-emu-actions-pub
        # n'a pas la branche de travail dans ce mock (emu_ref retombe sur main).
        printf '%s\n' '[{"databaseId":4242,"createdAt":"2099-01-01T00:00:00Z","status":"in_progress","conclusion":"","url":"https://example.test/4242","headBranch":"main"}]'
        ;;
      view)
        id="${1:-}"
        if printf '%s\n' "$*" | grep -q -- '--log-failed'; then
          # Journal volontairement long, avec le jeton au milieu : l'outil doit le couper et le masquer.
          i=1
          while [ "$i" -le 200 ]; do
            if [ "$i" -eq 195 ]; then
              echo "fail line ${i} token=${EMU_E2E_FAKE_TOKEN:-secret} boom"
            else
              echo "fail line ${i} xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            fi
            i=$((i + 1))
          done
        else
          printf '%s\n' '{"status":"completed","conclusion":"failure","url":"https://example.test/4242","displayTitle":"e2e","headBranch":"main"}'
        fi
        ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh"

export EMU_E2E_GH="$tmp/mock-gh"
export EMU_E2E_GH_LOG="$tmp/gh.log"
export EMU_E2E_TOKEN_FILE="$tmp/token"
export EMU_E2E_FAKE_TOKEN="$tok"
export OC_BRANCH="feat/multi"
export EMU_E2E_TIMEOUT_SEC=5
export EMU_E2E_POLL_SEC=0
export EMU_LOG_TAIL=20
export EMU_LOG_WIDTH=120
export GITHUB_ACTIONS=true

refs=$(EMU_E2E_GH="$tmp/mock-gh" EMU_E2E_TOKEN_FILE="$tmp/token" OC_BRANCH="feat/multi" \
  "$sh" resolve-refs)
printf '%s\n' "$refs" | grep -qx 'rider_ref=feat/multi' || ko "rider_ref devrait être la branche de travail, obtenu : $refs"
printf '%s\n' "$refs" | grep -qx 'driver_ref=main' || ko "driver_ref devrait retomber sur main, obtenu : $refs"
printf '%s\n' "$refs" | grep -q 'Galass_Driver' || ko "resolve-refs doit signaler le fallback Driver"
printf '%s\n' "$refs" | grep -Fq "$tok" && ko "jeton fuité dans resolve-refs"
ok "resolve-refs : branche de travail ou main, sans fuite"

# --- 3b. emu_ref (revue : galass-ci opencode/emu-e2e.sh l.361, --ref manquant) -
# Le mock ci-dessus (api repos/*/branches/feat%2Fmulti) ne connaît QUE Rider ;
# galass-emu-actions-pub n'a pas la branche de travail → repli main, comme Driver.
refs2=$(EMU_E2E_GH="$tmp/mock-gh" EMU_E2E_TOKEN_FILE="$tmp/token" OC_BRANCH="feat/multi" \
  "$sh" resolve-refs)
printf '%s\n' "$refs2" | grep -qx 'emu_ref=main' \
  || ko "emu_ref devrait retomber sur main (galass-emu-actions-pub sans la branche), obtenu : $refs2"
ok "resolve-refs : emu_ref résolu (branche de travail ou main)"

# Modèle non opencode/*-free refusé (avant tout appel réseau).
if out=$(EMU_E2E_MODEL=gemini-2.5-flash "$sh" run 2>&1); then
  ko "un modèle non *-free aurait dû être refusé"
fi
printf '%s' "$out" | grep -qi 'refusé' || ko "le refus de modèle doit être explicite"
printf '%s' "$out" | grep -Fq "$tok" && ko "jeton fuité lors du refus de modèle"
if out=$(EMU_E2E_MODEL=freellm/foo-free "$sh" run 2>&1); then
  ko "FreeLLM aurait dû être refusé"
fi
printf '%s' "$out" | grep -qi 'refusé' || ko "le refus FreeLLM doit être explicite"
# Défaut : le run (échec simulé) doit envoyer opencode/deepseek-v4.1-flash-free.
unset EMU_E2E_MODEL || true
: > "$tmp/gh.log.dispatch"
set +e
out=$("$sh" run 2>&1)
rc=$?
set -e
[ "$rc" -eq 1 ] || ko "run en échec simulé devrait sortir 1, obtenu $rc"
printf '%s' "$out" | grep -q 'verdict=failure' || ko "verdict d'échec manquant : $out"
printf '%s' "$out" | grep -q 'run=4242' || ko "id de run manquant"
printf '%s' "$out" | grep -q 'extrait des logs' || ko "extrait de logs manquant en échec"
# Pas le journal complet (200 lignes) : tail borné, plus le jeton en clair.
n=$(printf '%s\n' "$out" | grep -c 'fail line' || true)
[ "$n" -le 20 ] || ko "extrait trop long ($n lignes, max 20)"
printf '%s' "$out" | grep -Fq "$tok" && ko "jeton fuité dans l'extrait de logs"
printf '%s' "$out" | grep -q 'fail line 195' || ko "l'extrait devrait garder la fin du journal"
printf '%s' "$out" | grep -q 'token=\*\*\*' || ko "le jeton dans l'extrait doit être masqué"
grep -q 'model=opencode/deepseek-v4.1-flash-free' "$tmp/gh.log.dispatch" \
  || ko "le déclenchement doit passer model=opencode/deepseek-v4.1-flash-free"
grep -q 'rider_ref=feat/multi' "$tmp/gh.log.dispatch" || ko "dispatch sans rider_ref de travail"
grep -q 'driver_ref=main' "$tmp/gh.log.dispatch" || ko "dispatch sans driver_ref=main"
ok "run : déclenchement *-free, verdict et extrait court, pas de fuite"

# Succès : même mock, conclusion success, pas d'extrait.
cat > "$tmp/mock-gh-ok" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${EMU_E2E_GH_LOG:?}"
cmd="${1:-}"; shift || true
case "$cmd" in
  api)
    path=""
    for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "$path" in
      repos/LordThiouk/Galass_Rider/branches/feat%2Fmulti) exit 0 ;;
      repos/LordThiouk/Galass_Driver/branches/feat%2Fmulti) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  workflow) exit 0 ;;
  run)
    sub="${1:-}"
    case "$sub" in
      list) printf '%s\n' '[{"databaseId":7,"createdAt":"2099-01-01T00:00:00Z","status":"completed","conclusion":"success","url":"https://example.test/7","headBranch":"main"}]' ;;
      view) printf '%s\n' '{"status":"completed","conclusion":"success","url":"https://example.test/7","displayTitle":"e2e","headBranch":"main"}' ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh-ok"
: > "$tmp/gh.log"
out=$(EMU_E2E_GH="$tmp/mock-gh-ok" "$sh" run 2>&1) || ko "run succès simulé a échoué : $out"
printf '%s' "$out" | grep -q 'verdict=success' || ko "verdict succès manquant : $out"
printf '%s' "$out" | grep -q 'extrait des logs' && ko "pas d'extrait de logs en succès"
printf '%s' "$out" | grep -qx 'rider_ref=feat/multi' || printf '%s' "$out" | grep -q 'rider_ref=feat/multi' \
  || ko "refs de succès manquantes"
printf '%s' "$out" | grep -q 'driver_ref=feat/multi' || ko "Driver aurait dû garder la branche de travail"
ok "run : succès sans extrait de logs"

# Timeout borné : le run reste in_progress.
cat > "$tmp/mock-gh-hang" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; shift || true
case "$cmd" in
  api)
    path=""
    for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "$path" in repos/LordThiouk/*/branches/*) exit 0 ;; *) exit 1 ;; esac
    ;;
  workflow) exit 0 ;;
  run)
    sub="${1:-}"
    case "$sub" in
      list) printf '%s\n' '[{"databaseId":9,"createdAt":"2099-01-01T00:00:00Z","status":"in_progress","conclusion":"","url":"https://example.test/9","headBranch":"feat/multi"}]' ;;
      view) printf '%s\n' '{"status":"in_progress","conclusion":"","url":"https://example.test/9","displayTitle":"e2e","headBranch":"feat/multi"}' ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh-hang"
set +e
out=$(EMU_E2E_GH="$tmp/mock-gh-hang" EMU_E2E_TIMEOUT_SEC=1 EMU_E2E_POLL_SEC=0 "$sh" run 2>&1)
rc=$?
set -e
[ "$rc" -eq 124 ] || ko "timeout devrait sortir 124, obtenu $rc : $out"
printf '%s' "$out" | grep -q 'verdict=timeout' || ko "verdict timeout manquant : $out"
ok "run : timeout borné (124)"

# --- 3b. attente : sortie dès que le run est terminé, bornée, tolérante -------
# Mock paramétré par MOCK_MODE : done | hang | flaky | broken. Les appels
# `run view` sont comptés dans $MOCK_COUNT.
cat > "$tmp/mock-gh-wait" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; shift || true
case "$cmd" in
  api)
    path=""
    for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "$path" in repos/LordThiouk/*/branches/*) exit 0 ;; *) exit 1 ;; esac
    ;;
  workflow) exit 0 ;;
  run)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        printf '%s\n' '[{"databaseId":55,"createdAt":"2099-01-01T00:00:00Z","status":"completed","conclusion":"success","url":"https://example.test/55","headBranch":"feat/multi"}]'
        ;;
      view)
        if printf '%s\n' "$*" | grep -q -- '--log-failed'; then exit 0; fi
        n=$(( $(cat "${MOCK_COUNT:?}" 2>/dev/null || echo 0) + 1 ))
        printf '%s' "$n" > "$MOCK_COUNT"
        case "${MOCK_MODE:?}" in
          done)   printf '%s\n' '{"status":"completed","conclusion":"success","url":"https://example.test/55","displayTitle":"e2e"}' ;;
          hang)   sleep 30; printf '%s\n' '{"status":"in_progress","conclusion":"","url":"u","displayTitle":"e2e"}' ;;
          flaky)
            if [ "$n" -le 2 ]; then exit 1; fi
            printf '%s\n' '{"status":"completed","conclusion":"success","url":"https://example.test/55","displayTitle":"e2e"}'
            ;;
          broken) exit 1 ;;
        esac
        ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh-wait"
wait_run() { # $1=mode, reste = variables d'environnement supplémentaires
  local mode="$1"; shift
  : > "$tmp/view.count"
  start=$SECONDS
  set +e
  wait_out=$(env "$@" MOCK_MODE="$mode" MOCK_COUNT="$tmp/view.count" EMU_E2E_GH="$tmp/mock-gh-wait" "$sh" run 2>&1)
  wait_rc=$?
  set -e
  wait_elapsed=$(( SECONDS - start ))
  wait_views=$(cat "$tmp/view.count" 2>/dev/null || echo 0)
}

# Run déjà terminé : une seule lecture, aucune pause, malgré un délai de 600 s et un sondage de 30 s.
wait_run done EMU_E2E_TIMEOUT_SEC=600 EMU_E2E_POLL_SEC=30
[ "$wait_rc" -eq 0 ] || ko "run déjà terminé : rc=$wait_rc (attendu 0) : $wait_out"
printf '%s' "$wait_out" | grep -q 'verdict=success' || ko "run déjà terminé : verdict manquant : $wait_out"
[ "$wait_views" -eq 1 ] || ko "run déjà terminé : $wait_views lectures (attendu 1, aucune attente)"
[ "$wait_elapsed" -lt 10 ] || ko "run déjà terminé : ${wait_elapsed}s (doit sortir immédiatement)"
ok "attente : run déjà terminé → sortie immédiate (1 lecture, ${wait_elapsed}s)"

# Appel gh qui pend : plafonné par appel, l'attente reste bornée (124).
wait_run hang EMU_E2E_TIMEOUT_SEC=4 EMU_E2E_POLL_SEC=0 EMU_E2E_GH_TIMEOUT_SEC=1
[ "$wait_rc" -eq 124 ] || ko "gh qui pend : rc=$wait_rc (attendu 124) : $wait_out"
printf '%s' "$wait_out" | grep -q 'verdict=timeout' || ko "gh qui pend : verdict timeout manquant"
[ "$wait_elapsed" -lt 20 ] || ko "gh qui pend : ${wait_elapsed}s, l'attente n'est pas bornée"
ok "attente : appel gh qui pend → borné (${wait_elapsed}s, rc 124)"

# Erreurs transitoires de lecture : tolérées puis résolues.
wait_run flaky EMU_E2E_TIMEOUT_SEC=60 EMU_E2E_POLL_SEC=0
[ "$wait_rc" -eq 0 ] || ko "lectures instables : rc=$wait_rc (attendu 0) : $wait_out"
[ "$wait_views" -eq 3 ] || ko "lectures instables : $wait_views lectures (attendu 3)"
ok "attente : 2 erreurs de lecture transitoires tolérées, puis verdict"

# Lecture définitivement cassée : abandon après MAX_VIEW_FAILS, pas de boucle infinie.
wait_run broken EMU_E2E_TIMEOUT_SEC=600 EMU_E2E_POLL_SEC=0
[ "$wait_rc" -eq 1 ] || ko "lecture cassée : rc=$wait_rc (attendu 1) : $wait_out"
printf '%s' "$wait_out" | grep -q 'impossible de lire le run' || ko "lecture cassée : message manquant : $wait_out"
[ "$wait_views" -le 5 ] || ko "lecture cassée : $wait_views lectures (max 5)"
ok "attente : lecture cassée → abandon après ${wait_views} échecs consécutifs"

# --- 3c. cause du log figé (run 44163682423) : appels bloqués, sortie garantie --
# Mode deaf : gh ignore TERM (et ses enfants aussi) → seul KILL le libère.
sed 's|hang)   sleep 30;|hang)   trap "" TERM; sleep 30;|' "$tmp/mock-gh-wait" > "$tmp/mock-gh-deaf"
chmod +x "$tmp/mock-gh-deaf"
: > "$tmp/view.count"
start=$SECONDS
set +e
deaf_out=$(MOCK_MODE=hang MOCK_COUNT="$tmp/view.count" EMU_E2E_GH="$tmp/mock-gh-deaf" \
  EMU_E2E_TIMEOUT_SEC=3 EMU_E2E_POLL_SEC=0 EMU_E2E_GH_TIMEOUT_SEC=1 "$sh" run 2>&1)
deaf_rc=$?
set -e
deaf_elapsed=$(( SECONDS - start ))
[ "$deaf_rc" -eq 124 ] || ko "gh sourd à TERM : rc=$deaf_rc (attendu 124) : $deaf_out"
[ "$deaf_elapsed" -lt 25 ] || ko "gh sourd à TERM : ${deaf_elapsed}s, KILL de secours absent (timeout -k)"
grep -q 'timeout -k' "$sh" || ko "gh_cmd doit utiliser timeout -k (KILL après TERM)"
ok "gh bloqué et sourd à TERM : tué par KILL, sortie 124 en ${deaf_elapsed}s"

# Une ligne datée à chaque sondage : un log qui ne bouge plus est un processus mort/bloqué.
set +e
beat_out=$(EMU_E2E_GH="$tmp/mock-gh-hang" EMU_E2E_TIMEOUT_SEC=4 EMU_E2E_POLL_SEC=1 "$sh" run 2>&1)
set -e
beats=$(printf '%s\n' "$beat_out" | grep -cE '^[0-9]{2}:[0-9]{2}:[0-9]{2} sondage [0-9]+/[0-9]+ .*status=in_progress')
[ "$beats" -ge 2 ] || ko "heartbeat : $beats ligne(s) de sondage datée(s) (attendu >= 2) : $beat_out"
ok "sondages : une ligne datée par lecture ($beats lignes en 4 s)"

# Sortie garantie : TERM, HUP et USR1 (chien de garde) laissent un verdict= dans le log.
# INT est ignoré par construction pour un job lancé en arrière-plan (for sig in TERM INT HUP USR1; do) : non testable ici.
for sig in TERM HUP USR1; do
  : > "$tmp/bg.log"
  EMU_E2E_GH="$tmp/mock-gh-hang" EMU_E2E_TIMEOUT_SEC=60 EMU_E2E_POLL_SEC=0 "$sh" run > "$tmp/bg.log" 2>&1 < /dev/null &
  bgpid=$!
  for _ in $(seq 1 40); do grep -q '^run=' "$tmp/bg.log" 2>/dev/null && break; sleep 0.25; done
  grep -q '^run=' "$tmp/bg.log" || { kill -9 "$bgpid" 2>/dev/null; ko "signal $sig : le script n'a pas atteint l'attente : $(cat "$tmp/bg.log")"; }
  kill -"$sig" "$bgpid"
  set +e; wait "$bgpid"; bg_rc=$?; set -e
  case "$sig" in
    USR1) want='verdict=timeout watchdog'; want_rc=124 ;;
    *)    want="verdict=interrompu signal=$sig"; want_rc=$(( 128 + $(kill -l "$sig") )) ;;
  esac
  grep -q "$want" "$tmp/bg.log" || ko "signal $sig : '$want' absent du log : $(cat "$tmp/bg.log")"
  [ "$bg_rc" -eq "$want_rc" ] || ko "signal $sig : rc=$bg_rc (attendu $want_rc)"
done
grep -q 'watchdog_start' "$sh" || ko "chien de garde absent"
ok "sortie garantie : TERM/HUP/chien de garde laissent un verdict= dans le log"

# status : lecture seule d'un run, pour ne pas dormir sur un log figé.
: > "$tmp/view.count"
st=$(MOCK_MODE=done MOCK_COUNT="$tmp/view.count" EMU_E2E_GH="$tmp/mock-gh-wait" OC_BRANCH=feat/multistop-e2e-2026-11-15 "$sh" status 55 2>&1)
[ "$st" = "status=completed conclusion=success run=55" ] || ko "status : sortie inattendue : $st"
set +e
OC_BRANCH=x EMU_E2E_GH="$tmp/mock-gh-wait" "$sh" status '55; id' >/dev/null 2>&1; bad_rc=$?
OC_BRANCH=x MOCK_MODE=broken MOCK_COUNT="$tmp/view.count" EMU_E2E_GH="$tmp/mock-gh-wait" "$sh" status 55 >/dev/null 2>&1; unread_rc=$?
set -e
[ "$bad_rc" -ne 0 ] || ko "status doit refuser un identifiant non numérique"
[ "$unread_rc" -eq 1 ] || ko "status illisible : rc=$unread_rc (attendu 1)"
grep -q 'emu-e2e.sh status \*' "$wf" || ko "sudoers : status absent de la liste autorisée"
ok "status : lecture seule, id numérique, illisible → rc 1, autorisé via sudoers"

# Prompt : lancement détaché sans sous-shell, et règle des 2 cycles sur log figé.
blk=$("$sh" prompt-block)
printf '%s' "$blk" | grep -q 'setsid nohup' || ko "prompt sans lancement détaché (setsid nohup)"
printf '%s' "$blk" | grep -qF 'A && B && nohup' || ko "prompt sans l'interdiction du sous-shell A && B && nohup"
printf '%s' "$blk" | grep -q 'plus de 2 cycles' || ko "prompt sans la règle des 2 cycles"
printf '%s' "$blk" | grep -q 'emu-e2e.sh status <run_id>' || ko "prompt sans la vérification d'état du run"
ok "prompt : lancement détaché et vérification d'état après 2 cycles sans mouvement"

# --- 4. workflow : input booléen, plus de setup local, gardes intactes --------
grep -q 'with_emulators:' "$wf" || ko "input with_emulators absent du workflow"
awk '
  $0 ~ /^      with_emulators:/ { p=1; print; next }
  p && $0 ~ /^      [A-Za-z0-9_]+:/ { exit }
  p { print }
' "$wf" > "$tmp/input.yml"
grep -q 'type: boolean' "$tmp/input.yml" || ko "with_emulators doit être type: boolean"
grep -q 'default: false' "$tmp/input.yml" || ko "with_emulators doit valoir false par défaut"
# Plus de démarrage local, plus de build APK, plus des 5 secrets e2e.
if grep -nE 'actions/setup-java@|android-actions/setup-android@|subosito/flutter-action@' "$wf"; then
  ko "workflow : setup Java / Android / Flutter encore présent (démarrage local)"
fi
if grep -nE 'secrets\.(GALASS_STAGING_URL|GALASS_E2E_RIDER_TOKEN|GALASS_E2E_DRIVER_TOKEN|GALASS_E2E_DEV_TOKEN|DEBUG_KEYSTORE_B64)' "$wf"; then
  ko "workflow : secret e2e encore demandé sur galass-ci"
fi
if grep -nE 'emulators\.sh|free-disk|Arrêter les émulateurs|Préparer et démarrer les émulateurs' "$wf"; then
  ko "workflow : anciennes étapes d'émulateurs locaux encore présentes"
fi
grep -q 'opencode/emu-e2e.sh' "$wf" || ko "workflow n'installe pas emu-e2e.sh"
grep -q '/opt/fullrun-tools' "$wf" && grep -q 'emu-e2e.sh' "$wf" \
  || ko "emu-e2e.sh n'est pas figé dans /opt/fullrun-tools"
# Interdiction documentée OK ; on refuse une clé ou une URL de modèle HTTP.
if grep -nE 'FREELLMAPI_|OPENAI_API_KEY|OPENAI_BASE_URL|secrets\.OPENCODE_API_KEY' "$wf"; then
  ko "workflow : FreeLLM ou appel HTTP direct à un modèle détecté"
fi
# Les modèles restent opencode/*-free (garde existante intacte).
grep -q 'opencode/\[a-z0-9.-\]+-free' "$wf" || grep -qE 'opencode/\[a-z0-9\.-\]\+-free' "$wf" \
  || ko "garde des modèles opencode/*-free introuvable"
# Plafond mémoire toujours présent (on ne l'affaiblit pas).
grep -q 'MemoryMax=' "$wf" || ko "plafond mémoire retiré du workflow"
# Liste blanche toujours sourcée / figée.
grep -q 'allowed-repos.sh' "$wf" || ko "allowed-repos.sh retiré du workflow"
ok "workflow : input false par défaut, e2e distant, gardes FullRun intactes"

# --- 3d. --ref sur le dépôt emu (bug run 44238051634 : main exécuté au lieu de la branche de
# travail) : le dispatch doit porter --ref="$emu_ref", et find_new_run/run_e2e doivent refuser un
# run dont headBranch n'est pas emu_ref, jamais comme un faux FAIL de test. ------------------------
cat > "$tmp/mock-gh-ref" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${EMU_E2E_GH_LOG_REF:?}"
cmd="${1:-}"; shift || true
case "$cmd" in
  api)
    path=""
    for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "${REF_MODE:-has}" in
      has) case "$path" in repos/LordThiouk/*/branches/*) exit 0 ;; *) exit 1 ;; esac ;;
      missing_emu)
        case "$path" in
          repos/LordThiouk/galass-emu-actions-pub/branches/*) exit 1 ;;
          repos/LordThiouk/*/branches/*) exit 0 ;;
          *) exit 1 ;;
        esac
        ;;
    esac
    ;;
  workflow)
    [ "${1:-}" = run ] || exit 2
    printf '%s\n' "$*" >> "${EMU_E2E_GH_LOG_REF}.dispatch"
    exit 0
    ;;
  run)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        printf '%s\n' "${REF_LIST_JSON:?}"
        ;;
      view) printf '%s\n' '{"status":"completed","conclusion":"success","url":"https://example.test/x","displayTitle":"e2e"}' ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh-ref"
ref_run() { # $1=REF_MODE, $2=REF_LIST_JSON, reste = env supplémentaire
  local mode="$1" listjson="$2"; shift 2
  : > "$tmp/gh-ref.log"; : > "$tmp/gh-ref.log.dispatch"
  set +e
  refrun_out=$(env "$@" REF_MODE="$mode" REF_LIST_JSON="$listjson" \
    EMU_E2E_GH="$tmp/mock-gh-ref" EMU_E2E_GH_LOG_REF="$tmp/gh-ref.log" \
    OC_BRANCH="feat/multi" EMU_E2E_TIMEOUT_SEC=5 EMU_E2E_POLL_SEC=0 "$sh" run 2>&1)
  refrun_rc=$?
  set -e
}

# (1) branche de travail présente sur emu : --ref=feat/multi transmis, emu_ref=feat/multi au log.
run_on_branch='[{"databaseId":101,"createdAt":"2099-01-01T00:00:00Z","status":"completed","conclusion":"success","url":"u","headBranch":"feat/multi"}]'
ref_run has "$run_on_branch"
[ "$refrun_rc" -eq 0 ] || ko "--ref (branche présente) : rc=$refrun_rc (attendu 0) : $refrun_out"
printf '%s' "$refrun_out" | grep -q 'emu_ref=feat/multi' || ko "--ref : emu_ref absent du log (branche présente) : $refrun_out"
grep -q -- '--ref feat/multi' "$tmp/gh-ref.log.dispatch" \
  || ko "--ref : le dispatch doit porter --ref feat/multi (branche présente) : $(cat "$tmp/gh-ref.log.dispatch")"
ok "--ref : branche de travail présente sur emu → --ref=\$emu_ref transmis au dispatch"

# (2) branche de travail absente sur emu (cas du bug) : fallback --ref=main, même note que rider/driver.
run_on_main='[{"databaseId":102,"createdAt":"2099-01-01T00:00:00Z","status":"completed","conclusion":"success","url":"u","headBranch":"main"}]'
ref_run missing_emu "$run_on_main"
[ "$refrun_rc" -eq 0 ] || ko "--ref (fallback) : rc=$refrun_rc (attendu 0) : $refrun_out"
printf '%s' "$refrun_out" | grep -q 'emu_ref=main' || ko "--ref (fallback) : emu_ref devrait être main : $refrun_out"
printf '%s' "$refrun_out" | grep -q "galass-emu-actions-pub n'a pas la branche feat/multi" \
  || ko "--ref (fallback) : note de fallback absente pour galass-emu-actions-pub : $refrun_out"
grep -q -- '--ref main' "$tmp/gh-ref.log.dispatch" \
  || ko "--ref (fallback) : le dispatch doit porter --ref main : $(cat "$tmp/gh-ref.log.dispatch")"
ok "--ref : branche de travail absente sur emu → fallback --ref=main, note explicite"

# (3) run 44238051634 reproduit : le seul run trouvable est sur le mauvais head_branch (main, alors
# qu'emu_ref=feat/multi) → verdict=FAIL explicite « ref_erronee », jamais lu comme un échec de test.
run_on_wrong_branch='[{"databaseId":103,"createdAt":"2099-01-01T00:00:00Z","status":"completed","conclusion":"failure","url":"u","headBranch":"main"}]'
ref_run has "$run_on_wrong_branch"
[ "$refrun_rc" -ne 0 ] || ko "head_branch erroné : aurait dû échouer (run sur main, emu_ref=feat/multi)"
printf '%s' "$refrun_out" | grep -q 'ref_erronee' \
  || ko "head_branch erroné : verdict=FAIL ref_erronee absent : $refrun_out"
printf '%s' "$refrun_out" | grep -q 'attendu=feat/multi' || ko "head_branch erroné : attendu= absent : $refrun_out"
printf '%s' "$refrun_out" | grep -q 'obtenu=main' || ko "head_branch erroné : obtenu= absent : $refrun_out"
printf '%s' "$refrun_out" | grep -qv '^e2e : échec' ; : # pas d'assertion négative fragile, juste un rappel visuel
printf '%s' "$refrun_out" | grep -q 'extrait des logs' && ko "head_branch erroné : ne doit jamais lire l'extrait d'un run sur la mauvaise branche (confondu avec un vrai échec de test)"
ok "head_branch erroné (run 44238051634) : verdict=FAIL ref_erronee explicite, jamais lu comme un échec de test"

# (4) find_new_run filtre : deux runs dans la fenêtre since, l'un sur main, l'autre sur la branche de
# travail — seul celui sur la branche de travail doit être choisi (jamais le plus récent au hasard).
two_runs='[{"databaseId":200,"createdAt":"2099-01-01T00:00:05Z","status":"completed","conclusion":"success","url":"u","headBranch":"main"},{"databaseId":201,"createdAt":"2099-01-01T00:00:00Z","status":"completed","conclusion":"success","url":"u","headBranch":"feat/multi"}]'
ref_run has "$two_runs"
[ "$refrun_rc" -eq 0 ] || ko "filtre find_new_run : rc=$refrun_rc (attendu 0) : $refrun_out"
printf '%s' "$refrun_out" | grep -q 'run=201' || ko "filtre find_new_run : aurait dû choisir le run 201 (bonne branche), pas 200 : $refrun_out"
ok "find_new_run filtre sur headBranch : le run de la bonne branche est choisi, pas le plus récent au hasard"

# --- (5) régression : divergence list/view sur le head_branch (repris de main, dbe68be) ---
# `run list` (consulté par find_new_run) annonce la bonne branche, donc passe le filtre et la
# première garde (bon marché, l.~425) ; mais la vue détaillée (`run view`) du MÊME run révèle une
# autre branche : API en retard, run réutilisé par accident. Avant ce correctif, seule la liste
# était jamais consultée : ce scénario était lu comme « e2e : succès » (rc=0), silencieusement.
cat > "$tmp/mock-gh-wrongref" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; shift || true
case "$cmd" in
  api)
    path=""
    for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "$path" in repos/LordThiouk/*/branches/*) exit 0 ;; *) exit 1 ;; esac
    ;;
  workflow) [ "${1:-}" = run ] || exit 2; exit 0 ;;
  run)
    sub="${1:-}"; shift || true
    case "$sub" in
      list) printf '%s\n' '[{"databaseId":6001,"createdAt":"2099-01-01T00:00:00Z","status":"completed","conclusion":"success","url":"https://example.test/6001","headBranch":"feat/multi"}]' ;;
      view) printf '%s\n' '{"status":"completed","conclusion":"success","url":"https://example.test/6001","displayTitle":"e2e","headBranch":"main"}' ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh-wrongref"
set +e
wrongref_out=$(EMU_E2E_GH="$tmp/mock-gh-wrongref" OC_BRANCH="feat/multi" EMU_E2E_TIMEOUT_SEC=5 EMU_E2E_POLL_SEC=0 "$sh" run 2>&1)
wrongref_rc=$?
set -e
[ "$wrongref_rc" -ne 0 ] || ko "divergence list/view : rc=0 (attendu différent de 0) : $wrongref_out"
printf '%s' "$wrongref_out" | grep -qi 'mauvais ref' || ko "divergence list/view : message « mauvais ref » absent : $wrongref_out"
printf '%s' "$wrongref_out" | grep -q 'ref_erronee' || ko "divergence list/view : jeton verdict=FAIL ref_erronee absent : $wrongref_out"
printf '%s' "$wrongref_out" | grep -q 'e2e : succès' && ko "divergence list/view : lue à tort comme un succès de test (régression exacte signalée) : $wrongref_out"
ok "régression : list=feat/multi mais view=main (run réutilisé/API en retard) → FAIL mauvais ref/ref_erronee, jamais lu comme un succès"

# --- Chaînage : un run e2e en vol est REPRIS par le lien suivant, jamais relancé en double -----------
cat > "$tmp/mock-gh-resume" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${EMU_E2E_GH_LOG:?}"
cmd="${1:-}"; shift || true
case "$cmd" in
  api)
    path=""
    for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "$path" in repos/LordThiouk/*/branches/*) exit 0 ;; *) exit 1 ;; esac
    ;;
  run)
    case "${1:-}" in
      view) printf '%s\n' '{"status":"completed","conclusion":"success","url":"https://example.test/4242","displayTitle":"e2e","headBranch":"feat/multi"}' ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/mock-gh-resume"
: > "$tmp/gh.log"
printf '4242\n' > "$tmp/emu-resume"
set +e
out=$(EMU_E2E_GH="$tmp/mock-gh-resume" OC_BRANCH=feat/multi EMU_E2E_RESUME_FILE="$tmp/emu-resume" \
  EMU_E2E_INFLIGHT_FILE="$tmp/emu-run" EMU_E2E_TIMEOUT_SEC=5 EMU_E2E_POLL_SEC=0 "$sh" run 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || ko "reprise : rc=$rc : $out"
printf '%s' "$out" | grep -q 'reprise du run e2e 4242' || ko "reprise : message absent : $out"
printf '%s' "$out" | grep -q 'verdict=success' || ko "reprise : verdict absent : $out"
grep -q '^workflow run' "$tmp/gh.log" && ko "reprise : un nouveau run a été déclenché (double lancement) : $(cat "$tmp/gh.log")"
grep -q '^run list' "$tmp/gh.log" && ko "reprise : run list appelé (aucune recherche de nouveau run attendue)"
[ ! -f "$tmp/emu-resume" ] || ko "reprise : fichier de reprise non consommé"
[ ! -f "$tmp/emu-run" ] || ko "reprise : run terminé mais marqueur en vol non effacé"
ok "chaînage : run e2e 4242 repris (aucun workflow run), marqueur de reprise consommé, marqueur en vol effacé au verdict"

# Sans reprise : le run déclenché est inscrit comme « en vol » tant qu'il n'a pas de verdict (timeout)
: > "$tmp/gh.log"; rm -f "$tmp/emu-run"
set +e
out=$(EMU_E2E_GH="$tmp/mock-gh-hang" OC_BRANCH=feat/multi EMU_E2E_RESUME_FILE="$tmp/none" \
  EMU_E2E_INFLIGHT_FILE="$tmp/emu-run" EMU_E2E_TIMEOUT_SEC=1 EMU_E2E_POLL_SEC=0 "$sh" run 2>&1)
rc=$?
set -e
[ "$rc" -eq 124 ] || ko "en vol : timeout attendu (124), obtenu $rc : $out"
[ "$(tr -d '[:space:]' < "$tmp/emu-run" 2>/dev/null)" = 9 ] \
  || ko "en vol : le run 9 non terminé devait rester inscrit (lu : $(cat "$tmp/emu-run" 2>/dev/null))"
ok "chaînage : run non terminé à la fin du lien ⇒ id inscrit (transmis au lien suivant)"

# Fichier de reprise corrompu : ignoré, jamais injecté ; run normal (déclenchement)
printf 'abc; rm -rf /\n' > "$tmp/emu-resume"; : > "$tmp/gh.log"
out=$(EMU_E2E_GH="$tmp/mock-gh-ok" OC_BRANCH=feat/multi EMU_E2E_RESUME_FILE="$tmp/emu-resume" \
  EMU_E2E_INFLIGHT_FILE="$tmp/emu-run" "$sh" run 2>&1) || true
printf '%s' "$out" | grep -q 'reprise du run e2e' && ko "reprise corrompue : prise en compte à tort : $out"
grep -q '^workflow run' "$tmp/gh.log" || ko "reprise corrompue : aucun déclenchement normal"
ok "chaînage : fichier de reprise non numérique ignoré (run normal)"

echo "tous les contrôles with_emulators sont passés"
