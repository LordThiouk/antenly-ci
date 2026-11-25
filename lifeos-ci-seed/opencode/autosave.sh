#!/usr/bin/env bash
# Sauvegarde automatique du travail d'un FullRun, appelée par wippush.sh avant chaque push : un
# runner qui tombe (annulation, panne, quota) ne perd plus le report ISA, le point de reprise ni
# l'arbre de code non commité.
#
#   autosave.sh once        un passage (commits locaux `wip(carry)` puis `wip(autosave)`)
#
# Deux groupes, deux commits :
#  1. carry/checkpoint : MEMORY/WORK/<slug>/fullrun-carry.json et .fullrun/<job>_checkpoint.json
#     (de simples indices de reprise, JSON valide, taille bornée). Message `wip(carry)`.
#  2. arbre de code : tout le reste modifié ou nouveau, SAUF la liste d'exclusion
#     (opencode/autosave-deny.txt : .env, clés et keystores, google-services, comptes de service,
#     secrets PSP, builds et dépendances…), les liens symboliques, les binaires et les fichiers trop gros.
#     Message `wip(autosave)`.
# Règles fixes :
#  - jamais `git add -A` ni `git add .` : seuls des chemins nommés un à un, déjà filtrés, sont ajoutés ;
#  - gitleaks (config et ignores du run) scanne le contenu INDEXÉ avant le commit ; un fichier qui fuit
#    est retiré de l'index et reste non commité, le reste est sauvé ; un contrôle impossible = rien commité ;
#  - le commit ne prend que ces chemins (`git commit -- chemins`) : l'index de l'agent n'est pas touché ;
#  - aucun passage si l'agent tient l'index (index.lock), si une fusion/un rebase est en cours, ou si la
#    branche courante n'est pas la branche de travail ;
#  - exécuté comme propriétaire du dépôt (setpriv) quand le démon est root : aucun fichier root dans .git ;
#  - les messages ne contiennent aucun mot de la porte de clôture (verdict, isa, phase, complete…) et le
#    commit part hors d'opencode : aucune porte ni hook n'est contourné ou modifié.
# Sortie : une ligne de suivi par fait (jamais un secret, un contenu, ni un chemin hors liste assainie).
set +x
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${AS_REPO:?}" "${AS_BRANCH:?}" "${AS_TMP:?}"
GL="${AS_GITLEAKS:-gitleaks}"
CTL="${AS_CTL_TIMEOUT:-120}"
MAXB="${AS_MAX_BYTES:-5242880}"
DENY="${AS_DENY_FILE:-$HERE/autosave-deny.txt}"
[[ "$CTL" =~ ^[0-9]{1,4}$ ]] || CTL=120
[[ "$MAXB" =~ ^[0-9]{1,9}$ ]] || MAXB=5242880

[ -d "$AS_REPO/.git" ] || exit 0
[ -f "$DENY" ] || { echo "autosave : liste d'exclusion introuvable, rien commité"; exit 0; }
OWNER_UID=$(stat -c %u "$AS_REPO/.git" 2>/dev/null || echo 0)
OWNER_GID=$(stat -c %g "$AS_REPO/.git" 2>/dev/null || echo 0)

as_git() {
  local base=(env -i PATH="$PATH" HOME=/nonexistent GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
              GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false
              git -C "$AS_REPO" -c core.hooksPath=/dev/null -c core.fsmonitor=false -c commit.gpgsign=false
                  -c core.quotepath=false)
  if [ "$(id -u)" = 0 ] && [ "$OWNER_UID" != 0 ]; then
    setpriv --reuid="$OWNER_UID" --regid="$OWNER_GID" --clear-groups "${base[@]}" "$@"
  else
    "${base[@]}" "$@"
  fi
}

# --- Conditions de passage --------------------------------------------------------------------
G="$AS_REPO/.git"
[ -e "$G/index.lock" ] && { echo "autosave : index occupé par l'agent, on réessaie au prochain passage"; exit 0; }
for m in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply BISECT_LOG; do
  [ -e "$G/$m" ] && { echo "autosave : opération git en cours ($m), rien commité"; exit 0; }
done
cur=$(as_git symbolic-ref -q --short HEAD 2>/dev/null || true)
[ "$cur" = "$AS_BRANCH" ] || { echo "autosave : branche courante différente de la branche de travail, rien commité"; exit 0; }
case "${cur,,}" in main|master) exit 0 ;; esac

W=$(mktemp -d "$AS_TMP/autosave.XXXXXX") || exit 0
chmod 0700 "$W"
trap 'rm -rf "$W"' EXIT

