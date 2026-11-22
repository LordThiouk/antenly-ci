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
#      structuré = inconclusif, raison a:inconclusif ; lu par le CLI lifeos FullRunVerdict.ts, CLI inutilisable =
#      a:verdict-cli), et sa fin est postérieure au dernier commit de code ;
#   b. hooks.log contient `SUBAGENT done subagent_type=Max ok=true` postérieur au dernier commit
#      (un `on-agent-stop` lancé à la main en bash ne compte pas : il n'écrit pas cette ligne) ;
#   c. OC_DONE_VERIFY (fichier ou liste `;`) : toutes les commandes rendent 0 ;
#   d. arbre propre (hors .fullrun/logs), REPORT.md présent, ISA pas en `phase: complete`.
# Sortie : une seule ligne `done_check=ok` ou `done_check=ko raison=<a|b|c|d>:<détail>` (a:none:<Agent> = aucune tâche terminée pour cet agent de OC_DONE_AGENTS). Jamais de
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
import glob, json, os, shutil, sqlite3, subprocess, sys

store, agents_arg, last_commit = sys.argv[1], sys.argv[2], int(sys.argv[3])
agents = [a for a in agents_arg.split(',') if a]
# Verdict : UNE seule règle, celle du pipeline lifeos (parseReviewVerdict), lue via son CLI
# LIFEOS/TOOLS/FullRunVerdict.ts (stdin -> pass|fail|unknown, code 0/1/3). Ce script ne réimplémente
# plus rien : l'ancien lecteur python ne déballait pas l'enveloppe opencode 1.19 (<task id … state="completed">,
# <task_result>), d'où « pass » côté pipeline et « inconclusif » ici pour le même texte (incident 22 nov. 2026).
#  - pass : code 0 ET sortie « pass » (les deux doivent le dire) ;
#  - fail : code 1 ET sortie « fail » ;
#  - unknown : code 3 ET sortie « unknown » -> INCONCLUSIF, jamais PASS ;
#  - tout le reste (CLI introuvable, bun absent, plantage, délai dépassé, code/sortie incohérents) : panne
#    nommée a:verdict-cli — jamais pass, jamais lue comme un verdict.
# Le CLI est cherché dans OC_VERDICT_CLI, puis /opt/fullrun-tools/FullRunVerdict.js (copie figée root, hors de
# portée de l'agent, comme ce script), puis ~/.claude/LIFEOS/TOOLS/FullRunVerdict.ts (repli, modifiable).


class VerdictCliError(Exception):
    pass


def cli_command():
    cands = [os.environ.get('OC_VERDICT_CLI', ''), '/opt/fullrun-tools/FullRunVerdict.js',
             os.path.expanduser('~/.claude/LIFEOS/TOOLS/FullRunVerdict.ts')]
    cli = next((c for c in cands if c and os.path.isfile(c)), None)
    if cli is None:
        raise VerdictCliError('cli introuvable')
    bun = os.environ.get('OC_BUN') or shutil.which('bun') or os.path.expanduser('~/.bun/bin/bun')
    if not (os.path.isfile(bun) and os.access(bun, os.X_OK)):
        raise VerdictCliError('bun introuvable')
    return [bun, cli]


def verdict_of(out):
    """'pass' | 'fail' | None (inconclusif : le CLI dit unknown). VerdictCliError si le CLI est inutilisable."""
    cmd = cli_command()
    try:
        r = subprocess.run(cmd, input=out, capture_output=True, text=True, timeout=30)
    except Exception as e:
        raise VerdictCliError('cli: %s' % type(e).__name__)
    said = r.stdout.strip()
    if (r.returncode, said) == (0, 'pass'):
        return 'pass'
    if (r.returncode, said) == (1, 'fail'):
        return 'fail'
    if (r.returncode, said) == (3, 'unknown'):
        return None
    raise VerdictCliError('cli rc=%s' % r.returncode)


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
        try:
            v = verdict_of(str(st.get('output') or ''))
        except VerdictCliError:
            reasons.add('verdict-cli')
            continue
        if v is None:
            reasons.add('inconclusif')
            continue
        if v != 'pass':
            reasons.add('verdict')
            continue
        return None
    for r in ('verdict-cli', 'tokens', 'verdict', 'inconclusif', 'time'):
        if r in reasons:
            return r
    return 'model'


for agent in agents:
    why = check(agent)
    if why:
        # « none » seul laissait croire qu'il manquait Max : on nomme le premier agent de done_agents sans PASS réel.
        print('KO:%s' % ('none:%s' % agent if why == 'none' else why))
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
