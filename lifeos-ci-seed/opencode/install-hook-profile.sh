#!/usr/bin/env bash
# Copie hook-profiles depuis le checkout LifeOS vers le répertoire de config
# opencode. Le plugin lifeos-hooks lit plugins/../hook-profiles/fullrun.json.
# Un profil qui tente de désactiver un garde-fou est refusé (arrêt immédiat).
# Usage : install-hook-profile.sh <racine-lifeos> <dir-config-opencode>
set +x
set -euo pipefail

err() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    # Annotation utiles aux logs CI, mais le refus doit rester lisible sur stderr : c'est là que
    # les appelants et les tests le lisent (sinon le refus passe pour un silence).
    echo "::error::$1" >&2
  else
    echo "$1" >&2
  fi
  exit 1
}

if [ "$#" -ne 2 ]; then
  echo "usage: install-hook-profile.sh <racine-lifeos> <dir-config-opencode>" >&2
  exit 2
fi

LIFEOS="$1"
DEST="$2"
SRC="$LIFEOS/opencode/hook-profiles"
PROFILE="$SRC/fullrun.json"

# Mêmes noms que PROTECTED_HOOKS dans LifeOS (opencode/plugins/lib/hook-profile.ts).
# Suffixe .hook.ts / .hook.sh accepté : on compare le nom nu.
PROTECTED_HOOKS=(
  Safety
  PreToolGuard
  FullRunGate
  ISAStaleWriteGuard
  StopGates
  ISASync
  TaskGovernance
  ContextReduction
  KnowledgeWriteGuard
  ComplexityRatchet
  ModelRungGuard
  CheckpointPerISC
  SkillGuard
  AgentGuard
  CommunicationSkillGuard
  CompleteStampGate
  DeployRegistrationGate
  EgressClassGuard
  ISACloseGate
  ISAFoldGate
  ISAGate
  PublicPushGate
  SystemFileGuard
  VerificationGate
  VoiceEgressGuard
  WritingGate
)

[ -d "$LIFEOS/opencode" ] || err "lifeos sans dossier opencode/: $LIFEOS"
[ -d "$SRC" ] || err "hook-profiles absent du checkout LifeOS: $SRC"
[ -f "$PROFILE" ] || err "hook-profiles/fullrun.json absent du checkout LifeOS"
[ -d "$DEST" ] || err "répertoire de config opencode absent: $DEST"
command -v jq >/dev/null 2>&1 || err "jq est requis pour valider fullrun.json"

jq -e 'type == "object" and (.disable | type == "array")' "$PROFILE" >/dev/null \
  || err "fullrun.json invalide (objet {disable: []} attendu)"

prot_json=$(printf '%s\n' "${PROTECTED_HOOKS[@]}" | jq -R . | jq -s .)
rejected=$(jq -r --argjson prot "$prot_json" '
  .disable
  | map(select(. != null and (. | tostring) != ""))
  | map(tostring)
  | map(select((sub("\\.hook\\.(ts|sh)$"; "")) as $b | $prot | index($b)))
  | unique
  | join(", ")
' "$PROFILE")

if [ -n "$rejected" ]; then
  err "profil fullrun coupe des garde-fous : $rejected"
fi

rm -rf "$DEST/hook-profiles"
cp -a "$SRC" "$DEST/hook-profiles"
[ -f "$DEST/hook-profiles/fullrun.json" ] || err "copie hook-profiles/fullrun.json échouée"

# Chemin exact lu par le plugin : ${import.meta.dir}/../hook-profiles/fullrun.json
if [ -d "$DEST/plugins" ]; then
  [ -f "$DEST/plugins/../hook-profiles/fullrun.json" ] \
    || err "hook-profiles/fullrun.json inaccessible depuis plugins/"
fi

echo "hook-profiles/fullrun.json installé dans $DEST/hook-profiles"
