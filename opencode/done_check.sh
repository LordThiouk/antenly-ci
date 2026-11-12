#!/usr/bin/env bash
# Validation d'un run FullRun sur PASS de Max (PLAN A, étape 4). Script autonome : bash + jq +
# python3. Sort 0 seulement si TOUT est vrai :
#   a. stockage opencode : un `task` subagent_type=Max completed, sa session enfant a un message
#      assistant d'un modèle `-free` avec tokens.output > 0, sa sortie contient PASS/APPROVE/LGTM
#      sans REQUEST CHANGES/FAIL/BLOCK, et sa fin est postérieure au dernier commit de code ;
#   b. hooks.log contient `SUBAGENT done subagent_type=Max ok=true` postérieur au dernier commit
#      (un `on-agent-stop` lancé à la main en bash ne compte pas : il n'écrit pas cette ligne) ;
#   c. OC_DONE_VERIFY (fichier ou liste `;`) : toutes les commandes rendent 0 ;
#   d. arbre propre (hors .fullrun/logs), REPORT.md présent, ISA pas en `phase: complete`.
# Sortie : une seule ligne `done_check=ok` ou `done_check=ko raison=<a|b|c|d>:<détail>`. Jamais de
# texte du modèle, jamais de secret.
set +x
set -uo pipefail
STORE="${OC_STORE_DIR:-$HOME/.local/share/opencode}"
HOOKS="${OC_HOOKS_LOG:-$HOME/.local/state/opencode-lifeos/hooks.log}"
REPORT="${OC_REPORT:-}"
ISA="${OC_ISA:-${OC_ISA_PATH:-}}"
REPO="${OC_DONE_REPO:-$(pwd)}"
MAX_AGENT="${OC_MAX_SUBAGENT:-Max}"
DONE_VERIFY="${OC_DONE_VERIFY:-}"

ko() { printf 'done_check=ko raison=%s\n' "$1"; exit 1; }
ok() { printf 'done_check=ok\n'; exit 0; }

command -v python3 >/dev/null 2>&1 || ko a:python3
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || ko d:depot

# Dernier commit de code : hors MEMORY et hors artefacts FullRun (même règle que le diagnostic).
last_commit=$(git -C "$REPO" log -1 --format=%ct -- . ':!MEMORY' ':!.fullrun' 2>/dev/null) || last_commit=0
[[ "$last_commit" =~ ^[0-9]+$ ]] || last_commit=0

