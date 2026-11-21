#!/usr/bin/env bash
# Reprise après stall : sonde --continue courte, sinon session neuve ; repli modèle ; erreurs typées.
# Depuis la règle « fin de tour ≠ terminé », un rc=0 sans PASS vérifié n'est plus un succès : le
# faux opencode marque donc $T/done sur ses chemins de succès, et un faux done_check.sh factice
# ($T/done_check) ne rend `done_check=ok` que si ce marqueur existe. Les cas qui attendent rc=0
# décrivent ainsi un VRAI succès (Max PASS confirmé), pas un simple retour du modèle.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R="$HERE/../run-fullrun.sh"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# Faux validateur de fin : PASS uniquement si la passe a marqué une fin réussie.
cat >"$T/done_check" <<S
#!/usr/bin/env bash
[ -f "$T/done" ] && echo done_check=ok || echo done_check=ko raison=a:none
S
chmod +x "$T/done_check"

# Faux opencode piloté par $T/mode. Écrit ses arguments dans $T/calls (jamais dans le journal).
mk() { # $1 = comportement
  cat >"$T/oc" <<S
#!/usr/bin/env bash
T_DIR="$T"
n=\$(cat "\$T_DIR/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"\$T_DIR/n"
printf 'call %s: %s\n' "\$n" "\$*" >>"\$T_DIR/calls"
printf 'env %s: OC_MODEL_MAIN=%s\n' "\$n" "\${OC_MODEL_MAIN:-}" >>"\$T_DIR/calls"
printf 'envfullrun %s: %s\n' "\$n" "\${LIFEOS_FULLRUN:-}" >>"\$T_DIR/calls"
printf 'envprofile %s: %s\n' "\$n" "\${LIFEOS_HOOK_PROFILE:-}" >>"\$T_DIR/calls"
mode=\$(cat "\$T_DIR/mode")
cont=0; for a in "\$@"; do [ "\$a" = "--continue" ] && cont=1; done
banner() { printf '> Nix/LifeOS · deepseek-v4.1-flash-free\n'; }
ok_fin() { echo fini; : >"\$T_DIR/done"; exit 0; }
hang() { end=\$((SECONDS+30)); while [ \$SECONDS -lt \$end ]; do :; done; }
case "\$mode" in
  hang-then-ok)
    [ \$n -ge 2 ] && ok_fin; hang ;;
  hang-always)
    hang ;;
  continue-empty)
    [ \$n -eq 1 ] && hang
    if [ \$cont = 1 ]; then banner; exit 0; fi
    ok_fin ;;
  ok-after-done)
    ok_fin ;;
  provider)
    [ \$n -eq 1 ] && { echo "erreur fournisseur"; exit 1; }
    ok_fin ;;
  ratelimit)
    [ \$n -eq 1 ] && { echo "429 Too Many Requests"; exit 1; }
    ok_fin ;;
  empty-always)
    banner; exit 0 ;;
  big-ok)
    banner; head -c 1500000 /dev/zero | tr '\\0' 'x' | fold -w 200; echo; ok_fin ;;
  hang-subagent)
    printf 'dispatch subagent Max (task)\\n'; hang ;;
  chain-rotate)
    case \$n in
      1) hang ;;
      2) banner; exit 0 ;;
      3) echo "encore bloque"; exit 1 ;;
      *) ok_fin ;;
    esac ;;
  error-idle)
    [ \$n -eq 1 ] && { echo "[agent-error] type=timeout"; hang; }
    ok_fin ;;
  error-empty)
    [ \$n -eq 1 ] && { echo "[agent-error] type=empty"; hang; }
    ok_fin ;;
  error-429)
    [ \$n -eq 1 ] && { echo "[agent-error] type=429"; hang; }
    ok_fin ;;
  *)
    echo "mode inconnu" >&2; exit 2 ;;
esac
S
  chmod +x "$T/oc"
  rm -f "$T/n" "$T/done" "$T/log" "$T/log.status" "$T/log.act" "$T/calls" "$T/log.internal" "$T/log.internal.stamp"
  mkdir -p "$T/a" "$T/store" "$T/agents" "$T/internals"; echo p >"$T/p"; echo "$1" >"$T/mode"
}

