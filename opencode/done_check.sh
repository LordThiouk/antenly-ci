#!/usr/bin/env bash
# Validation d'un run FullRun sur PASS de Max (PLAN A, étape 4). Script autonome : bash + jq +
# python3. OC_DONE_AGENTS (liste séparée par des virgules, défaut = OC_MAX_SUBAGENT = Max) :
# CHAQUE agent listé (ex. « Max,Silas ») doit satisfaire a et b ; un PASS qui ne vient pas d'une
# vraie réponse de l'agent dans le stockage opencode (texte écrit par l'agent principal, fichier,
# rapport) ne compte jamais. OC_DONE_ONLY=verdict s'arrête après a et b (utilisé par
# checkpoint.sh pour n'enregistrer que des verdicts réels). Sort 0 seulement si TOUT est vrai :
#   a. stockage opencode : un `task` subagent_type=Max completed, sa session enfant a un message
#      assistant d'un modèle `-free` avec tokens.output > 0, sa sortie CONCLUT PASS dans un verdict structuré
#      (JSON final {"verdict":…} ou dernière ligne « VERDICT: PASS »; jamais lu dans le corps, aucun verdict
#      structuré = inconclusif, raison a:inconclusif), et sa fin est postérieure au dernier commit de code ;
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
AGENTS="${OC_DONE_AGENTS:-$MAX_AGENT}"
ONLY="${OC_DONE_ONLY:-}"
DONE_VERIFY="${OC_DONE_VERIFY:-}"

ko() { printf 'done_check=ko raison=%s\n' "$1"; exit 1; }
[[ "$AGENTS" =~ ^[A-Za-z][A-Za-z0-9_-]{0,39}(,[A-Za-z][A-Za-z0-9_-]{0,39}){0,5}$ ]] || { printf 'done_check=ko raison=a:agents\n'; exit 1; }
ok() { printf 'done_check=ok\n'; exit 0; }

command -v python3 >/dev/null 2>&1 || ko a:python3
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || ko d:depot
# Un magasin absent n'est pas « aucune tâche Max » : c'est un chemin faux (a:none a déjà menti
# une fois, run F4, quand OC_STORE_DIR valait /.local/share/opencode). Panne nommée, pas silence.
[ -d "$STORE" ] || ko a:stockage

# Dernier commit de code : hors MEMORY et hors artefacts FullRun (même règle que le diagnostic).
last_commit=$(git -C "$REPO" log -1 --format=%ct -- . ':!MEMORY' ':!.fullrun' 2>/dev/null) || last_commit=0
[[ "$last_commit" =~ ^[0-9]+$ ]] || last_commit=0

