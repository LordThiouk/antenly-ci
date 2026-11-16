#!/usr/bin/env bash
# Prépare le journal opencode pour le dépôt PRIVÉ antenly : tronque le brut à OC_LOG_MAX octets
# (défaut 5 Mo, début et fin gardés) AVANT tout perl, puis retire les codes ANSI, masque les motifs
# de jetons courants, la clé ISA et les noms de fichiers du corpus audio (que gitleaks prend pour
# des clés génériques à cause de leur entropie). Le perl -0777 ne voit donc qu'un fichier déjà borné : un journal
# énorme ne gonfle jamais la mémoire. Rien n'est écrit sur stdout.   redact-log.sh <log brut> <sortie>
set +x
set -uo pipefail
in="${1:?}"; out="${2:?}"
MAX="${OC_LOG_MAX:-5242880}"
[[ "$MAX" =~ ^[0-9]{4,9}$ ]] || MAX=5242880
[ -f "$in" ] || exit 3

# Coupe bornée : début + bandeau + fin, comme avant, mais sur le fichier d'entrée (jamais de slurp).
truncate_file() { # <source> <sortie> <taille totale annoncée>
  local src="$1" dst="$2" total="$3" head_b tail_b
  head_b=$(( MAX / 5 )); tail_b=$(( MAX - head_b - 512 ))
  {
    printf '[journal tronqué par antenly-ci : %s octets au total, début (%s o) et fin (%s o) conservés]\n\n' \
      "$total" "$head_b" "$tail_b"
    head -c "$head_b" "$src" | sed '$d'
    printf '\n[... %s octets omis ...]\n\n' "$(( total - head_b - tail_b ))"
    tail -c "$tail_b" "$src" | sed '1d'
  } > "$dst"
}

size=$(wc -c < "$in")
bounded="$in"; cut=""
if [ "$size" -gt "$MAX" ]; then
  cut=$(mktemp) || exit 3
  truncate_file "$in" "$cut" "$size" || { rm -f "$cut"; exit 4; }
  bounded="$cut"
fi

tmp=$(mktemp) || { [ -n "$cut" ] && rm -f "$cut"; exit 3; }
# La clé ISA est lue par perl depuis le fichier (jamais en argument ni en variable d'env).
OC_ISA_KEY_FILE="${OC_ISA_KEY_FILE:-$HOME/.claude/LIFEOS/MEMORY/STATE/.isa-stamp-key}" perl -0777 -pe '
  BEGIN {
    our $k = "";
    if (open(my $f, "<", $ENV{OC_ISA_KEY_FILE})) { local $/; $k = <$f> // ""; close $f; $k =~ s/\s+//g; }
  }
  s/\e\][^\a\e]*(?:\a|\e\\)//g;            # OSC
  s/\e\[[0-9;?]*[ -\/]*[@-~]//g;           # CSI
  s/\e[()][A-Za-z0-9]//g; s/\r(?!\n)/\n/g; s/\r//g;
  if (length($k) >= 32) { s/\Q$k\E/[REDACTED:isa-key]/gi; }
  s/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|\z)/[REDACTED:private-key]/gs;
  s/\bgithub_pat_[A-Za-z0-9_]{20,}/[REDACTED:github-pat]/g;
  s/\bgh[pousr]_[A-Za-z0-9]{20,}/[REDACTED:github-token]/g;
  s/\bhf_[A-Za-z0-9]{20,}/[REDACTED:hf-token]/g;
  s/\bsk-[A-Za-z0-9_-]{16,}/[REDACTED:sk-key]/g;
  s/\bxox[abposr]-[A-Za-z0-9-]{10,}/[REDACTED:slack-token]/g;
  s/\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/[REDACTED:aws-key]/g;
  s/\bAIza[0-9A-Za-z_-]{30,}/[REDACTED:google-key]/g;
  s/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/[REDACTED:jwt]/g;
  # Noms de fichiers du corpus audio (<station>_s<k>_<AAAAMMJJ>T<HHMMSS>Z.<ext>) : ce ne sont pas
  # des secrets, mais la règle gitleaks generic-api-key les prend pour des clés (entropie >= 3,5)
  # et imprimer un chemin audio dans le journal viole déjà le contrat de prompt. Masquage à la
  # source, sans allowlist gitleaks qui affaiblirait la détection des vrais jetons.
  # (Bloc délimité par des quotes simples côté shell : aucune apostrophe ici.)
  s/\b[a-z][a-z0-9]{0,15}_s\d{1,2}_\d{8}T\d{6}Z\.(?:opus|wav|mp3|m4a|flac|ogg|aac)\b/[REDACTED:audio-file]/g;
  s/(x-access-token:)[^\s@"\x27]+/$1\[REDACTED\]/gi;
  s/((?:authorization|proxy-authorization)\s*[:=]\s*(?:basic|bearer|token)\s+)[A-Za-z0-9._~+\/=-]{8,}/$1\[REDACTED\]/gi;
  s/(\bbearer\s+)[A-Za-z0-9._~+\/=-]{20,}/$1\[REDACTED\]/gi;
  s/(https?:\/\/[^\s:\/@]+:)[^\s@\/]+@/$1\[REDACTED\]@/g;
  s/(?<![0-9A-Fa-f])[0-9A-Fa-f]{64}(?![0-9A-Fa-f])/[REDACTED:hex64]/g;
' "$bounded" > "$tmp" 2>/dev/null || { rm -f "$tmp" "$cut"; exit 4; }
[ -n "$cut" ] && rm -f "$cut"

# Filet : le masquage peut rallonger (remplacements plus longs) ; on ne garde jamais plus de MAX.
size=$(wc -c < "$tmp")
if [ "$size" -gt "$MAX" ]; then
  cut2=$(mktemp) || { rm -f "$tmp"; exit 3; }
  truncate_file "$tmp" "$cut2" "$size" || { rm -f "$tmp" "$cut2"; exit 4; }
  mv -f "$cut2" "$tmp"
fi

mkdir -p "$(dirname "$out")"
mv -f "$tmp" "$out"
chmod 0644 "$out"
