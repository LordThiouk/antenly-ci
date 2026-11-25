#!/usr/bin/env bash
# Tests statiques de la chaîne FullRun et de l'écriture LifeOS (sans réseau).
#   opencode/tests/lifeos-chain-test.sh
# shellcheck disable=SC2016
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
wf="$here/.github/workflows"
fr="$wf/fr-plan-vera.yml"
next="$wf/_next.yml"
task="$wf/task.yml"
run="$wf/_agent-run.yml"

pass=0
fail() {
  echo "FAIL $1" >&2
  exit 1
}
need_file() {
  [ -f "$1" ] || fail "fichier absent : $1"
  pass=$((pass + 1))
}
need_line() {
  local file="$1" needle="$2" label="$3"
  grep -qF -- "$needle" "$file" || fail "$label (attendu « $needle » dans $(basename "$file"))"
  pass=$((pass + 1))
}
forbid_line() {
  local file="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" "$file"; then
    fail "$label (interdit « $needle » dans $(basename "$file"))"
  fi
  pass=$((pass + 1))
}

need_file "$fr"
need_file "$next"
need_file "$task"
need_file "$run"

# fr-plan-vera.yml déclare lifeos_write (booléen) et le transmet au run et au lien suivant.
need_line "$fr" "lifeos_write:" "fr-plan-vera déclare lifeos_write"
need_line "$fr" "type: boolean" "fr-plan-vera déclare un booléen"
n=$(grep -cF -- 'lifeos_write: ${{ inputs.lifeos_write }}' "$fr")
[ "$n" -ge 2 ] || fail "fr-plan-vera doit transmettre lifeos_write à _agent-run et _next (vu $n)"
pass=$((pass + 1))

# _next.yml transmet lifeos_write et tous les autres inputs au maillon suivant.
need_line "$next" "lifeos_write:" "_next déclare lifeos_write"
need_line "$next" '-F lifeos_write="$LIFEOS_WRITE"' "_next transmet lifeos_write (booléen) avec -F au maillon suivant"
for input in target_repo extra_repos branch prompt_path isa_path job_name lifeos_ref timeout_minutes; do
  need_line "$next" "-f ${input}=" "_next transmet ${input}"
done

# task.yml garde le défaut false.
awk '
function indent(s) { match(s, /^ */); return RLENGTH }
/^[ ]*lifeos_write:/ { li = indent($0); inb = 1; next }
inb {
  if ($0 ~ /^[ ]*$/) next
  if (indent($0) <= li && $0 ~ /^[ ]*[A-Za-z0-9_.-]+:/) inb = 0
}
inb && /^[ ]*default:[ ]*false/ { found = 1 }
END { exit(found ? 0 : 1) }
' "$task" || fail "task.yml : lifeos_write doit avoir default: false"
pass=$((pass + 1))

# Aucune destination main/master pour LifeOS : branche dédiée uniquement.
need_line "$run" 'lifeos_branch="lifeos-ci/' "_agent-run crée une branche LifeOS dédiée"
need_line "$run" 'HEAD:refs/heads/$lifeos_branch' "le push LifeOS vise la branche dédiée"
need_line "$run" 'lifeos-guard.sh destination "$LIFEOS_WRITE" "LordThiouk/lifeos" "$lifeos_branch"' \
  "le garde-fou est appliqué à la destination LifeOS"
forbid_line "$run" 'HEAD:refs/heads/main' "aucun push LifeOS vers main"
forbid_line "$run" 'HEAD:refs/heads/master' "aucun push LifeOS vers master"

echo "PASS lifeos-chain-test : $pass cas"
