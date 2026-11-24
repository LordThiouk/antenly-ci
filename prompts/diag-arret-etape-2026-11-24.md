# Tâche : diagnostiquer et corriger « le FullRun ne s'arrête pas après l'étape demandée »

## Symptômes prouvés (2026-11-24)
1. Antenly, run 45328234540 (job `moteur-corrections-vera-2026-11-24-r2`, `start_step=vera`, `stop_after_step=vera`, `chain_enabled=false`) : au lieu de s'arrêter après vera, opencode a aussi écrit du code (`scripts/corpus/bench/*.py`, ~1 200 lignes, branche antenly `fullrun/moteur-corrections-2026-11-24`, commit 03bddd8), puis le job a fini en échec après 1 h 05 avec la raison `a:none:Max` (attente d'un verdict Max) et un timeout.
2. Galass (même logique dans galass-ci), run 45320422961 (`start_step=serena`, `stop_after_step=serena`, `done_agents=Architect`) : opencode a déroulé build, verify, max et close, puis le job a fini sur le plafond de temps (`DONE_REASON: a:time`, `OC_STOP: tour`), car le validateur de fin attendait un verdict « Architect » jamais émis.

## Règle de Papa à respecter (ne jamais changer)
Un job = une seule étape (vera, serena, build, verify, max, close), lancée à la main. Le job doit s'arrêter dès que l'étape demandée est finie et validée par l'agent de cette étape. Les 8 étapes et leurs agents de FullRunPipeline.ts ne changent pas.

## À faire
1. Lire `.github/workflows/opencode-fullrun.yml` et les scripts qu'il appelle (préambule CI, porte de fin, validateur, carry) et trouver précisément :
   a. pourquoi `stop_after_step` n'empêche pas opencode de passer aux étapes suivantes (consigne donnée à opencode, garde côté workflow) ;
   b. pourquoi le validateur attend un agent (Max, Architect) qui ne correspond pas à l'étape demandée, au lieu de l'agent de l'étape (vera → Algorithm, serena → Architect, etc.) ou de `done_agents`.
2. Écrire un rapport simple en français `docs/reports/diag-arret-etape-2026-11-24.md` : cause exacte (fichier et lignes), correction proposée, risques.
3. Écrire la correction : tout changement dans `.github/workflows/` va sous forme de patch `docs/patches/diag-arret-etape-2026-11-24.patch` (applicable avec `git apply` sur main) ; les autres fichiers peuvent être modifiés directement. Ajouter un test ou un contrôle qui prouve que l'étape s'arrête bien.
4. Indiquer dans le rapport si la même correction doit être reportée dans galass-ci.
5. Commiter sur la branche courante, ne jamais pousser (le workflow pousse après gitleaks), jamais main, aucun secret. Résumé court dans `/tmp/task_done.md`.
