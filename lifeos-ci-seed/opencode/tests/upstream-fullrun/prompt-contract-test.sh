#!/usr/bin/env bash
# Contrat de prompt FullRun : le préambule injecté avant le prompt du job doit porter les trois
# consignes de la section B (contrat de prompt), dans l'ordre de priorité, et aucune consigne ne
# doit finir par un point d'interrogation (en CI personne ne répond : une question vaut abandon).
# Le rendu imite le workflow : substitution des variables, puis concaténation du prompt du job.
#   opencode/tests/prompt-contract-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PRE="$HERE/../ci-preamble.md"
WF="$HERE/../../.github/workflows/opencode-fullrun.yml"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

[ -f "$PRE" ] || { echo "FAIL préambule introuvable : $PRE"; exit 1; }

# Rendu : mêmes variables que le workflow (envsubst porté en perl, disponible partout).
cat > "$T/job-prompt.md" <<'JOB'
# Tâche du job (fixture)

Travaille le banc pub/jingle, commit souvent, écris le rapport.
JOB
perl -pe '
  BEGIN { %v = (
    TARGET_DIR => "/home/box/target", TARGET_REPO => "Galass_backend",
    OC_BRANCH => "feat/test", OC_REPORT => "/home/box/oc/REPORT.md", OC_JOB => "fixture",
    OC_MODEL_MAIN => "opencode/deepseek-v4.1-flash-free",
    OC_MODEL_MAX  => "opencode/deepseek-v4.1-flash-free",
    EXTRA_ROOT => "/home/box/extra", EXTRA_REPOS => "",
  ) }
  s/\$\{([A-Z_]+)\}/exists $v{$1} ? $v{$1} : "\${$1}"/ge;
  s/\$([A-Z_]+)/exists $v{$1} ? $v{$1} : "\$$1"/ge;
' "$PRE" > "$T/rendu.md"
cat "$T/job-prompt.md" >> "$T/rendu.md"

# 1. Les trois phrases, mot pour mot, dans l'ordre de priorité.
p1="Tu ne termines jamais ton tour par une question ni par une demande d'arbitrage : en CI personne ne répond, une question vaut abandon."
p2="Si une mesure contredit un ISC : consigne l'écart dans l'ISA (Log + claim), garde la garde en place, choisis l'option qui **ne réécrit pas** les seuils, commit, puis continue."
p3="Tout correctif annoncé comme non négociable est commité dans la même passe que l'annonce, et le rapport \`.fullrun/<job>_DONE.md\` est écrit avant la dernière phrase."

manquantes=0
n=0
for p in "$p1" "$p2" "$p3"; do
  n=$((n + 1))
  grep -qF "$p" "$T/rendu.md" || { echo "  phrase $n absente du prompt rendu"; manquantes=1; }
done
if [ "$manquantes" -eq 0 ]; then
  echo "ok 1 les trois consignes du contrat sont dans le prompt rendu"
else
  echo "FAIL 1 consigne(s) du contrat absente(s)"; fail=1
fi

# 2. Ordre de priorité : phrase 1 avant 2 avant 3.
i1=$(grep -nF "$p1" "$T/rendu.md" | head -1 | cut -d: -f1)
i2=$(grep -nF "$p2" "$T/rendu.md" | head -1 | cut -d: -f1)
i3=$(grep -nF "$p3" "$T/rendu.md" | head -1 | cut -d: -f1)
if [ -n "$i1" ] && [ -n "$i2" ] && [ -n "$i3" ] && [ "$i1" -lt "$i2" ] && [ "$i2" -lt "$i3" ]; then
  echo "ok 2 ordre de priorité respecté ($i1 < $i2 < $i3)"
else
  echo "FAIL 2 ordre de priorité incorrect : ${i1:-?} / ${i2:-?} / ${i3:-?}"; fail=1
fi

# 3. Aucune consigne ne finit par « ? » (lignes de directive : « 1. », « - », « * »).
consignes_interrogatives() { # <fichier> -> lignes fautives
  grep -nE '^[[:space:]]*([0-9]+[.)]|[-*])[[:space:]].*\?[[:space:]]*$' "$1" || true
}
fautives=$(consignes_interrogatives "$T/rendu.md")
if [ -z "$fautives" ]; then
  echo "ok 3 aucune consigne ne finit par un point d'interrogation"
else
  echo "FAIL 3 consigne interrogative :"; printf '%s\n' "$fautives"; fail=1
fi

# 4. Contrôle négatif : le détecteur attrape bien une consigne qui finit par « ? ».
printf -- '- Veux-tu continuer sur cette piste ?\n' > "$T/negatif.md"
if [ -n "$(consignes_interrogatives "$T/negatif.md")" ]; then
  echo "ok 4 contrôle négatif : une consigne interrogative est détectée"
else
  echo "FAIL 4 le détecteur ne voit pas une consigne interrogative (test invalide)"; fail=1
fi

# 5. Le workflow injecte bien CE préambule avant le prompt du job (pas un autre fichier).
if grep -qF '< "$CI_DIR/opencode/ci-preamble.md" > "$OC_WORK/prompt.md"' "$WF" \
   && grep -qF 'cat "$p" >> "$OC_WORK/prompt.md"' "$WF"; then
  echo "ok 5 le préambule est concaténé au prompt du job par le workflow"
else
  echo "FAIL 5 le workflow n'injecte pas le préambule attendu"; fail=1
fi

# 6. Le préambule dit qu'une fin de tour sans PASS est une reprise (la règle survit à toute
#    réécriture : un agent qui lit ce texte ne doit pas croire qu'il peut s'arrêter sans verdict).
if grep -qi 'fin de tour sans PASS' "$PRE" && grep -qi 'relance une session' "$PRE"; then
  echo "ok 6 le préambule porte la règle « fin de tour ≠ fin de run »"
else
  echo "FAIL 6 règle de fin de tour absente du préambule"; fail=1
fi

exit $fail
