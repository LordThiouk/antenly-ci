#!/usr/bin/env bash
# Test du plafond mémoire : bench-capped tue un processus qui dépasse le cap, le parent survit,
# et la ligne [oom] est écrite dans le journal avec un pic numérique. Aucun réseau réel.
#   opencode/tests/memcap-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

bench="$here/bench-capped"
[ -x "$bench" ] || ko "bench-capped absent ou non exécutable"

# --- Fonctions utilitaires ---
# Génère un programme Python qui alloue de la mémoire au-delà du cap.
make_eater() {
  cat > "$tmp/eater.py" <<'PYEOF'
import sys
# Alloue par blocs de 2 Mo jusqu'à ce que le noyau tue le processus.
blocks = []
try:
    while True:
        blocks.append(b'\x00' * (2 * 1024 * 1024))
except (MemoryError, OSError):
    sys.exit(42)  # MemoryError = prlimit, pas OOM cgroup → exit connu
PYEOF
}

has_oom_peak() {
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    if grep -qE '\[oom\].*peak=[1-9][0-9]*' "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# --- 1. Commande sous le cap : bench-capped laisse passer normalement ---
export BENCH_CAPPED_LIMIT=$((200 * 1024 * 1024))  # 200 Mo
export OC_LOG="$tmp/test.log"
: > "$OC_LOG"

rc=0
"$bench" /bin/sh -c 'echo hello' > "$tmp/ok.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || ko "commande légère devrait réussir (rc=$rc) : $(cat "$tmp/ok.out")"
ok "commande sous le cap : succès"

# --- 2. Commande qui dépasse le cap : tuée, parent survit, [oom] + pic ---
make_eater
rc=0
"$bench" python3 -I "$tmp/eater.py" > "$tmp/oom.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || ko "eater devrait être tué (rc=0 inattendu)"
if has_oom_peak "$OC_LOG" "$tmp/oom.out"; then
  ok "eater tué, ligne [oom] et pic numérique (rc=$rc)"
else
  ko "eater tué (rc=$rc) mais [oom]/pic absent : stderr=$(cat "$tmp/oom.out") log=$(cat "$OC_LOG" 2>/dev/null)"
fi

# --- 3. Le parent (ce script) est toujours vivant ---
# Si on arrive ici, le parent a survécu par définition.
ok "parent (test) toujours vivant après OOM du fils"

# --- 4. bench-capped sans argument : usage + exit 2 ---
rc=0
"$bench" > "$tmp/usage.out" 2>&1 || rc=$?
[ "$rc" -eq 2 ] || ko "bench-capped sans argument devrait rendre 2 (rc=$rc)"
ok "bench-capped sans argument : exit 2 (usage)"

# --- 5. command -v bench-capped le trouve une fois installé dans le PATH (comme en CI) ---
mkdir -p "$tmp/bin"
cp "$bench" "$tmp/bin/bench-capped"
chmod 0755 "$tmp/bin/bench-capped"
found=$(PATH="$tmp/bin:/usr/bin:/bin" command -v bench-capped || true)
[ "$found" = "$tmp/bin/bench-capped" ] || ko "command -v bench-capped devrait trouver $tmp/bin/bench-capped (trouvé=${found:-rien})"
ok "command -v bench-capped trouve l'outil dans le PATH"

# --- 6. prlimit (rc=42) : ligne [oom] et pic numérique ---
if command -v prlimit >/dev/null 2>&1; then
  : > "$OC_LOG"
  rc=0
  BENCH_CAPPED_METHOD=prlimit "$bench" python3 -I "$tmp/eater.py" > "$tmp/pr.out" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || ko "eater prlimit devrait échouer (rc=0)"
  if has_oom_peak "$OC_LOG" "$tmp/pr.out"; then
    ok "prlimit : [oom] et pic numérique (rc=$rc)"
  else
    ko "prlimit rc=$rc sans [oom]/pic : stderr=$(cat "$tmp/pr.out") log=$(cat "$OC_LOG" 2>/dev/null)"
  fi
else
  ok "prlimit absent : test [oom]/pic prlimit ignoré"
fi

echo "PASS memcap : cap mémoire, OOM, parent survit, [oom] journal, PATH, pic"
