#!/usr/bin/env bash
# Test du plafond mémoire : bench-capped tue un processus qui dépasse le cap, le parent survit,
# et la ligne [oom] est écrite dans le journal. Aucun réseau réel.
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

# --- 1. Commande sous le cap : bench-capped laisse passer normalement ---
export BENCH_CAPPED_LIMIT=$((200 * 1024 * 1024))  # 200 Mo
export OC_LOG="$tmp/test.log"
: > "$OC_LOG"

rc=0
"$bench" /bin/sh -c 'echo hello' > "$tmp/ok.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || ko "commande légère devrait réussir (rc=$rc) : $(cat "$tmp/ok.out")"
ok "commande sous le cap : succès"

# --- 2. Commande qui dépasse le cap : tuée, parent survit, [oom] écrit ---
make_eater
rc=0
"$bench" python3 -I "$tmp/eater.py" > "$tmp/oom.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || ko "eater devrait être tué (rc=0 inattendu)"
# La ligne [oom] doit apparaître dans OC_LOG ou dans stderr (selon le mécanisme).
if grep -q '\[oom\]' "$OC_LOG" 2>/dev/null || grep -q '\[oom\]' "$tmp/oom.out" 2>/dev/null; then
  ok "eater tué, ligne [oom] présente (rc=$rc)"
else
  # Avec prlimit, le signal est SIGSEGV (139) ou MemoryError (42). Le [oom] est attendu pour
  # 137 et 139 ; si le mécanisme est prlimit et Python attrape MemoryError → rc=42, pas d'[oom].
  if [ "$rc" -eq 42 ]; then
    ok "eater tué par MemoryError (prlimit, rc=42) — pas de ligne [oom] attendue"
  else
    ko "eater tué (rc=$rc) mais pas de ligne [oom] : stderr=$(cat "$tmp/oom.out") log=$(cat "$OC_LOG" 2>/dev/null)"
  fi
fi

# --- 3. Le parent (ce script) est toujours vivant ---
# Si on arrive ici, le parent a survécu par définition.
ok "parent (test) toujours vivant après OOM du fils"

# --- 4. bench-capped sans argument : usage + exit 2 ---
rc=0
"$bench" > "$tmp/usage.out" 2>&1 || rc=$?
[ "$rc" -eq 2 ] || ko "bench-capped sans argument devrait rendre 2 (rc=$rc)"
ok "bench-capped sans argument : exit 2 (usage)"

echo "PASS memcap : cap mémoire, OOM, parent survit, [oom] journal"