run() { # $1 = reprises max, $2 = sonde --continue en secondes
  ANTENLY_DIR="$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=m OC_MODEL_FALLBACK=opencode/fb-free \
  OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 OC_IDLE_SEC=3 OC_POLL_SEC=1 OC_KILL_GRACE=1 \
  OC_CONTINUE_PROBE_SEC="$2" OC_STORE_DIR="$T/store" OC_BIN="$T/oc" OC_STALL_RESUMES="$1" \
  OC_AGENT_DIR="$T/agents" OC_DONE_CHECK_BIN="$T/done_check" OC_INTERNAL_LOG="$T/log.internal" OC_INTERNAL_LOG_DIR="$T/internals" bash "$R"
}
calls() { cat "$T/calls" 2>/dev/null || true; }

# Chaîne de secours : OC_MODEL_CHAIN explicite (le principal est filtré par le script).
run_chain() { # $1 = chaîne, $2 = reprises (vide = défaut), $3 = sonde
  ANTENLY_DIR="$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=m \
  OC_MODEL_CHAIN="$1" OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 OC_IDLE_SEC=3 \
  OC_POLL_SEC=1 OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC="${3:-0}" OC_STORE_DIR="$T/store" \
  OC_BIN="$T/oc" OC_STALL_RESUMES="${2:-}" OC_AGENT_DIR="$T/agents" OC_DONE_CHECK_BIN="$T/done_check" OC_INTERNAL_LOG="$T/log.internal" OC_INTERNAL_LOG_DIR="$T/internals" bash "$R"
}


# Variante : OC_SUBAGENT_IDLE_SEC court, OC_IDLE_SEC long, pour prouver que le seuil sous-agent
# est bien le plus court des deux et qu'il est étiqueté (subagent_timeout=1).
run_sub() { # $1 = reprises max, $2 = sonde, $3 = seuil sous-agent
  ANTENLY_DIR="$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=m OC_MODEL_FALLBACK=opencode/fb-free \
  OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 OC_IDLE_SEC=30 OC_POLL_SEC=1 OC_KILL_GRACE=1 \
  OC_CONTINUE_PROBE_SEC="$2" OC_STORE_DIR="$T/store" OC_BIN="$T/oc" OC_STALL_RESUMES="$1" \
  OC_SUBAGENT_IDLE_SEC="$3" OC_AGENT_DIR="$T/agents" OC_DONE_CHECK_BIN="$T/done_check" OC_INTERNAL_LOG="$T/log.internal" OC_INTERNAL_LOG_DIR="$T/internals" bash "$R"
}

run_err() { # $1 = reprises max, $2 = OC_ERROR_IDLE_SEC, $3 = OC_IDLE_SEC (silence normal)
  ANTENLY_DIR="$T/a" OC_PROMPT_FILE="$T/p" OC_LOG="$T/log" OC_MODEL_MAIN=m \
  OC_MODEL_CHAIN="opencode/glm-free,opencode/mini-free" \
  OC_DEADLINE_EPOCH=$(( $(date +%s) + 3600 )) OC_IDLE_MIN=20 OC_IDLE_SEC="$3" \
  OC_ERROR_IDLE_SEC="$2" OC_POLL_SEC=1 OC_KILL_GRACE=1 OC_CONTINUE_PROBE_SEC=2 \
  OC_STORE_DIR="$T/store" OC_BIN="$T/oc" OC_STALL_RESUMES="$1" OC_AGENT_DIR="$T/agents" \
  OC_DONE_CHECK_BIN="$T/done_check" OC_INTERNAL_LOG="$T/log.internal" OC_INTERNAL_LOG_DIR="$T/internals" bash "$R"
}

# 1. silence puis reprise réussie (la sonde --continue parle) — cas déjà couvert.
mk hang-then-ok; run 3 2; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^\[stall\] .*reprise 1/3' "$T/log" \
   && grep -q '^call 2: run --continue --model opencode/fb-free' "$T/calls" \
   && grep -q '^\[agent-error\] type=timeout' "$T/log"; then
  echo "ok 1 silence puis reprise réussie"
else
  echo "FAIL 1 rc=$rc"; calls; tail -n 8 "$T/log"; tail -n 8 "$T/log.status"; fail=1
fi

