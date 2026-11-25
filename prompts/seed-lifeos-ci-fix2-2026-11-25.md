# Socle lifeos-ci : Fix2 (preuves de tests, allowed-repos-test d'origine, 3 défauts critiques)

Contexte : branche `seed/lifeos-ci-2026-11-24` (HEAD 620e51f). Modifie **uniquement** `lifeos-ci-seed/`. Interdit : `git push`, `gh`. galass-ci en lecture seule : `git clone --depth 1 https://github.com/LordThiouk/galass-ci /tmp/galass-ci`. antenly-ci : `origin/main`. Ne lis jamais `evidence/`, `kuna_*.c`, `match_*.md`, `humanified_example.js`. Aucun secret.

## A. Preuve que TOUS les tests tournent
- Vérifie que `opencode/tests/run-all.sh` lance **chaque** fichier `opencode/tests/*-test.sh` (liste-les ; aucun oublié).
- Installe actionlint 1.7.7 si absent (binaire officiel de la release GitHub rhysd/actionlint v1.7.7) et shellcheck si absent.
- Exécute depuis `lifeos-ci-seed/` : `bash opencode/tests/run-all.sh`, `shellcheck opencode/*.sh targets/*.sh`, `actionlint .github/workflows/*.yml`.
- Test copié en échec : corrige **uniquement le chemin ou l'adaptation** (dépôt, répertoire, variable d'emplacement), **jamais la logique ni les assertions**. Liste chaque correction (fichier, ligne, avant → après, raison).

## B. allowed-repos-test.sh
- Restaure `opencode/tests/allowed-repos-test.sh` à l'identique de la version de galass-ci (`cp`), adaptée seulement aux chemins.
- Les cas propres à la liste étendue de lifeos-ci (antenly, antenly-ci, galass-ci, lifeos, lifeos-ci…) vont dans un fichier séparé `opencode/tests/allowed-repos-lifeos-test.sh`, si nécessaire.
- Explique dans REPORT.md pourquoi chaque cas ajouté est nécessaire.

## C. Les 3 défauts CRITIQUES de REVIEW.md
Avant d'écrire quoi que ce soit, cherche si `opencode-task.yml`/`opencode-fullrun.yml` d'antenly-ci ou les workflows de galass-ci ont déjà la protection ; si oui, **reprends-la** et cite la source.
1. **Scripts de confiance modifiables par l'agent exécutés après opencode** : prendre une copie des scripts de confiance (`opencode/`, `targets/`) **avant** l'étape opencode, dans un répertoire hors de l'espace de travail de l'agent (non accessible en écriture par lui), et exécuter les étapes post-opencode (garde-fou lifeos, quota, gitleaks, push, PR, notification) **depuis cette copie**.
2. **Hooks git exécutés avec CI_TOKEN** : toute étape qui utilise un jeton (fetch/push/PR) force `git -c core.hooksPath=/dev/null` (et ignore les configurations locales modifiées par l'agent : pas de `include`, pas d'alias, `GIT_CONFIG_NOSYSTEM=1` si pertinent).
3. **État modifiable cru par les étapes suivantes** (`GITHUB_ENV`, `GITHUB_OUTPUT`, `RUNNER_TEMP`) : opencode ne doit pas avoir accès à ces fichiers (les retirer de son environnement, répertoire temporaire distinct) ; les étapes suivantes **recalculent** les valeurs (SHA de base, statut, modèle, branche) au lieu de les relire depuis un état modifiable par l'agent.
- Ajoute **un test par défaut corrigé** (`opencode/tests/critical-<n>-test.sh` ou noms explicites), sans réseau ni secret, ajoutés à `run-all.sh`.
- Dans `REVIEW.md`, coche les 3 défauts critiques (`[x]`) avec le commit et le test correspondants. Ne traite pas les défauts « élevés » (run suivant).

## REPORT.md : section « Fix2 (2026-11-25) »
- Liste des tests exécutés (un par ligne) et **sortie brute** de run-all.sh, shellcheck, actionlint (avec la version d'actionlint).
- Corrections de chemins (A), explication (B), protections (C) avec leur source si reprises.

## Fin
- `git diff --name-only 620e51f..HEAD | grep -v '^lifeos-ci-seed/'` doit être vide.
- Commits avec l'auteur `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. Résumé (SHA, nombre de tests, PASS/FAIL, critiques corrigés) dans `/tmp/task_done.md`.
