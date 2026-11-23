#!/usr/bin/env bash
# Tests du garde-fou prompt_agent_check.sh : un lien non chaîné dont le prompt effectif ne
# dispatche jamais un agent de done_agents échouera à coup sûr sur a:none:<Agent> (voir
# opencode/prompt_agent_check.sh pour le constat du 22 nov. 2026). Ce test vérifie que le
# garde-fou le nomme AVANT opencode, et ne se met jamais en travers du mode chaîné ni d'un
# prompt qui dispatche réellement l'agent.
# Usage : bash opencode/tests/prompt-agent-check-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRIPT="$ROOT/opencode/prompt_agent_check.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "ok $1"; pass=$((pass + 1)); }
ko() { echo "ko $1"; fail=$((fail + 1)); }

[ -f "$SCRIPT" ] || { echo "ko script introuvable : $SCRIPT"; exit 1; }

# 1) Reproduction exacte de l'incident : prompt de phase build (jamais Max), solo, done_agents=Max
#    -> refusé avant opencode, message nommant Max.
build_prompt="$T/build.md"
cat >"$build_prompt" <<'EOF'
# FullRun · phase BUILD (étape 4)
Unité de travail : UNE tâche de build. Écritures d'ISA.md via ISATool uniquement.
EOF
out=$("$SCRIPT" false Max "$build_prompt" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'Max'; then
  ok "prompt build sans Max, solo -> refusé, Max nommé"
else
  ko "prompt build sans Max, solo -> attendu rc=1 et 'Max' dans le message (rc=$rc, out=$out)"
fi

# 2) Même prompt, mais chaîné (chain_enabled=true) : hors périmètre, jamais refusé ici.
out=$("$SCRIPT" true Max "$build_prompt" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "chain_enabled=true -> toujours accepté (hors périmètre)" \
  || ko "chain_enabled=true -> attendu rc=0 silencieux (rc=$rc, out=$out)"

# 3) Prompt de phase close (dispatche réellement Max) : accepté.
close_prompt="$T/close.md"
cat >"$close_prompt" <<'EOF'
# FullRun · phase CLOSE (étapes 6-7)
Unité de travail : Max, puis fermeture.
1. Max (read-only, lecture critique finale) : dispatche-le sur la plage de commits.
EOF
out=$("$SCRIPT" false Max "$close_prompt" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "prompt close avec Max, solo -> accepté" \
  || ko "prompt close avec Max, solo -> attendu rc=0 silencieux (rc=$rc, out=$out)"

# 4) Plusieurs agents, un seul manquant (Silas présent, Max absent) : nomme le bon.
verify_prompt="$T/verify.md"
cat >"$verify_prompt" <<'EOF'
# FullRun · phase VERIFY (étape 5)
Premier agent sans verdict réel : code-reviewer, puis Forge, puis Silas Locke (sécurité).
EOF
out=$("$SCRIPT" false "Silas,Max" "$verify_prompt" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'Max' && ! printf '%s' "$out" | grep -qE '\bSilas\b.*manquant|manquant.*\bSilas\b'; then
  ok "deux agents, un seul absent -> seul le manquant (Max) est nommé"
else
  ko "deux agents, un seul absent -> message incorrect (rc=$rc, out=$out)"
fi

# 5) Pas de faux positif sur un sous-mot (« Maxime » ne doit pas faire croire que « Max » est cité).
subword_prompt="$T/subword.md"
cat >"$subword_prompt" <<'EOF'
# FullRun
Contact : Maxime relit le rapport avant publication.
EOF
out=$("$SCRIPT" false Max "$subword_prompt" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "« Maxime » ne compte pas comme une mention de l'agent Max (mot entier)" \
  || ko "« Maxime » a été pris à tort pour une mention de Max (rc=$rc, out=$out)"

# 6) chain_enabled invalide -> erreur nommée, jamais un passage silencieux.
out=$("$SCRIPT" peutetre Max "$build_prompt" 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'chain_enabled' && ok "chain_enabled invalide -> rc=2 nommé" \
  || ko "chain_enabled invalide -> attendu rc=2 nommé (rc=$rc, out=$out)"

echo "---"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
