#!/usr/bin/env bash
# Empêche un persist/export (y compris après `FullRunPipeline.ts step --direction retreat`)
# d'écraser fullrun-carry.json en perdant un enregistrement signé déjà présent sur la branche.
# Fusion : on réintroduit les steps pass/skipped munis d'une empreinte qui existent dans
# l'historique du fichier ; on n'écrase pas un fichier plus complet par un sous-ensemble.
#
#   merge-signed-carry.sh <dépôt>
#   merge-signed-carry.sh install-hook <dépôt>   # copie figée dans .git/hooks + pre-commit
#
# Codes : 0 ok (rien à faire ou fusion écrite), 2 usage.
# Ne jamais afficher de secret, de signature ni de contenu d'enregistrement.
set +x
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() { echo "usage: merge-signed-carry.sh <dépôt> | install-hook <dépôt>" >&2; exit 2; }

install_hook() {
  local repo="${1:-}" hook
  [ -n "$repo" ] && [ -d "$repo/.git" ] || usage
  hook="$repo/.git/hooks"
  mkdir -p "$hook"
  cp -f "$HERE/merge-signed-carry.sh" "$hook/merge-signed-carry.sh"
  chmod 0755 "$hook/merge-signed-carry.sh"
  # pre-commit : rattrape un `git commit` de l'agent (hors --no-verify / hooksPath=/dev/null).
  cat > "$hook/pre-commit" <<'HOOK'
#!/bin/sh
set +x
script="$(dirname "$0")/merge-signed-carry.sh"
[ -x "$script" ] || exit 0
repo=$(git rev-parse --show-toplevel) || exit 0
"$script" "$repo" || exit 1
# Si le script a réécrit un carry, l'inclure dans CE commit.
# Chemins seulement, jamais le contenu.
for f in $(git diff --name-only -- 'MEMORY/WORK/*/fullrun-carry.json' 2>/dev/null); do
  git add -- "$f" 2>/dev/null || true
done
exit 0
HOOK
  chmod 0755 "$hook/pre-commit"
  echo "merge-signed-carry : hook installé"
  exit 0
}

if [ "${1:-}" = "install-hook" ]; then
  install_hook "${2:-}"
fi

REPO="${1:-}"
[ -n "$REPO" ] && [ -d "$REPO/.git" ] || usage
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || usage

# Clé d'empreinte : chemins/env déjà utilisés par le job, jamais affichée.
key_file=""
for c in "${OC_ISA_KEY_FILE:-}" "${EXTRA_ISA_KEY_FILE:-}" "${LIVE_ISA_KEY_FILE:-}" "${WIP_ISA_KEY_FILE:-}"; do
  if [ -n "$c" ] && [ -f "$c" ] && [ -s "$c" ]; then key_file="$c"; break; fi
done
if [ -z "$key_file" ]; then
  def="${HOME:-}/.claude/LIFEOS/MEMORY/STATE/.isa-stamp-key"
  if [ -f "$def" ] && [ -s "$def" ]; then key_file="$def"; fi
fi
# Fichier temporaire si seule la variable d'environnement est posée (step de contrôle).
key_tmp=""
cleanup() { [ -n "$key_tmp" ] && rm -f "$key_tmp"; }
trap cleanup EXIT
if [ -z "$key_file" ] && [ -n "${ISA_STAMP_KEY:-}" ]; then
  key_tmp=$(mktemp)
  chmod 600 "$key_tmp"
  # shellcheck disable=SC2059
  printf '%s' "$ISA_STAMP_KEY" > "$key_tmp"
  key_file="$key_tmp"
fi

export MERGE_CARRY_REPO="$REPO"
export MERGE_CARRY_KEY="${key_file:-}"

python3 - <<'PY'
import json, os, subprocess, sys
from pathlib import Path

repo = os.environ["MERGE_CARRY_REPO"]
key_path = os.environ.get("MERGE_CARRY_KEY") or ""

