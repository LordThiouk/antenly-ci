# Revue du socle lifeos-ci (LECTURE SEULE)

Contexte : branche `seed/lifeos-ci-2026-11-24`, dossier `lifeos-ci-seed/` (identique à la PR LordThiouk/lifeos-ci#1).

## Règles
- **Aucun changement de code.** Le seul fichier que tu crées ou modifies est `lifeos-ci-seed/REVIEW.md`.
- Interdit : `git push`, `gh`. Lecture seule de galass-ci : `git clone --depth 1 https://github.com/LordThiouk/galass-ci /tmp/galass-ci`.
- Ne lis jamais `evidence/`, `kuna_*.c`, `match_*.md`, `humanified_example.js`. N'affiche aucun secret.

## Contenu de REVIEW.md
1. **Provenance** : un tableau avec, pour chaque script (`opencode/*.sh`, `targets/*.sh`, `opencode/tests/*`) et chaque workflow (`.github/workflows/*.yml`) de `lifeos-ci-seed/`, la colonne source (fichier d'antenly-ci `main` : `opencode/`, `.github/workflows/`, ou de galass-ci), ou « nouveau ». Ajoute un diff résumé (repris tel quel / adapté : quoi / réécrit). **Signale explicitement** tout fichier réécrit ou créé sans raison alors qu'un script existant faisait déjà le travail (ex. allowed-repos.sh, extra-repos.sh, redact-log.sh, livelog.sh, porte gitleaks, notification), en citant le fichier existant.
2. **Défauts bloquants**, chacun avec `fichier:ligne`, la gravité et la correction suggérée (sans l'appliquer) :
   - sécurité `lifeos_write` : contournement du garde-fou, clone lifeos accessible en écriture quand false, défaut différent de false dans task.yml, perte de la valeur dans la chaîne `_next.yml` ;
   - fuite de secrets : jeton dans une URL de remote, `echo` ou `set -x` de secrets, secrets passés à opencode, sortie opencode publiée sur un dépôt public ;
   - quota : faux positif possible (diff/code), plus d'une bascule, modèle non `-free`, enchaînement malgré le statut `quota` ;
   - push sur `main`/`master` possible dans un dépôt ; push fait par opencode au lieu du workflow ;
   - concurrence (1 par dépôt cible), condition `github.actor`, permissions trop larges.
3. **Verdict final** sur une ligne : `VERDICT: OK` ou `VERDICT: À CORRIGER` (avec la liste numérotée des corrections obligatoires).

## Fin
- Vérifie que `git diff --name-only HEAD~1..HEAD` après ton commit ne contient que `lifeos-ci-seed/REVIEW.md`.
- Commit auteur `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. Résumé (SHA, verdict) dans `/tmp/task_done.md`.
