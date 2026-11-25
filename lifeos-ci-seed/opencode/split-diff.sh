#!/usr/bin/env bash
# Découpe un gros diff en morceaux avant revue (agent code-reviewer/Forge/Silas), pour éviter les
# dépassements de contexte d'un modèle -free sur un diff volumineux. Ne coupe JAMAIS un fichier en
# deux moitiés dans des morceaux différents : la frontière de coupe est toujours entre deux en-têtes
# `diff --git a/... b/...`, jamais au milieu d'un hunk — un fichier seul plus gros que le seuil reste
# un morceau à lui seul (jamais tronqué : une revue partielle d'un fichier est pire qu'un seul
# morceau trop long, le modèle décide alors lui-même s'il doit se limiter).
#
# Usage :
#   split-diff.sh --out-dir DIR [--max-lines N] [--source FICHIER]
#   (lit le diff sur stdin si --source est omis ou vaut -)
#
# Sortie : DIR/chunk-0001.diff, DIR/chunk-0002.diff, ... (toujours au moins un, même un diff vide
# produit chunk-0001.diff vide) et DIR/manifest.txt (une ligne par morceau : nom, nombre de lignes,
# liste des fichiers qu'il contient — pour que l'agent sache quoi envoyer et dans quel ordre).
# Code de sortie : 0 ok, 64 entrée invalide, 70 crash (découpe non garantie avoir eu lieu).
set -uo pipefail

fail() { echo "[split-diff] code=64 $1" >&2; exit 64; }

OUT_DIR=""
MAX_LINES=800
SRC="-"
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --max-lines) MAX_LINES="${2:-}"; shift 2 ;;
    --source) SRC="${2:-}"; shift 2 ;;
    *) fail "argument inattendu : $1" ;;
  esac
done
[ -n "$OUT_DIR" ] || fail "--out-dir requis"
[[ "$MAX_LINES" =~ ^[0-9]{1,6}$ ]] && [ "$MAX_LINES" -ge 10 ] || fail "--max-lines invalide (entier >= 10)"

mkdir -p "$OUT_DIR" || { echo "[split-diff] code=70 impossible de créer $OUT_DIR" >&2; exit 70; }
rm -f "$OUT_DIR"/chunk-*.diff "$OUT_DIR/manifest.txt" 2>/dev/null || true

if [ "$SRC" = "-" ]; then
  input="$OUT_DIR/.input.diff"
  cat > "$input" || { echo "[split-diff] code=70 lecture stdin interrompue" >&2; exit 70; }
else
  [ -f "$SRC" ] || fail "--source introuvable : $SRC"
  input="$SRC"
fi

python3 - "$input" "$OUT_DIR" "$MAX_LINES" <<'PY'
import sys, os

src, out_dir, max_lines = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(src, "r", errors="replace") as f:
    lines = f.readlines()

# Un diff --git a/... b/... ouvre toujours un nouveau fichier : c'est la SEULE frontière de coupe
# admise. On regroupe les lignes en blocs par fichier, puis on remplit les morceaux sans jamais
# couper un bloc-fichier.
files = []  # liste de (nom_affiché, [lignes])
cur_name, cur_lines = None, []
for ln in lines:
    if ln.startswith("diff --git "):
        if cur_lines:
            files.append((cur_name, cur_lines))
        # "diff --git a/path b/path" -> on affiche le chemin b/ (la version après).
        parts = ln.rstrip("\n").split(" ")
        cur_name = parts[-1][2:] if len(parts) >= 1 and parts[-1].startswith("b/") else ln.strip()
        cur_lines = [ln]
    else:
        if cur_lines or files or cur_name is not None:
            cur_lines.append(ln)
        else:
            # Lignes avant le premier "diff --git " (en-tête de patch éventuel) : rattachées au
            # premier fichier, jamais perdues.
            cur_name = "(préambule)"
            cur_lines = [ln]
if cur_lines:
    files.append((cur_name, cur_lines))

chunks = []  # liste de listes de (nom, lignes)
cur_chunk, cur_chunk_count = [], 0
for name, flines in files:
    n = len(flines)
    if cur_chunk and cur_chunk_count + n > max_lines:
        chunks.append(cur_chunk)
        cur_chunk, cur_chunk_count = [], 0
    cur_chunk.append((name, flines))
    cur_chunk_count += n
if cur_chunk:
    chunks.append(cur_chunk)
if not chunks:
    chunks = [[]]  # diff vide -> un seul morceau vide, jamais zéro morceau

manifest = []
for i, chunk in enumerate(chunks, start=1):
    chunk_path = os.path.join(out_dir, "chunk-%04d.diff" % i)
    total = 0
    names = []
    with open(chunk_path, "w") as out:
        for name, flines in chunk:
            out.writelines(flines)
            total += len(flines)
            names.append(name)
    manifest.append("chunk-%04d.diff\t%d lignes\t%s" % (i, total, ", ".join(names) if names else "(vide)"))

with open(os.path.join(out_dir, "manifest.txt"), "w") as m:
    m.write("\n".join(manifest) + ("\n" if manifest else ""))

print("[split-diff] %d morceau(x) écrit(s) dans %s" % (len(chunks), out_dir), file=sys.stderr)
PY
rc=$?
[ "$SRC" = "-" ] && rm -f "$input" 2>/dev/null
[ "$rc" -eq 0 ] || { echo "[split-diff] code=70 découpe interrompue (python3)" >&2; exit 70; }
exit 0