# 2. reprises bornées puis arrêt silence — cas déjà couvert (chaque reprise = sonde + session neuve).
mk hang-always; run 2 2; rc=$?
if [ "$rc" -eq 125 ] && [ "$(cat "$T/n")" -eq 5 ] && grep -q '^arret=silence' "$T/log.status"; then
  echo "ok 2 reprises bornées puis arrêt silence"
else
  echo "FAIL 2 rc=$rc n=$(cat "$T/n")"; calls; tail -n 8 "$T/log.status"; fail=1
fi

# 3. --continue muet (bannière seule) : la piste est abandonnée, l'appel suivant est une session
#    NEUVE (sans --continue) avec le message de reprise.
mk continue-empty; run 3 2; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -q '^call 2: run --continue --model opencode/fb-free' "$T/calls" \
   && grep -q '^call 3: run --model opencode/fb-free' "$T/calls" \
   && ! grep -q '^call 3: .*--continue' "$T/calls" \
   && grep -q '^\[agent-error\] type=empty' "$T/log" \
   && grep -q 'nouvelle session' "$T/log"; then
  echo "ok 3 --continue muet -> nouvelle session"
else
  echo "FAIL 3 rc=$rc"; calls; tail -n 8 "$T/log"; tail -n 8 "$T/log.status"; fail=1
fi

# 4. erreur fournisseur : repli sur le modèle fallback et type=provider.
mk provider; run 3 2; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^call 2: run --continue --model opencode/fb-free' "$T/calls" \
   && grep -q '^\[agent-error\] type=provider' "$T/log"; then
  echo "ok 4 erreur fournisseur -> fallback"
else
  echo "FAIL 4 rc=$rc"; calls; tail -n 8 "$T/log.status"; fail=1
fi

# 5. 429 : repli sur le modèle fallback et type=429.
mk ratelimit; run 3 2; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^call 2: run --continue --model opencode/fb-free' "$T/calls" \
   && grep -q '^\[agent-error\] type=429' "$T/log"; then
  echo "ok 5 429 -> fallback"
else
  echo "FAIL 5 rc=$rc"; calls; tail -n 8 "$T/log.status"; fail=1
fi

# 6. réponses vides épuisées : jamais un succès (rc 126), reprises bornées.
mk empty-always; run 1 2; rc=$?
if [ "$rc" -eq 126 ] && [ "$(cat "$T/n")" -eq 3 ] \
   && grep -q '^arret=vide' "$T/log.status" \
   && grep -q '^\[agent-error\] type=empty' "$T/log"; then
  echo "ok 6 réponses vides épuisées -> rc 126"
else
  echo "FAIL 6 rc=$rc n=$(cat "$T/n")"; calls; tail -n 8 "$T/log.status"; fail=1
fi

# 7. sortie > 1 Mo, rc 0 : un vrai succès (pas un faux « vide » dû au SIGPIPE de grep -q sous
#    pipefail), aucune reprise, aucune erreur.
mk big-ok; run 3 2; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$T/n")" -eq 1 ] \
   && [ "$(stat -c %s "$T/log")" -gt 1000000 ] \
   && ! grep -q '^\[agent-error\]' "$T/log" \
   && ! grep -q '^error=' "$T/log.status" \
   && ! grep -q 'stall_resume' "$T/log.status"; then
  echo "ok 7 sortie > 1 Mo rc 0 -> succès sans reprise"
else
  echo "FAIL 7 rc=$rc n=$(cat "$T/n")"; calls; tail -n 8 "$T/log.status"; fail=1
fi

# 8. sous-agent muet : seuil OC_SUBAGENT_IDLE_SEC (2 s) plus court que OC_IDLE_SEC (30 s) →
#    coupure rapide, type=timeout, subagent_timeout=1, puis reprise normale.
mk hang-subagent; run_sub 1 0 2; rc=$?
if [ "$rc" -eq 125 ] \
   && grep -q '^\[agent-error\] type=timeout' "$T/log" \
   && grep -q '^error=timeout' "$T/log.status" \
   && grep -q '^subagent_timeout=1' "$T/log.status" \
   && [ "$(cat "$T/n")" -eq 2 ]; then
  echo "ok 8 sous-agent muet -> seuil 8 min et subagent_timeout=1"
