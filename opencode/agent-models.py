#!/usr/bin/env python3
"""Bilan déterministe agents → modèles, lu dans la base opencode du runner (lecture seule).
Ne lit que les champs agent / providerID / modelID / erreur des messages assistant."""
import json, os, sqlite3, sys
db = os.path.expanduser("~/.local/share/opencode/opencode.db")
print("## Agents et modèles (base opencode, compté par le workflow)\n")
if not os.path.exists(db):
    print("(base opencode absente)"); sys.exit(0)
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
rows = c.execute("""select coalesce(json_extract(m.data,'$.agent'),'?'),
  coalesce(json_extract(m.data,'$.providerID'),'?')||'/'||coalesce(json_extract(m.data,'$.modelID'),'?'),
  case when s.parent_id is null then 'principal' else 'sous-agent' end,
  count(*), count(distinct m.session_id),
  sum(case when json_extract(m.data,'$.error') is not null then 1 else 0 end)
  from message m join session s on s.id=m.session_id
  where json_extract(m.data,'$.role')='assistant'
  group by 1,2,3 order by 3,1""").fetchall()
print("| agent | modèle | session | messages | sessions | erreurs |\n|---|---|---|---|---|---|")
for a, m, k, n, ns, e in rows:
    print(f"| {a} | {m} | {k} | {n} | {ns} | {e} |")
errs = c.execute("""select distinct coalesce(json_extract(m.data,'$.agent'),'?'), substr(coalesce(json_extract(m.data,'$.error.name'),'')||': '||coalesce(json_extract(m.data,'$.error.data.message'),''),1,160)
  from message m where json_extract(m.data,'$.role')='assistant' and json_extract(m.data,'$.error') is not null limit 30""").fetchall()
if errs:
    print("\n### Erreurs de messages\n")
    for a, e in errs: print(f"- {a} : {e}")
# Diagnostic des arrêts prématurés : derniers textes de l'agent principal (tronqués).
last = c.execute("""select substr(json_extract(p.data,'$.text'),1,600) from part p join session s on s.id=p.session_id
  where s.parent_id is null and json_extract(p.data,'$.type')='text' and json_extract(p.data,'$.synthetic') is not 1
  and p.message_id in (select id from message where json_extract(data,'$.role')='assistant')
  order by p.time_created desc limit 3""").fetchall()
if last:
    print("\n### Derniers messages de l'agent principal (600 car. max, du plus récent au plus ancien)\n")
    for (t,) in last:
        print("> " + (t or "").replace("\n", "\n> ") + "\n")