# --- a. stockage opencode (SQLite 1.19+ ou arbre JSON) ---
storage=$(python3 - "$STORE" "$AGENTS" "$last_commit" <<'PY'
import glob, json, os, re, sqlite3, sys

store, agents_arg, last_commit = sys.argv[1], sys.argv[2], int(sys.argv[3])
agents = [a for a in agents_arg.split(',') if a]
# Verdict lu UNIQUEMENT dans une conclusion structurée, jamais dans le corps (même règle que lifeos#14) :
#  1. le bloc JSON FINAL {"verdict"|"status"|"result": ...} : le dernier objet JSON du texte, à condition
#     qu'il le termine (un JSON cité au milieu du corps n'est jamais une conclusion) ;
#  2. à défaut, la dernière ligne « VERDICT: PASS|FAIL|BLOCKED » (ligne entière, hors phrase).
# Rien de structuré, ou valeur inconnue : INCONCLUSIF — jamais PASS. Aucun motif FAIL/BLOCK sur le corps.
LINE = re.compile(r'^[ \t>*_#-]*VERDICT[ \t]*[:\uff1a][ \t*_`]*(PASS|FAIL|BLOCKED)\b[ \t*_`]*(?:[(\[\u2014\u2013-].*)?$',
                  re.I)


def word(raw):
    if not isinstance(raw, str):
        return None
    w = raw.strip().lower()
    if w in ('pass', 'approve', 'approved'):
        return 'pass'
    if w in ('fail', 'reject', 'rejected', 'blocked', 'block'):
        return 'fail'
    return None


def final_json(text):
    """Dernier objet JSON (accolades équilibrées, chaînes respectées) s'il termine le texte, sinon None."""
    found, end_found, i = None, -1, 0
    while i < len(text):
        if text[i] != '{':
            i += 1
            continue
        depth, in_str, esc, j, closed = 0, False, False, i, False
        while j < len(text):
            c = text[j]
            if in_str:
                if esc:
                    esc = False
                elif c == '\\':
                    esc = True
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    closed = True
                    break
            j += 1
        if closed:
            try:
                v = json.loads(text[i:j + 1])
                if isinstance(v, dict):
                    found, end_found = v, j + 1
            except Exception:
                pass
            i = j + 1
        else:
            i += 1
    if found is not None and re.fullmatch(r'[\s`]*', text[end_found:]):
        return found
    return None


def verdict_of(out):
    """'pass' | 'fail' | None (inconclusif : aucun verdict structuré)."""
    text = out.strip()
    obj = final_json(text) if text else None
    if obj is not None:
        v = word(obj.get('verdict') if obj.get('verdict') is not None
                 else obj.get('status') if obj.get('status') is not None else obj.get('result'))
        if v:
            return v
    last = None
    for line in text.splitlines():
        m = LINE.match(line)
        if m:
            last = word(m.group(1))
    return last


def parse(d):
    try:
        return json.loads(d)
    except Exception:
        return None


def parts():
    out = []
    read = 0  # sources réellement lues : distingue « pas de Max » de « magasin illisible »
    for db in glob.glob(os.path.join(store, '*.db')):
        try:
            con = sqlite3.connect('file:%s?mode=ro' % db, uri=True)
            rows = con.execute('select session_id, data from part').fetchall()
        except Exception:
            continue
        read += 1
        for _sid, data in rows:
            o = parse(data)
            if o and o.get('tool') == 'task':
                out.append(('db', db, o))
    for base in (os.path.join(store, 'storage', 'part'), os.path.join(store, 'part')):
        if not os.path.isdir(base):
            continue
        read += 1
        for f in glob.glob(os.path.join(base, '*', '*.json')):
            o = parse(open(f, encoding='utf-8', errors='replace').read())
            if o and o.get('tool') == 'task':
                out.append(('fs', store, o))
    return out, read


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


task_parts, sources = parts()
if not sources:
    print('KO:stockage')
    sys.exit(0)

def check(max_agent):
    """None si l'agent a rendu un vrai PASS ; sinon la raison (none|tokens|verdict|time|model)."""
    cands = []
    for kind, src, o in task_parts:
        st = o.get('state') or {}
        inp = st.get('input') or {}
        if inp.get('subagent_type') != max_agent or st.get('status') != 'completed':
            continue
        cands.append((kind, src, o, st, inp))
    if not cands:
        return 'none'
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
        v = verdict_of(str(st.get('output') or ''))
        if v is None:
            reasons.add('inconclusif')
            continue
        if v != 'pass':
            reasons.add('verdict')
            continue
        return None
    for r in ('tokens', 'verdict', 'inconclusif', 'time'):
        if r in reasons:
            return r
    return 'model'


for agent in agents:
    why = check(agent)
    if why:
        print('KO:%s' % why)
        sys.exit(0)
print('OK')
PY
) || ko a:stockage
[ "$storage" = OK ] || ko "a:${storage#KO:}"

# --- b. hooks.log : ligne du plugin PAR agent exigé, postérieure au dernier commit de code ---
IFS=',' read -r -a agent_list <<<"$AGENTS"
for ag in "${agent_list[@]}"; do
  hooks_ok=0
  if [ -f "$HOOKS" ]; then
    while IFS= read -r line; do
      case "$line" in *"SUBAGENT done subagent_type=$ag ok=true"*) ;; *) continue ;; esac
      ts=${line%% *}
      epoch=$(date -u -d "$ts" +%s 2>/dev/null) || continue
      if [ "$epoch" -gt "$last_commit" ]; then hooks_ok=1; break; fi
    done <"$HOOKS"
  fi
  [ "$hooks_ok" -eq 1 ] || ko b:hooks
done
[ "$ONLY" = verdict ] && ok

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
