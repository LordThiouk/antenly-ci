# Tâche : ajouter acr-senegal comme dépôt cible de opencode-task.yml

Dépôt : LordThiouk/antenly-ci, branche feat/opencode-task-acr-senegal-2026-11-24 (déjà poussée, contient le correctif GITHUB_TOKEN de la PR #48).

## But
Pouvoir lancer une tâche opencode (hors FullRun) sur le dépôt privé LordThiouk/acr-senegal, exactement comme pour antenly. Le secret ANTENLY_TOKEN a déjà accès à acr-senegal.

## À faire (.github/workflows/opencode-task.yml)
1. Ajouter `acr-senegal` aux options de l'input `target_repo` (défaut inchangé : antenly).
2. Accepter `acr-senegal` partout où la cible est validée : test TARGET_REPO, regex de prompt_path (schéma `acr-senegal:<chemin>`), cohérence schéma/cible.
3. Jeton : pour acr-senegal, utiliser ANTENLY_TOKEN, avec les mêmes gardes qu'antenly (modification de .github/workflows refusée, jamais main/master, push fast-forward, gitleaks avant push, sortie d'opencode jamais affichée : dépôt public).
4. Prompts `prompts:<chemin>` lus sur la branche fullrun-prompts du dépôt cible (comme aujourd'hui).
5. Mettre à jour l'en-tête du workflow et le README s'ils listent les cibles.
6. Si la validation des entrées est testée dans les tests de scripts CI (ci-scripts.yml), ajouter le cas acr-senegal. Ne pas toucher ci.yml.

## Interdits
Pas de push sur main, pas de merge, pas de force-push, aucun secret en clair. Ne rien changer d'autre que nécessaire.

## Rendu
Commit(s) sur la branche + `.task/opencode-task-acr-senegal_DONE.md` : changements, tests lancés et résultats.