else
  echo "FAIL 8 rc=$rc n=$(cat "$T/n")"; calls; tail -n 8 "$T/log.status"; fail=1
fi

# 9. chaîne de secours : rotation sur les reprises, OC_MODEL_MAIN transmis à l'enfant, statut
#    fallback=<modèle>.
mk chain-rotate; run_chain "opencode/glm-free,opencode/mini-free" 2 2; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -q '^call 2: run --continue --model opencode/glm-free' "$T/calls" \
   && grep -q '^env 2: OC_MODEL_MAIN=opencode/glm-free' "$T/calls" \
   && grep -q '^call 3: run --model opencode/glm-free' "$T/calls" \
   && grep -q '^call 4: run --continue --model opencode/mini-free' "$T/calls" \
   && grep -q '^fallback=opencode/glm-free' "$T/log.status" \
   && grep -q '^fallback=opencode/mini-free' "$T/log.status"; then
  echo "ok 9 chaîne de secours -> rotation + OC_MODEL_MAIN"
else
  echo "FAIL 9 rc=$rc"; calls; tail -n 8 "$T/log.status"; fail=1
fi

# 10. le principal est retiré de la chaîne ; agent/*.md (Max compris) réécrits vers le secours.
mk continue-empty
printf 'model: opencode/old-free\n' >"$T/agents/Max.md"
printf 'model: opencode/old-free\n' >"$T/agents/Engineer.md"
run_chain "m,opencode/glm-free" 1 2; rc=$?
if [ "$rc" -eq 0 ] \
   && ! grep -q '^call [23]: .*--model m' "$T/calls" \
   && grep -q '^call 2: run --continue --model opencode/glm-free' "$T/calls" \
   && grep -q '^model: opencode/glm-free$' "$T/agents/Max.md" \
   && grep -q '^model: opencode/glm-free$' "$T/agents/Engineer.md"; then
  echo "ok 10 principal filtré + agent/*.md réécrits"
else
  echo "FAIL 10 rc=$rc"; calls; tail -n 4 "$T/agents/Max.md"; tail -n 8 "$T/log.status"; fail=1
fi

# 11. élément non gratuit -> erreur d'environnement 90, rien n'est lancé.
mk continue-empty; run_chain "opencode/paid-model" 1 0; rc=$?
if [ "$rc" -eq 90 ] && [ ! -f "$T/calls" ]; then
  echo "ok 11 modèle non gratuit -> 90"
else
  echo "FAIL 11 rc=$rc"; calls; fail=1
fi

# 12. chaîne vide après filtrage (réduite au principal) -> 90.
mk continue-empty; run_chain "m" 1 0; rc=$?
if [ "$rc" -eq 90 ] && [ ! -f "$T/calls" ]; then
  echo "ok 12 chaîne réduite au principal -> 90"
else
  echo "FAIL 12 rc=$rc"; calls; fail=1
fi

# 13. signal « vrai FullRun » : le wrapper transmet LIFEOS_FULLRUN=1 (et le profil fullrun) au
#     processus opencode ; un lancement hors wrapper ne l'a pas. Le test tourne dans un shell
#     nettoyé de ces variables pour prouver que c'est bien le wrapper qui les pose.
mk big-ok
( env -u LIFEOS_FULLRUN -u LIFEOS_HOOK_PROFILE "$T/oc" run hors-wrapper ) >/dev/null 2>&1
run 1 0; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -q '^envfullrun 1: $' "$T/calls" \
   && grep -q '^envfullrun 2: 1$' "$T/calls" \
   && grep -q '^envprofile 2: fullrun$' "$T/calls"; then
  echo "ok 13 LIFEOS_FULLRUN=1 transmis par le wrapper, absent hors wrapper"
else
  echo "FAIL 13 rc=$rc"; calls; fail=1
fi

# 14. ok-after-done : PASS de Max confirmé dès la première passe -> rc 0, arret=max_pass,
#     done_check=ok, un seul appel (pas de reprise inutile).
mk ok-after-done; run 2 0; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$T/n")" -eq 1 ] \
   && grep -qx 'done_check=ok' "$T/log.status" \
   && grep -qx 'arret=max_pass' "$T/log.status" \
   && ! grep -q 'stall_resume' "$T/log.status"; then
  echo "ok 14 ok-after-done -> done_check=ok, arret=max_pass, rc 0, un seul appel"