# Avant de commiter le carry : réintroduire les enregistrements signés déjà
# présents sur la branche (export après retreat, persist amputé).
# Copie figée $T en CI ; à côté du script en test local.
for _msc in "${T:-/opt/fullrun-tools}/merge-signed-carry.sh" "$HERE/merge-signed-carry.sh"; do
  if [ -x "$_msc" ]; then
    "$_msc" "$AS_REPO" || true
    break
  fi
done

as_git status --porcelain=v1 -z -uall > "$W/status.z" 2>/dev/null || { echo "autosave : git status impossible, rien commité"; exit 0; }
[ -s "$W/status.z" ] || exit 0

# --- Politique : une seule source, en python (NUL-sûr) ----------------------------------------
AS_REPO="$AS_REPO" AS_DENY="$DENY" AS_MAXB="$MAXB" AS_W="$W" python3 - <<'PY'
import fnmatch, json, os, re, stat

repo, deny_file, maxb, W = os.environ["AS_REPO"], os.environ["AS_DENY"], int(os.environ["AS_MAXB"]), os.environ["AS_W"]
globs = []
for line in open(deny_file, encoding="utf-8"):
    s = line.strip()
    if s and not s.startswith("#"):
        globs.append(s.lower())

CARRY = re.compile(r"^(?:.+/)?MEMORY/WORK/[^/]+/fullrun-carry\.json$")
CHECK = re.compile(r"^\.fullrun/[A-Za-z0-9][A-Za-z0-9._-]{0,63}_checkpoint\.json$")


def denied(path):
    p = path.lower()
    parts = p.split("/")
    for g in globs:
        if "/" in g:
            gg = g.rstrip("/")
            if fnmatch.fnmatch(p, gg) or p == gg or p.startswith(gg + "/"):
                return g
        else:
            if any(fnmatch.fnmatch(part, g) for part in parts):
                return g
    return None


def clean(p):
    return re.sub(r"[^A-Za-z0-9._/ -]", "?", p)[:80]


raw = open(os.path.join(W, "status.z"), "rb").read().split(b"\0")
paths, i = [], 0
while i < len(raw):
    e = raw[i]
    i += 1
    if len(e) < 4:
        continue
    xy, p = e[:2].decode("latin-1"), e[3:].decode("utf-8", "surrogateescape")
    if "R" in xy or "C" in xy:
        i += 1  # ancien nom : on ne commite que le nouveau
    paths.append((xy, p))

carry, code, skip = [], [], []
for xy, p in paths:
    if "\n" in p or "\r" in p or p.startswith("/") or ".." in p.split("/"):
        skip.append(("chemin inhabituel", p)); continue
    full = os.path.join(repo, p)
    deleted = "D" in xy and not os.path.lexists(full)
    if not deleted:
        try:
            st = os.lstat(full)
        except OSError:
            skip.append(("illisible", p)); continue
        if stat.S_ISLNK(st.st_mode):
            skip.append(("lien symbolique", p)); continue
        if not stat.S_ISREG(st.st_mode):
            skip.append(("pas un fichier", p)); continue
    if CARRY.match(p) or CHECK.match(p):
        if deleted:
            continue
        try:
            if st.st_size > 65536:
                skip.append(("point de reprise trop gros", p)); continue
            json.load(open(full, encoding="utf-8"))
        except Exception:
            skip.append(("point de reprise illisible", p)); continue
        carry.append(p); continue
    d = denied(p)
    if d:
        skip.append(("liste d'exclusion", p)); continue
    if not deleted:
        if st.st_size > maxb:
            skip.append(("trop gros", p)); continue
        try:
            with open(full, "rb") as h:
                if b"\0" in h.read(8192):
                    skip.append(("binaire", p)); continue
        except OSError:
            skip.append(("illisible", p)); continue
    code.append(p)

for name, lst in (("carry", carry), ("code", code)):
    with open(os.path.join(W, name + ".lst"), "wb") as h:
        for p in lst:
            h.write(p.encode("utf-8", "surrogateescape") + b"\0")
with open(os.path.join(W, "skip.txt"), "w", encoding="utf-8") as h:
    for why, p in skip:
        h.write(f"{why} : {clean(p)}\n")
PY
[ -s "$W/skip.txt" ] && while IFS= read -r l; do echo "autosave : non commité — $l"; done < <(head -n 10 "$W/skip.txt")

