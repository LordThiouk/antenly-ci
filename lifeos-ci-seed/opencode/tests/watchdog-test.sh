#!/usr/bin/env bash
# Test local du chien de garde des démons (wippush.sh / livelog.sh en mode daemon) : chaque
# passage tourne dans un processus fils borné, un passage qui dépasse son délai ou meurt est
# signalé et relancé, le superviseur survit, $STATE/pid est SON pid, $STATE/worker.pid celui du
# passage courant, et le jeton ne touche jamais l'état. Aucun réseau réel.
#   opencode/tests/watchdog-test.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=opencode/tests/lib.sh
. "$here/tests/lib.sh"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

remote="$tmp/remote.git"; git init -q --bare "$remote"
work="$tmp/work"; git init -q -b feat/w "$work"
git -C "$work" config user.name Test; git -C "$work" config user.email test@example.invalid
printf 'base\n' > "$work/README.md"; git -C "$work" add README.md; git -C "$work" commit -qm base
base=$(git -C "$work" rev-parse HEAD)
git -C "$work" push -q "$remote" "HEAD:refs/heads/feat/w"
printf 'un\n' > "$work/one.txt"; git -C "$work" add one.txt; git -C "$work" commit -qm "wip: un"
token="WATCHDOGTOKEN$(rand_alnum 24)"

# gitleaks factice lent : le passage reste bloqué dans le contrôle, donc le timeout le coupe.
printf '#!/bin/sh\nsleep 5\n' > "$tmp/gl-sleep"; chmod +x "$tmp/gl-sleep"
export WIP_REPO="$work" WIP_BRANCH=feat/w WIP_JOB=wd WIP_RUN=77 WIP_REMOTE="file://$remote" \
       WIP_BASE_SHA="$base" WIP_GITLEAKS="$tmp/gl-sleep" WIP_TRIES=1 WIP_TIMEOUT=5 \
       WIP_FIRST=1 WIP_INTERVAL_SEC=1 WIP_RETRY_SEC=1

# --- 1. passage trop long : coupé, signalé, superviseur vivant, puis arrêt propre -------------
export WIP_STATE="$tmp/state1" WIP_PASS_TIMEOUT=2
dout="$tmp/d1.out"
printf '%s\n' "$token" | WIP_TOKEN_STDIN=1 "$here/wippush.sh" daemon > "$dout" 2>&1 &
pid=$!
wpid=""
for _ in $(seq 1 60); do
  wpid=$(cat "$WIP_STATE/worker.pid" 2>/dev/null || true)
  [[ "$wpid" =~ ^[0-9]{1,9}$ ]] && break
  sleep 0.05
done
[[ "$wpid" =~ ^[0-9]{1,9}$ ]] || ko "worker.pid absent pendant un passage"
[ "$(cat "$WIP_STATE/pid")" = "$pid" ] || ko "pid d'état ≠ pid du superviseur"
for _ in $(seq 1 80); do grep -q 'délai 2 s dépassé' "$dout" 2>/dev/null && break; sleep 0.1; done
grep -q 'délai 2 s dépassé' "$dout" || ko "passage trop long non signalé : $(cat "$dout")"
kill -0 "$pid" 2>/dev/null || ko "le superviseur est mort après un passage coupé"
kill -TERM "$pid"
for _ in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
kill -0 "$pid" 2>/dev/null && { kill -KILL "$pid"; ko "le superviseur ne s'arrête pas sur SIGTERM"; }
grep -q 'arrêté' "$dout" || ko "arrêt non signalé"
[ "$(grep -c 'démarré' "$dout")" = 1 ] || ko "redémarrage inattendu après SIGTERM"
ok "passage trop long : coupé (2 s), superviseur vivant, arrêt propre"

# --- 2. passage tué : signalé et relancé sans tuer le superviseur ----------------------------
export WIP_STATE="$tmp/state2" WIP_PASS_TIMEOUT=10
dout2="$tmp/d2.out"
printf '%s\n' "$token" | WIP_TOKEN_STDIN=1 "$here/wippush.sh" daemon > "$dout2" 2>&1 &
pid2=$!
w1=""
for _ in $(seq 1 60); do
  w1=$(cat "$WIP_STATE/worker.pid" 2>/dev/null || true)
  [[ "$w1" =~ ^[0-9]{1,9}$ ]] && break
  sleep 0.05
done
[[ "$w1" =~ ^[0-9]{1,9}$ ]] || ko "worker.pid absent (cas 2)"
kill -TERM "$w1" 2>/dev/null || true
# Le signal est envoyé au `timeout` du passage. Selon coreutils, tuer `timeout` rend 143
# (« relance ») ou 124 (« délai dépassé ») : les deux disent « passage interrompu ». Exiger le
# texte exact rendait ce test rouge sur les runners (coreutils 9.4) alors que la relance marchait.
for _ in $(seq 1 80); do grep -q 'passage interrompu' "$dout2" 2>/dev/null && break; sleep 0.1; done
grep -q 'passage interrompu' "$dout2" || ko "passage tué non signalé : $(cat "$dout2")"
kill -0 "$pid2" 2>/dev/null || ko "le superviseur est mort avec le passage"
w2=""
for _ in $(seq 1 60); do
  w2=$(cat "$WIP_STATE/worker.pid" 2>/dev/null || true)
  [[ "$w2" =~ ^[0-9]{1,9}$ && "$w2" != "$w1" ]] && break
  sleep 0.05
done
[ -n "$w2" ] && [ "$w2" != "$w1" ] || ko "passage tué non relancé : aucun nouveau passage (pas de relance)"
kill -TERM "$pid2"
for _ in $(seq 1 40); do kill -0 "$pid2" 2>/dev/null || break; sleep 0.1; done
kill -0 "$pid2" 2>/dev/null && { kill -KILL "$pid2"; ko "le superviseur ne s'arrête pas (cas 2)"; }
ok "passage tué : relancé, superviseur intact"

# --- 3. le jeton ne touche jamais l'état du superviseur -------------------------------------
grep -rqaF -- "$token" "$tmp/state1" "$tmp/state2" "$dout" "$dout2" && ko "jeton retrouvé dans l'état ou la sortie"
ok "jeton absent de l'état et des sorties du chien de garde"

echo "PASS watchdog : timeout de passage, relance après kill, superviseur stable, jeton caché"
