#!/usr/bin/env bash
# Tests de la notification de fin de run (sans réseau, sans secret réel).
#   opencode/tests/notify-test.sh
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
notify="$here/notify.sh"
[ -f "$notify" ] || { echo "FAIL notify.sh absent : $notify" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'FAKE'
#!/usr/bin/env bash
code="${FAKE_HTTP_CODE:-200}"
out=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ]; then
    out="$a"
  fi
  prev="$a"
done
if [ -n "$out" ]; then
  printf 'fake response body %s\n' "$code" > "$out"
fi
printf '%s' "$code"
if [ "$code" = "000" ]; then
  exit 7
fi
exit 0
FAKE
chmod +x "$tmp/bin/curl"

pass=0
secret="SENTINEL-KEY-DO-NOT-PRINT-abcdef123456"

run_case() {
  local code="$1" output
  output=$(PATH="$tmp/bin:$PATH" \
    FAKE_HTTP_CODE="$code" \
    OC_NOTIFY_URL="https://example.invalid/notify" \
    OC_NOTIFY_KEY="$secret" \
    OC_JOB="job-test" OC_AGENT="vera" OC_STATUS="ok" \
    OC_TARGET_REPO="antenly" OC_BRANCH="feat/x" OC_MODEL="opencode/x-free" \
    OC_SHA="deadbee" OC_RUN_URL="https://example.invalid/run/1" \
    bash "$notify" 2>&1) || {
      echo "FAIL HTTP $code : sortie non nulle" >&2
      printf '%s\n' "$output" >&2
      exit 1
    }
  pass=$((pass + 1))
  case "$output" in
    *"$secret"*)
      echo "FAIL HTTP $code : la clé apparaît dans la sortie" >&2
      printf '%s\n' "$output" >&2
      exit 1
      ;;
  esac
  printf '%s' "$output" > "$tmp/out-$code"
}

check_contains() {
  local code="$1" needle="$2"
  if ! grep -qF "$needle" "$tmp/out-$code"; then
    echo "FAIL HTTP $code : attendu « $needle »" >&2
    cat "$tmp/out-$code" >&2
    exit 1
  fi
  pass=$((pass + 1))
}

check_absent() {
  local code="$1" needle="$2"
  if grep -qF "$needle" "$tmp/out-$code"; then
    echo "FAIL HTTP $code : ne devait pas contenir « $needle »" >&2
    cat "$tmp/out-$code" >&2
    exit 1
  fi
  pass=$((pass + 1))
}

# 200 : code affiché, aucun warning.
run_case 200
check_contains 200 "notify: HTTP 200"
check_absent 200 "::warning::"

# 401, 500, 000 : warning présent, sortie toujours 0, clé jamais affichée.
for code in 401 500 000; do
  run_case "$code"
  check_contains "$code" "notify: HTTP $code"
  check_contains "$code" "::warning::notification échouée (HTTP $code)"
  check_absent "$code" "$secret"
  check_absent "$code" "Authorization"
  check_absent "$code" "X-Automation-Key"
done

echo "PASS notify-test : $pass cas"
