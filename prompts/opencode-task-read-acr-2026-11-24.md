# Tâche : permettre aux tâches opencode de lire acr-senegal (lecture seule)

Dépôt : LordThiouk/antenly-ci, branche `feat/opencode-task-read-acr-2026-11-24` (déjà poussée). Fichier visé : `.github/workflows/opencode-task.yml`. IMPORTANT : le jeton de ce job ne peut PAS pousser un fichier sous `.github/workflows/`. Ne commite donc AUCUN fichier sous `.github/`. Fais la modification localement, vérifie-la, puis exporte-la en patch `git diff` dans `docs/patches/opencode-task-read-acr-2026-11-24.patch` (appliquable avec `git apply` depuis la racine sur main), remets `.github/` dans son état d'origine, et commite seulement le patch + le rapport. Nix appliquera le patch tel quel.

## But
Les tâches opencode qui ciblent `antenly` doivent pouvoir LIRE le dépôt privé `LordThiouk/acr-senegal` (pour comparer les moteurs d'empreinte). Aujourd'hui le checkout utilise `persist-credentials: false` et aucun jeton n'arrive à opencode, donc impossible.

## Changement demandé (le plus petit possible)
1. Ajouter une étape AVANT l'exécution d'opencode, active seulement quand `inputs.target_repo == 'antenly'` : `actions/checkout@v4` de `LordThiouk/acr-senegal`, `token: ${{ secrets.ANTENLY_TOKEN }}`, `persist-credentials: false`, `fetch-depth: 0` (toutes les branches), dans un dossier HORS de la cible, par ex. `$RUNNER_TEMP/ro/acr-senegal` (via `path:` relatif au workspace si nécessaire, mais jamais dans `target/`). Rendre l'étape non bloquante (`continue-on-error: true`) et écrire dans le résumé du job si la copie a réussi ou non.
2. Récupérer toutes les branches distantes en local (ex. `git -C <dossier> fetch origin '+refs/heads/*:refs/remotes/origin/*'`) avec le même jeton passé seulement pour cette commande, sans l'écrire dans `.git/config`.
3. Exposer à opencode le chemin via une variable `ACR_SENEGAL_RO=<chemin>` et le mentionner dans le texte de contexte du prompt si le workflow en ajoute un.
4. Le dossier doit rester en lecture seule pour la tâche : `chmod -R a-w` après la copie, et vérifier que la porte de push existante n'inclut jamais ce dossier.
5. Ne pas toucher au reste du workflow (jeton de la cible, porte gitleaks, interdiction de modifier .github/workflows sur antenly, etc.).

## Preuve
- `actionlint` (ou `yamllint` à défaut) passe sur le fichier.
- Rapport court `docs/reports/opencode-task-read-acr-2026-11-24.md` : ce qui a changé, pourquoi, comment l'utiliser dans un prompt.
- Vérifier `git apply --check docs/patches/opencode-task-read-acr-2026-11-24.patch` sur un arbre propre. Pas de PR (Nix l'ouvrira). NE PAS merger.

## Règles
- Modèles gratuits uniquement. Durée < 20 min.
- Pousse uniquement sur `feat/opencode-task-read-acr-2026-11-24`. Jamais main, jamais --force, pas de merge.
- gitleaks avant chaque push. Aucun secret affiché.
- Ne termine jamais par une question.
