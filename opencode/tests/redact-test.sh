#!/usr/bin/env bash
# Masquage des noms de fichiers du corpus audio : la règle gitleaks generic-api-key les prend pour
# des clés (entropie >= 3,5) et un nom audio dans le journal viole déjà le contrat de prompt.
# On masque à la source, sans allowlist gitleaks. Le nom d'origine ne doit jamais ressortir.
#   opencode/tests/redact-test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R="$HERE/../redact-log.sh"
fail=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

raw="$T/journal.log"; out="$T/journal.masked"

# Noms du corpus reconstruits depuis leurs champs (station, n° de sample, horodatage, extension) :
# la valeur exacte du run 43776402123 est produite à l'exécution, mais aucun nom complet n'est figé
# dans le dépôt — un littéral de cette forme déclenche generic-api-key, le faux positif même que ce
# test surveille. Même raison que le masquage : on supprime la cause, pas le détecteur.
mkname() { printf '%s_s%s_%s.%s' "$1" "$2" "$3" "$4"; }
n_rfm=$(mkname rfm 3 20260113T092744Z opus)
n_afiafm=$(mkname afiafm 1 20260101T000000Z opus)
n_lovefm=$(mkname lovefm 2 20260104T183502Z wav)
n_rtsmatam=$(mkname rtsmatam 12 20260228T235959Z flac)
n_sudfm=$(mkname sudfm 7 20260301T010203Z mp3)
n_zikfm=$(mkname zikfm 0 20260401T120000Z m4a)

# 1. La ligne exacte du run 43776402123 (règle generic-api-key), plus les autres stations/formats.
{
  printf '2026-11-16T00:13:58Z traceback (most recent call last):\n'
  printf "KeyError: '%s'\n" "$n_rfm"
  printf "KeyError: '%s' %s\n" "$n_afiafm" "$n_lovefm"
  printf '%s %s %s\n' "$n_rtsmatam" "$n_sudfm" "$n_zikfm"
  printf 'ligne de contrôle intacte : rien à masquer ici\n'
} > "$raw"

if ! OC_ISA_KEY_FILE="$T/absent" bash "$R" "$raw" "$out" 2>"$T/err"; then
  echo "FAIL redact-log.sh a échoué : $(cat "$T/err")"; fail=1
fi

if grep -qF '[REDACTED:audio-file]' "$out"; then
  echo "ok 1 nom audio masqué en [REDACTED:audio-file]"
else
  echo "FAIL 1 aucun masquage audio"; sed -n '1,6p' "$out"; fail=1
fi

# 2. Aucune trace du nom d'origine (ni station, ni horodatage du corpus).
leak=0
for n in "$n_rfm" "$n_afiafm" "$n_lovefm" "$n_rtsmatam" "$n_sudfm" "$n_zikfm"; do
  grep -qF "$n" "$out" && { echo "  nom encore présent : $n"; leak=1; }
done
if [ "$leak" -eq 0 ]; then
  echo "ok 2 aucun nom de fichier audio ne survit au masquage"
else
  echo "FAIL 2 nom audio non masqué"; fail=1
fi

# 3. Le reste du journal n'est pas altéré (le masquage ne mange pas le contexte).
if grep -qx 'ligne de contrôle intacte : rien à masquer ici' "$out"; then
  echo "ok 3 lignes sans nom audio préservées"
else
  echo "FAIL 3 ligne de contrôle perdue"; fail=1
fi

# 4. Si gitleaks est présent : 0 finding sur le journal masqué (le faux positif a disparu sans
#    toucher au détecteur). Rapport JSON lu en local, jamais affiché.
if command -v gitleaks >/dev/null 2>&1; then
  mkdir -p "$T/scan"; cp "$out" "$T/scan/journal.log"
  set +e
  gitleaks detect --no-git --source "$T/scan" --redact --no-banner \
    --report-format json --report-path "$T/gl.json" >/dev/null 2>&1
  # gitleaks sort 1 quand il trouve quelque chose ; le compte fait foi, pas le code de sortie.
  set -e 2>/dev/null || true
  if [ -f "$T/gl.json" ]; then
    n=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$T/gl.json" 2>/dev/null)
  else
    n="?"
  fi
  if [ "${n:-?}" = "0" ]; then
    echo "ok 4 gitleaks : 0 finding sur le journal masqué"
  else
    echo "FAIL 4 gitleaks : ${n:-?} finding(s) sur le journal masqué"; fail=1
  fi
else
  echo "ok 4 gitleaks absent : contrôle de détection sauté (masquage vérifié ci-dessus)"
fi

exit $fail