def git(*args, raw=False):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True)
    if raw:
        return r.returncode, r.stdout
    out = r.stdout.decode("utf-8", "replace")
    return r.returncode, out

def show(rev, path):
    rc, data = git("show", f"{rev}:{path}", raw=True)
    return data if rc == 0 else None

def parse(raw):
    if not raw:
        return None
    try:
        text = raw.decode("utf-8") if isinstance(raw, (bytes, bytearray)) else raw
        d = json.loads(text)
    except Exception:
        return None
    if not isinstance(d, dict):
        return None
    payload = d.get("payload")
    if not isinstance(payload, dict) or not isinstance(payload.get("steps"), dict):
        return None
    return d

def valid_step(rec):
    if not isinstance(rec, dict):
        return False
    if rec.get("status") not in ("pass", "skipped"):
        return False
    fp = rec.get("fp")
    return isinstance(fp, str) and len(fp) >= 16

def list_paths():
    paths = set()
    rc, out = git("ls-files", "-z", "--", "MEMORY/WORK/*/fullrun-carry.json")
    if rc == 0 and out:
        paths.update([p for p in out.split("\0") if p])
    # Historique récent (fichier déjà commité puis éventuellement retiré de l'index).
    rc, out = git("log", "-50", "--name-only", "--pretty=format:", "--", "MEMORY/WORK/*/fullrun-carry.json")
    if rc == 0:
        for line in out.splitlines():
            line = line.strip()
            if line.endswith("fullrun-carry.json"):
                paths.add(line)
    # Arbre de travail (export non encore suivi).
    root = Path(repo)
    mem = root / "MEMORY" / "WORK"
    if mem.is_dir():
        for p in mem.glob("*/fullrun-carry.json"):
            try:
                rel = p.relative_to(root).as_posix()
            except ValueError:
                continue
            paths.add(rel)
    return sorted(paths)

def history_revs(path):
    rc, out = git("log", "-50", "--format=%H", "--", path)
    if rc != 0 or not out.strip():
        return []
    return [l.strip() for l in out.splitlines() if l.strip()]

def collect_versions(path):
    """Plus récent d'abord : arbre de travail puis commits qui touchent le fichier."""
    versions = []  # list of (raw_bytes, parsed, source)
    wt = Path(repo, path)
    if wt.is_file() and not wt.is_symlink():
        raw = wt.read_bytes()
        versions.append((raw, parse(raw), "worktree"))
    for rev in history_revs(path):
        raw = show(rev, path)
        parsed = parse(raw) if raw else None
        if raw and parsed:
            versions.append((raw, parsed, rev[:12]))
    return versions

def step_ids(parsed):
    if not parsed:
        return set()
    return {k for k, v in parsed["payload"]["steps"].items() if valid_step(v)}

def rec_at(rec):
    """Horodatage ISO d'un enregistrement ("" si absent) : compare deux versions du même id."""
    a = rec.get("at")
    return a if isinstance(a, str) else ""

def newest_at(parsed):
    """Horodatage le plus récent du fichier : dit quelle version est le dernier état connu."""
    vals = [rec_at(rec) for rec in parsed["payload"]["steps"].values() if valid_step(rec)]
    return max(vals) if vals else ""

