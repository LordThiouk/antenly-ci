#!/usr/bin/env bash
# Lance opencode run sans jamais écrire sa sortie dans le log public du job.
# Repli sur $OC_MODEL_FALLBACK seulement si la passe principale échoue sur un 429 / limite d'usage.
set +x
set -uo pipefail
: "${ANTENLY_DIR:?}" "${OC_PROMPT_FILE:?}" "${OC_LOG:?}" "${OC_MODEL_MAIN:?}" "${OC_MODEL_FALLBACK:?}" "${OC_DEADLINE_MIN:?}"
cd "$ANTENLY_DIR" || exit 90
# opencode ne reçoit pas les fichiers de commandes du runner : il ne peut ni poser de variables
# ou de PATH pour les steps suivants, ni écrire dans le Summary public, ni de sorties de step.
unset GITHUB_ENV GITHUB_PATH GITHUB_OUTPUT GITHUB_STATE GITHUB_STEP_SUMMARY
PROMPT=$(cat "$OC_PROMPT_FILE")
mkdir -p "$(dirname "$OC_LOG")"
start=$(date +%s)
remaining() { echo $(( OC_DEADLINE_MIN * 60 - ( $(date +%s) - start ) )); }

timeout --signal=INT --kill-after=60 "$(remaining)" \
  opencode run --model "$OC_MODEL_MAIN" --title "$OC_JOB" "$PROMPT" >"$OC_LOG" 2>&1
rc=$?
echo "main_rc=$rc" >"$OC_LOG.status"

if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ "$(remaining)" -gt 600 ] \
   && grep -qiE '\b429\b|too many requests|rate.?limit|usage limit' "$OC_LOG"; then
  echo "fallback=1" >>"$OC_LOG.status"
  timeout --signal=INT --kill-after=60 "$(remaining)" \
    opencode run --continue --model "$OC_MODEL_FALLBACK" \
    "Reprends exactement où tu t'es arrêté (le modèle précédent a reçu un 429). Relis le contexte CI ci-dessus et $OC_REPORT si présent." \
    >>"$OC_LOG" 2>&1
  rc=$?
  echo "fallback_rc=$rc" >>"$OC_LOG.status"
fi
exit "$rc"