else
  echo "FAIL 14 rc=$rc n=$(cat "$T/n")"; calls; tail -n 8 "$T/log.status"; fail=1
fi

# 15. défaut 2 : une erreur agent timeout écrite pendant la passe, puis plus aucune activité, coupe
#     la passe après OC_ERROR_IDLE_SEC (2 s) et reprend sur la chaîne — bien avant le silence normal
#     (10 s). Même compteur (1/2), même statut fallback que la reprise sur silence.
mk error-idle
t0=$(date +%s); run_err 2 2 10; rc=$?; dt=$(( $(date +%s) - t0 ))
if [ "$rc" -eq 0 ] && [ "$dt" -lt 9 ] \
   && grep -q '^\[agent-error\] type=timeout' "$T/log" \
   && grep -q '^\[stall\] .*reprise 1/2' "$T/log" \
   && grep -q '^call 2: run --continue --model opencode/glm-free' "$T/calls" \
   && grep -q '^fallback=opencode/glm-free' "$T/log.status" \
   && grep -q '^error=timeout' "$T/log.status"; then
  echo "ok 15 erreur timeout + silence court -> repli immédiat sur la chaîne (${dt}s)"
else
  echo "FAIL 15 rc=$rc dt=${dt}s"; calls; tail -n 10 "$T/log"; tail -n 10 "$T/log.status"; fail=1
fi

# 16. même chose avec une erreur empty.
mk error-empty
t0=$(date +%s); run_err 2 2 10; rc=$?; dt=$(( $(date +%s) - t0 ))
if [ "$rc" -eq 0 ] && [ "$dt" -lt 9 ] \
   && grep -q '^\[agent-error\] type=empty' "$T/log" \
   && grep -q '^call 2: run --continue --model opencode/glm-free' "$T/calls" \
   && grep -q '^fallback=opencode/glm-free' "$T/log.status" \
   && grep -q '^error=empty' "$T/log.status"; then
  echo "ok 16 erreur empty + silence court -> repli immédiat (${dt}s)"
else
  echo "FAIL 16 rc=$rc dt=${dt}s"; calls; tail -n 10 "$T/log"; tail -n 10 "$T/log.status"; fail=1
fi

# 17. marqueur 429 : comportement INTACT — aucune coupure anticipée, le seuil de silence normal (10 s)
#     fait foi, aucun modèle de secours n'est lancé ici (reprises désactivées pour isoler la passe).
mk error-429
t0=$(date +%s); run_err 0 2 10; rc=$?; dt=$(( $(date +%s) - t0 ))
if [ "$rc" -eq 125 ] && [ "$dt" -ge 9 ] && [ "$(cat "$T/n")" -eq 1 ] \
   && grep -q '^\[agent-error\] type=429' "$T/log" \
   && grep -qx 'arret=silence' "$T/log.status" \
   && ! grep -q '^fallback=' "$T/log.status"; then
  echo "ok 17 marqueur 429 -> seuil de silence normal conservé (${dt}s), pas de repli anticipé"
else
  echo "FAIL 17 rc=$rc dt=${dt}s n=$(cat "$T/n")"; calls; tail -n 10 "$T/log.status"; fail=1
fi

# 18. la variable est câblée dans l'env du step opencode du workflow (défaut 240 s).
if grep -q 'OC_ERROR_IDLE_SEC:' "$HERE/../../.github/workflows/opencode-fullrun.yml" \
   && grep -q 'OC_ERROR_IDLE_SEC:-240' "$R"; then
  echo "ok 18 OC_ERROR_IDLE_SEC câblée dans le workflow, défaut 240 s"
else
  echo "FAIL 18 variable non câblée"; fail=1
fi

# 19. OC_ERROR_IDLE_SEC invalide -> erreur d'environnement 90, rien n'est lancé (jamais avalée).
mk ok-after-done; run_err 2 abc 10; rc=$?
if [ "$rc" -eq 90 ] && [ ! -f "$T/calls" ]; then
  echo "ok 19 OC_ERROR_IDLE_SEC invalide -> 90, opencode jamais lancé"
else
  echo "FAIL 19 rc=$rc"; calls; fail=1
fi

exit $fail
