#!/usr/bin/env bash
# Webhook de fin de run. Toujours non bloquant (sortie 0), jamais de secret affiché.
# Variables lues : OC_NOTIFY_URL, OC_NOTIFY_KEY, OC_JOB, OC_AGENT, OC_STATUS,
# OC_TARGET_REPO, OC_BRANCH, OC_MODEL, OC_SHA, OC_RUN_URL, OC_MESSAGE.
set -euo pipefail

notify_main() {
  local url="${OC_NOTIFY_URL:-}" key="${OC_NOTIFY_KEY:-}" payload message
  local job="${OC_JOB:-}" agent="${OC_AGENT:-}" status="${OC_STATUS:-}" target="${OC_TARGET_REPO:-}"
  local branch="${OC_BRANCH:-}" model="${OC_MODEL:-}" sha="${OC_SHA:-}" run_url="${OC_RUN_URL:-}"
  local extra="${OC_MESSAGE:-}"

  if [ -z "$url" ] || [ -z "$key" ]; then
    echo "notification ignorée : OC_NOTIFY_URL ou OC_NOTIFY_KEY absent"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "notification ignorée : jq absent"
    return 0
  fi

  message="${extra:-${job} (${target}@${branch}) : status=${status} model=${model} sha=${sha} — ${run_url}}"
  payload=$(jq -cn \
    --arg job "$job" \
    --arg agent "$agent" \
    --arg status "$status" \
    --arg target_repo "$target" \
    --arg branch "$branch" \
    --arg model "$model" \
    --arg sha "$sha" \
    --arg run_url "$run_url" \
    --arg message "$message" \
    '{job:$job, agent:$agent, status:$status, target_repo:$target_repo, branch:$branch, model:$model, sha:$sha, run_url:$run_url, message:$message}') || return 0

  curl -sS --max-time 15 -X POST "$url" \
    -H "Authorization: Bearer $key" \
    -H "X-Automation-Key: $key" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null 2>&1 || true
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  notify_main || true
  exit 0
fi