# --- Contrôle gitleaks du contenu indexé -------------------------------------------------------
scan_staged() { # $1 = liste de chemins (NUL) ; rc 0 propre, 1 fuite (fichiers dans $W/leak.lst), 2 contrôle impossible
  local x="$W/x" p rc=0
  rm -rf "$x" "$W/rep.json" "$W/leak.lst"; mkdir -p "$x"; : > "$W/leak.lst"
  while IFS= read -r -d '' p; do
    mkdir -p "$x/$(dirname -- "$p")" 2>/dev/null || return 2
    as_git show ":$p" > "$x/$p" 2>/dev/null || rm -f "$x/$p"   # suppression indexée : pas de contenu
  done < "$1"
  cfg=(); [ -n "${AS_GL_CONFIG:-}" ] && [ -s "${AS_GL_CONFIG:-}" ] && cfg=(--config "$AS_GL_CONFIG")
  ign=(); [ -n "${AS_GL_IGNORE:-}" ] && [ -d "${AS_GL_IGNORE:-}" ] && ign=(--gitleaks-ignore-path "$AS_GL_IGNORE")
  timeout -k 5 "$CTL" "$GL" dir "${cfg[@]}" "${ign[@]}" --redact --no-banner --report-path "$W/rep.json" "$x" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) python3 - "$W/rep.json" "$x" > "$W/leak.lst" <<'PY'
import json, os, sys
rep, root = sys.argv[1], os.path.realpath(sys.argv[2])
try:
    d = json.load(open(rep))
except Exception:
    d = []
seen = set()
for f in (d if isinstance(d, list) else []):
    p = os.path.relpath(os.path.realpath(f.get("File", "")), root)
    if not p.startswith("..") and p not in seen:
        seen.add(p); sys.stdout.buffer.write(p.encode("utf-8", "surrogateescape") + b"\0")
PY
       return 1 ;;
    *) return 2 ;;
  esac
}

# Chemins « littéraux » : sans :(literal), un fichier nommé « :(top)* » serait lu par git comme un motif
# magique et ajouterait tout l'arbre. Tout chemin passé à add / reset / commit est donc préfixé.
LP=()
lit() { local p; LP=(); for p in "$@"; do LP+=(":(literal)$p"); done; }

save_group() { # $1 = carry|code ; $2 = message
  local name="$1" msg="$2" lst="$W/$1.lst" p rc keep="$W/keep.lst" skipit q
  local -a paths=() leaks=()
  [ -s "$lst" ] || return 0
  mapfile -d '' -t paths < "$lst"
  lit "${paths[@]}"
  as_git add -- "${LP[@]}" >/dev/null 2>&1 || { echo "autosave : git add refusé ($name), rien commité"; return 0; }
  scan_staged "$lst"; rc=$?
  if [ "$rc" -eq 1 ]; then
    # Les fichiers qui fuient sortent de l'index (ils restent dans l'arbre, non suivis par ce commit).
    mapfile -d '' -t leaks < "$W/leak.lst"
    lit "${leaks[@]}"; as_git reset -q -- "${LP[@]}" >/dev/null 2>&1 || true
    for p in "${leaks[@]}"; do echo "autosave : secret probable dans $(printf '%s' "$(basename -- "$p")" | tr -cd 'A-Za-z0-9._ -' | cut -c1-80), non commité"; done
    : > "$keep"
    for p in "${paths[@]}"; do
      skipit=0; for q in "${leaks[@]}"; do [ "$p" = "$q" ] && skipit=1; done
      [ "$skipit" -eq 0 ] && printf '%s\0' "$p" >> "$keep"
    done
    mapfile -d '' -t paths < "$keep"
    [ "${#paths[@]}" -gt 0 ] || return 0
    scan_staged "$keep"; rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    lit "${paths[@]}"; as_git reset -q -- "${LP[@]}" >/dev/null 2>&1 || true
    echo "autosave : contrôle gitleaks impossible ou fuite persistante ($name), rien commité"
    return 0
  fi
  lit "${paths[@]}"
  if as_git -c user.name=Nix -c user.email=nix@galass.local commit -q --no-verify -m "$msg" -- "${LP[@]}" >/dev/null 2>&1; then
    echo "autosave : $msg ($(as_git rev-parse --short HEAD 2>/dev/null)), ${#paths[@]} fichier(s)"
  else
    as_git reset -q -- "${LP[@]}" >/dev/null 2>&1 || true
    echo "autosave : commit refusé ($name), index remis, on réessaie"
  fi
}

save_group carry "wip(carry): reprise du run"
save_group code "wip(autosave): arbre de travail"
exit 0
