# Fix2a : vérification seule (aucune correction)

Branche `seed/lifeos-ci-2026-11-24` (HEAD e956ccf). Travaille dans `lifeos-ci-seed/` uniquement. Interdit : `git push`, `gh`, modifier du code ou des tests. Ne lis jamais `evidence/`, `kuna_*.c`, `match_*.md`, `humanified_example.js`. Run court : sois rapide.

1. Installe shellcheck si absent, et actionlint **1.7.7** si absent (binaire officiel de la release rhysd/actionlint v1.7.7).
2. Depuis `lifeos-ci-seed/`, exécute et capture la sortie brute (stdout+stderr, code de sortie) de :
   - `bash opencode/tests/run-all.sh` ; vérifie qu'il lance **tous** les `*-test.sh`, y compris `opencode/tests/upstream-fullrun/` ; s'il en oublie, exécute aussi les manquants un par un (`bash <fichier>`) ;
   - `shellcheck opencode/*.sh targets/*.sh` ;
   - `actionlint .github/workflows/*.yml` (avec `actionlint -version`).
3. Ajoute à `lifeos-ci-seed/REPORT.md` une section `## Fix2a (2026-11-25)` : la liste des tests exécutés, la sortie brute de chaque commande et la **liste des échecs** (fichier, message), **sans rien corriger**.
4. Commit (seul `lifeos-ci-seed/REPORT.md` modifié), auteur `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. Résumé (SHA, PASS/FAIL) dans `/tmp/task_done.md`.
