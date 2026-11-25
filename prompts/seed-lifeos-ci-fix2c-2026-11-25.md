# Fix2c : ci.yml seulement

Branche `seed/lifeos-ci-2026-11-24` (HEAD a71fc3a). Modifie **uniquement** `lifeos-ci-seed/.github/workflows/ci.yml`. **Ne modifie pas** `opencode-fullrun.yml` (copie de référence) ni aucun autre fichier. Interdit : `git push`, `gh`. Run court (10 min).

1. **actionlint** : passe à la dernière version stable (trouve-la avec `git ls-remote --tags https://github.com/rhysd/actionlint`). Garde le téléchargement du binaire officiel avec vérification de somme (fichier `checksums` de la release). Installe-la localement et lance `actionlint .github/workflows/*.yml` depuis `lifeos-ci-seed/` : indique si l'erreur « maximum number of inputs for workflow_dispatch » disparaît.
2. **Tests shell** : l'étape `Tests shell` doit tourner même si ShellCheck ou Actionlint échouent (`if: ${{ !cancelled() }}` ou étapes indépendantes), et le job reste en échec si une étape échoue.
3. **bun** : ajoute `oven-sh/setup-bun` **épinglé par SHA complet** (dernier tag v2 : `git ls-remote https://github.com/oven-sh/setup-bun 'refs/tags/v2*'`, commentaire `# vX.Y.Z`), avant les tests.
4. Commit, auteur `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. Dans `/tmp/task_done.md` : SHA, version actionlint, SHA de setup-bun, résultat local d'actionlint (erreur 1 présente/absente).
