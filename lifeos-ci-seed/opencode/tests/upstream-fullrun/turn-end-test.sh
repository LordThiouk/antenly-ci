#!/usr/bin/env bash
# Fin de tour ≠ terminé : un rc=0 d'opencode sans PASS de Max vérifié par done_check.sh est une
# reprise, jamais un succès ; reprises épuisées -> exit 127 et `arret=tour-fini`, jamais 0.
# Le faux opencode « finit son tour » en affichant une vraie phrase puis en sortant 0, sans
# marqueur de PASS ; le faux done_check.sh ($T/done_check) ne rend ok que si $T/done existe.
#   opencode/tests/turn-end-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R="$HERE/../../run-fullrun.sh"
WF="$HERE/../../../.github/workflows/opencode-fullrun.yml"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

cat >"$T/done_check" <<S
#!/usr/bin/env bash
[ -f "$T/done" ] && echo done_check=ok || echo done_check=ko raison=a:none
S
chmod +x "$T/done_check"

# Faux opencode piloté par $T/mode ; n = numéro d'appel. Marque $T/done sur un vrai succès.
mk() {
  cat >"$T/oc" <<S
#!/usr/bin/env bash
T_DIR="$T"
n=\$(cat "\$T_DIR/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"\$T_DIR/n"
printf 'call %s: %s\n' "\$n" "\$*" >>"\$T_DIR/calls"
mode=\$(cat "\$T_DIR/mode")
case "\$mode" in
  # Tour fini : le modèle rend la main (question, récapitulatif) au lieu de conclure.
  tour-always)
    echo "Récapitulatif du tour : je m'arrête ici, dis-moi si je continue."; exit 0 ;;
  # Un tour fini, puis une reprise qui conclut réellement (PASS marqué).
  tour-then-pass)
    if [ "\$n" -ge 2 ]; then echo "Travail repris et terminé."; : >"\$T_DIR/done"; exit 0; fi
    echo "Je m'arrête à la fin de ce tour."; exit 0 ;;
  # Succès immédiat et vérifié.
  pass-direct)
    echo "Tout est fait, PASS rendu."; : >"\$T_DIR/done"; exit 0 ;;
  # Aucun token utile : réponse vide (rc 0, bannière seule) -> 126, jamais 127.
  banner-only)
    printf '> Nix/LifeOS · deepseek-v4.1-flash-free\n'; exit 0 ;;
  *)
    echo "mode inconnu" >&2; exit 2 ;;
esac
S
  chmod +x "$T/oc"
  rm -f "$T/n" "$T/done" "$T/log" "$T/log.status" "$T/log.act" "$T/calls"
  mkdir -p "$T/a" "$T/store" "$T/agents" "$T/internals"; echo p >"$T/p"; echo "$1" >"$T/mode"
}

run() { # $1 = reprises max, $2 = sonde --continue en secondes
  ANTENLY_DIR="$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=m \
  OC_MODEL_CHAIN=opencode/fb-free OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) \
  OC_IDLE_MIN=20 OC_IDLE_SEC=3 OC_POLL_SEC=1 OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC="$2" \
  OC_STORE_DIR="$T/store" OC_BIN="$T/oc" OC_STALL_RESUMES="$1" OC_AGENT_DIR="$T/agents" \
  OC_DONE_CHECK_BIN="$T/done_check" OC_INTERNAL_LOG="$T/log.internal" \
  OC_INTERNAL_LOG_DIR="$T/internals" bash "$R"
}
calls() { cat "$T/calls" 2>/dev/null || true; }

# 1. Le cas du run 43776402123 : rc=0, tokens utiles, aucun PASS, reprises épuisées.
#    Attendu : 127 + arret=tour-fini ; surtout PAS 0 avec « terminé ».
mk tour-always; run 0 0; rc=$?
if [ "$rc" -eq 127 ] \
   && grep -qx 'main_rc=0' "$T/log.status" \
   && grep -qx 'arret=tour-fini' "$T/log.status" \
   && ! grep -q 'arret=max_pass' "$T/log.status"; then
  echo "ok 1 fin de tour sans PASS -> rc 127, arret=tour-fini"
else
  echo "FAIL 1 rc=$rc"; calls; tail -n 8 "$T/log.status"; fail=1
fi

# 2. Un PASS vérifié par done_check.sh reste un vrai succès (rc 0, arret=max_pass, une passe).
mk pass-direct; run 0 0; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$T/n")" -eq 1 ] \
   && grep -qx 'arret=max_pass' "$T/log.status" \
   && grep -qx 'done_check=ok' "$T/log.status"; then
  echo "ok 2 PASS vérifié -> rc 0, arret=max_pass, aucune reprise"
else
  echo "FAIL 2 rc=$rc n=$(cat "$T/n")"; calls; tail -n 8 "$T/log.status"; fail=1
fi

# 3. Un tour fini déclenche une reprise (session neuve) qui, elle, conclut : rc 0, pas 127.
mk tour-then-pass; run 1 0; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$T/n")" -eq 2 ] \
   && grep -q '^\[stall\] fin de tour ou silence, reprise 1/1' "$T/log" \
   && grep -qx 'stall_resume=1' "$T/log.status" \
   && grep -qx 'new_session=1' "$T/log.status" \
   && grep -qx 'arret=max_pass' "$T/log.status"; then
  echo "ok 3 fin de tour -> reprise -> PASS, rc 0"
else
  echo "FAIL 3 rc=$rc n=$(cat "$T/n")"; calls; tail -n 10 "$T/log.status"; fail=1
fi

# 4. Que des fins de tour : les reprises sont bornées, l'épuisement rend 127, jamais 0.
mk tour-always; run 2 0; rc=$?
if [ "$rc" -eq 127 ] && [ "$(cat "$T/n")" -eq 3 ] \
   && grep -qx 'stall_resume=2' "$T/log.status" \
   && grep -qx 'arret=tour-fini' "$T/log.status"; then
  echo "ok 4 reprises épuisées sur fins de tour -> rc 127"
else
  echo "FAIL 4 rc=$rc n=$(cat "$T/n")"; calls; tail -n 10 "$T/log.status"; fail=1
fi

# 5. Réponse vide (aucun token) : 126 l'emporte, le run n'est pas requalifié en fin de tour.
mk banner-only; run 0 0; rc=$?
if [ "$rc" -eq 126 ] && grep -qx 'arret=vide' "$T/log.status"; then
  echo "ok 5 réponse vide -> rc 126 (précédence sur 127)"
else
  echo "FAIL 5 rc=$rc"; tail -n 8 "$T/log.status"; fail=1
fi

# 6. Contrat du workflow : 127 -> stop=tour, et le Statut final ne dit « terminé » que si DONE=ok.
if grep -qF '127) stop=tour; why="fin de tour sans PASS (à reprendre)"' "$WF" \
   && grep -qF 'tour) why="fin de tour sans PASS (${DONE_REASON:-a:none})"' "$WF" \
   && grep -qF 'ok_why="fin de tour sans PASS (${DONE_REASON:-a:none})"' "$WF" \
   && grep -qF 'ok) why="$ok_why"' "$WF" \
   && grep -qF '::error::run en échec : PASS requis non vérifié' "$WF"; then
  echo "ok 6 workflow : 127 -> tour, « terminé » conditionné au PASS, barrière intacte"
else
  echo "FAIL 6 contrat du workflow"; grep -n 'stop=tour\|ok_why\|Statut final' "$WF" | head; fail=1
fi

exit $fail
