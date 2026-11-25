# Fix2b : copier les fichiers manquants des tests upstream-fullrun

Branche `seed/lifeos-ci-2026-11-24` (HEAD 66034c5). Modifie **uniquement** `lifeos-ci-seed/`. Interdit : `git push`, `gh`. Règle : on **copie** ce qui existe, on ne retire **aucun** test et on ne change **jamais** la logique d'un test. Ne lis jamais `evidence/`, `kuna_*.c`, `match_*.md`, `humanified_example.js`. Run court (10 min) : **commit après chaque étape** (auteur `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`).

Sources : antenly-ci `origin/main` (`git show origin/main:<chemin>` ou `git worktree add /tmp/antenly-main origin/main`) ; galass-ci en lecture seule : `git clone --depth 1 https://github.com/LordThiouk/galass-ci /tmp/galass-ci`.

1. **Copier les manquants.** Pour chaque fichier cité par `lifeos-ci-seed/opencode/tests/upstream-fullrun/*` et absent du seed (au minimum : `run-fullrun.sh`, `.github/workflows/opencode-fullrun.yml`, `chain.sh`, `guard.sh`, `prep.sh`, `save.sh`, `restore.sh`, `ci-preamble.md`, `lib.sh`), cherche-le dans **tous** les chemins des deux dépôts (`git ls-files | grep`, dont `.github/scripts/`, `opencode/`, `opencode/fullrun/`, `prompts/`), puis **copie-le tel quel** (`cp -p`) dans `lifeos-ci-seed/` au même chemin relatif. `opencode-fullrun.yml` va dans `lifeos-ci-seed/.github/workflows/`. Fichier introuvable : note-le « absent ». **Commit.**
2. **Chemins des tests.** Corrige seulement les chemins (emplacement du dépôt, répertoire des scripts) dans les tests `upstream-fullrun/`, jamais les assertions. **Commit.**
3. **run-all.sh.** Ajoute `opencode/tests/upstream-fullrun/*-test.sh` à `run-all.sh`. **Commit.**
4. **bun.** N'installe pas bun. Repère les tests qui ont besoin de bun et marque-les « besoin de bun » dans REPORT.md (bun sera ajouté à `ci.yml` au run suivant).
5. Depuis `lifeos-ci-seed/`, lance `bash opencode/tests/run-all.sh` et ajoute à `REPORT.md` une section `## Fix2b (2026-11-25)` : les fichiers copiés (source dépôt:chemin → destination), les chemins corrigés, la **sortie brute**, et les **échecs restants avec leur cause**. **Commit.** Résumé (SHA, PASS/FAIL) dans `/tmp/task_done.md`.
