# Tâche : revue de la PR « un job FullRun s'arrête à l'étape demandée » (branche fix/diag-arret-etape-2026-11-24)

Lire `docs/reports/diag-arret-etape-2026-11-24.md`, le diff de la branche contre `main` (dont `.github/workflows/opencode-fullrun.yml`, `opencode/run-fullrun.sh`, `opencode/step-agents.sh`, `opencode/tests/stop-after-step-test.sh`).

Vérifier en particulier :
1. Qu'un job borné (`stop_after_step`) s'arrête après son étape, sans reprise ni étape suivante, et que le chaînage manuel (`chain_enabled=false`) reste inchangé.
2. Que l'agent validateur par étape respecte la règle de Papa (FullRunPipeline.ts, à ne jamais changer) : 2 vera → Algorithm ; 3 serena → Architect ; 4 build → Designer/Aditi (UI) ou Engineer/Forge/Anvil (logique) ; 5 verify → code-reviewer, Forge, Silas ; 6-7 max/close → Max. Signaler si un seul agent fixe (ex. Forge pour build, Silas pour verify) peut bloquer un job légitime.
3. Pas de secret exposé, pas de régression des autres entrées du workflow, tests réellement exécutés (`bash opencode/tests/stop-after-step-test.sh` et suites existantes).

Écrire `docs/reports/revue-diag-arret-etape-2026-11-24.md` avec une ligne `Verdict : OK` ou `Verdict : À CORRIGER`, puis la liste des problèmes (fichier, ligne, gravité). Ne rien corriger toi-même. Commiter sur la branche courante, ne jamais pousser, jamais main. Résumé court dans `/tmp/task_done.md`.