# --- a. stockage opencode (SQLite 1.19+ ou arbre JSON) ---
storage=$(python3 - "$STORE" "$MAX_AGENT" "$last_commit" <<'PY'
import glob, json, os, re, sqlite3, sys

store, max_agent, last_commit = sys.argv[1], sys.argv[2], int(sys.argv[3])
PASS = re.compile(r'\{"status"\s*:\s*"pass"\}|\bPASS\b|\bAPPROVE\b|\bLGTM\b')
FAIL = re.compile(r'REQUEST CHANGES|\bFAIL\b|\bBLOCK\b')


def parse(d):
    try:
        return json.loads(d)
    except Exception:
        return None


def parts():
    out = []
    for db in glob.glob(os.path.join(store, '*.db')):
        try:
            con = sqlite3.connect('file:%s?mode=ro' % db, uri=True)
            rows = con.execute('select session_id, data from part').fetchall()
        except Exception:
            continue
        for _sid, data in rows:
            o = parse(data)
            if o and o.get('tool') == 'task':
                out.append(('db', db, o))
    for base in (os.path.join(store, 'storage', 'part'), os.path.join(store, 'part')):
        for f in glob.glob(os.path.join(base, '*', '*.json')):
            o = parse(open(f, encoding='utf-8', errors='replace').read())
            if o and o.get('tool') == 'task':
                out.append(('fs', store, o))
    return out


def child_messages(kind, src, child):
    msgs = []
    if kind == 'db':
        try:
            con = sqlite3.connect('file:%s?mode=ro' % src, uri=True)
            for (data,) in con.execute('select data from message where session_id=?', (child,)):
                o = parse(data)
                if o:
                    msgs.append(o)
        except Exception:
            pass
    else:
        for base in (os.path.join(src, 'storage', 'message', child), os.path.join(src, 'message', child)):
            for f in glob.glob(os.path.join(base, '*.json')):
                o = parse(open(f, encoding='utf-8', errors='replace').read())
                if o:
                    msgs.append(o)
    return msgs


cands = []
for kind, src, o in parts():
    st = o.get('state') or {}
    inp = st.get('input') or {}
    if inp.get('subagent_type') != max_agent or st.get('status') != 'completed':
        continue
    cands.append((kind, src, o, st, inp))

if not cands:
    print('KO:none')
    sys.exit(0)

reasons = set()
for kind, src, o, st, inp in cands:
    meta = st.get('metadata') or {}
    child = meta.get('sessionId') or ''
    end = (st.get('time') or {}).get('end') or 0
    try:
        end = int(end)
    except Exception:
        end = 0
    if end <= last_commit * 1000:
        reasons.add('time')
        continue
    msgs = child_messages(kind, src, child) if child else []
    if not any((m.get('role') == 'assistant')
               and str(m.get('modelID') or '').endswith('-free')
               and int((m.get('tokens') or {}).get('output') or 0) > 0
               for m in msgs):
        reasons.add('tokens')
        continue
    out = str(st.get('output') or '')
    if not PASS.search(out):
        reasons.add('verdict')
        continue
    if FAIL.search(out):
        reasons.add('verdict')
        continue
    print('OK')
    sys.exit(0)

for r in ('tokens', 'verdict', 'time'):
    if r in reasons:
        print('KO:%s' % r)
        sys.exit(0)
print('KO:model')
PY
) || ko a:stockage
[ "$storage" = OK ] || ko "a:${storage#KO:}"

# --- b. hooks.log : ligne du plugin, postérieure au dernier commit de code ---
hooks_ok=0
if [ -f "$HOOKS" ]; then
  while IFS= read -r line; do
    case "$line" in *"SUBAGENT done subagent_type=$MAX_AGENT ok=true"*) ;; *) continue ;; esac
    ts=${line%% *}
    epoch=$(date -u -d "$ts" +%s 2>/dev/null) || continue
    if [ "$epoch" -gt "$last_commit" ]; then hooks_ok=1; break; fi
  done <"$HOOKS"
fi
[ "$hooks_ok" -eq 1 ] || ko b:hooks

# --- c. vérificateurs relancés (fichier ou liste séparée par des `;`) ---
if [ -n "$DONE_VERIFY" ]; then
  cmds=()
  if [ -f "$DONE_VERIFY" ]; then
    while IFS= read -r c; do cmds+=("$c"); done <"$DONE_VERIFY"
  else
    IFS=';' read -r -a cmds <<<"$DONE_VERIFY"
  fi
  i=0
  for c in "${cmds[@]}"; do
    c="${c#"${c%%[![:space:]]*}"}"; c="${c%"${c##*[![:space:]]}"}"
    [ -n "$c" ] || continue
    case "$c" in \#*) continue ;; esac
    i=$((i + 1))
    if ! ( cd "$REPO" && bash -c "$c" ) >/dev/null 2>&1; then ko "c:verify$i"; fi
  done
fi

# --- d. arbre propre, rapport, ISA non close ---
dirty=$(cd "$REPO" && git status --porcelain 2>/dev/null | grep -vE '^.. \.fullrun/logs/' || true)
[ -z "$dirty" ] || ko d:arbre-sale
[ -n "$REPORT" ] && [ -s "$REPORT" ] || ko d:rapport-absent
if [ -n "$ISA" ]; then
  isa="$ISA"
  case "$isa" in /*) ;; *) isa="$REPO/$isa" ;; esac
  [ -f "$isa" ] || ko d:isa-absente
  if grep -qE '^phase:[[:space:]]*complete[[:space:]]*$' "$isa"; then ko d:isa-complete; fi
fi

ok