changed = 0
for path in list_paths():
    if ".." in path or path.startswith("/"):
        continue
    versions = collect_versions(path)
    if not versions:
        continue
    current_raw, current, current_src = versions[0]
    if current is None:
        # Arbre illisible : reprendre la dernière version historique bien formée.
        older = next(((r, p, s) for r, p, s in versions[1:] if p is not None), None)
        if older:
            Path(repo, path).parent.mkdir(parents=True, exist_ok=True)
            Path(repo, path).write_bytes(older[0])
            print(f"merge-signed-carry : {path} restauré (fichier illisible, version de la branche)")
            changed += 1
        continue
    current_ids = step_ids(current)
    current_newest = newest_at(current)
    # Version historique à reprendre : soit elle possède un step valide absent du courant,
    # soit c'est un état PLUS RÉCENT du carry (même ids, empreintes/horodatages plus récents).
    # Sans ce second cas, un carry complet mais périmé (ex. restauré depuis un vieux commit)
    # masque un carry plus récent amputé : les ids sont présents, donc aucune fusion n'était
    # déclenchée et la porte lisait des empreintes d'ISA périmées.
    donor = None
    missing = set()
    for raw, parsed, src in versions[1:]:
        ids = step_ids(parsed)
        lost = {i for i in ids if i not in current_ids}
        newer_state = newest_at(parsed) > current_newest
        if lost or newer_state:
            donor = (raw, parsed, src)
            missing = lost | {i for i in ids if i in current_ids}
            break
    if not donor:
        continue
    donor_raw, donor_parsed, donor_src = donor
    # Sous-ensemble strict : le courant n'a aucun step que le donneur n'ait pas
    # → on rétablit le fichier signé déjà présent (cas typique après retreat).
    extra = {i for i in current_ids if i not in step_ids(donor_parsed)}
    if not extra:
        if current_raw == donor_raw:
            continue
        Path(repo, path).parent.mkdir(parents=True, exist_ok=True)
        Path(repo, path).write_bytes(donor_raw)
        print(f"merge-signed-carry : {path} restauré ({len(missing)} enregistrement(s) signé(s) repris de la branche)")
        changed += 1
        continue
    # Le courant a aussi des steps nouveaux : fusion + ré-signature si la clé est là.
    # Sans clé, on refuse d'écrire un fichier à signature cassée : on conserve
    # les enregistrements déjà signés (donneur) plutôt que les perdre.
    if not key_path or not Path(key_path).is_file():
        Path(repo, path).parent.mkdir(parents=True, exist_ok=True)
        Path(repo, path).write_bytes(donor_raw)
        print(f"merge-signed-carry : {path} restauré (clé absente, enregistrements signés de la branche conservés)")
        changed += 1
        continue
    try:
        import hmac, hashlib
        key = Path(key_path).read_bytes()
        # Ré-signer comme FullRunCarry.exportCarry : HMAC-SHA256(clé, JSON compact du payload).
        payload = {
            "v": donor_parsed["payload"].get("v", 1),
            "isa": current["payload"].get("isa") or donor_parsed["payload"].get("isa"),
            "head": current["payload"].get("head") or donor_parsed["payload"].get("head") or "",
            "steps": {},
        }
        # Pour chaque id, garder l'enregistrement le plus récent (horodatage). Un id présent
        # des deux côtés ne doit jamais revenir à une version plus ancienne : c'était le cas
        # quand le courant (fichier périmé restauré) écrasait le donneur (état plus récent).
        for src_parsed in (donor_parsed, current):
            for sid, rec in src_parsed["payload"]["steps"].items():
                if not valid_step(rec):
                    continue
                sid = str(sid)
                if sid not in payload["steps"] or rec_at(rec) >= rec_at(payload["steps"][sid]):
                    payload["steps"][sid] = rec
        compact = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        sig = hmac.new(key, compact.encode("utf-8"), hashlib.sha256).hexdigest()
        text = json.dumps({"payload": payload, "sig": sig}, ensure_ascii=False, indent=2) + "\n"
        Path(repo, path).parent.mkdir(parents=True, exist_ok=True)
        Path(repo, path).write_text(text, encoding="utf-8")
        print(f"merge-signed-carry : {path} fusionné ({len(missing)} enregistrement(s) signé(s) repris de la branche)")
        changed += 1
    except Exception:
        Path(repo, path).parent.mkdir(parents=True, exist_ok=True)
        Path(repo, path).write_bytes(donor_raw)
        print(f"merge-signed-carry : {path} restauré (fusion impossible, version signée de la branche)")
        changed += 1

sys.exit(0)
PY
