# Socle lifeos-ci : reprendre l'existant (COPIE, pas de réécriture)

Contexte : branche `seed/lifeos-ci-2026-11-24`, dossier `lifeos-ci-seed/`. Règle de Papa : lifeos-ci **reprend tout ce qui existe** dans antenly-ci et galass-ci au lieu de recréer.

## Règles
- Ne modifie que des fichiers sous `lifeos-ci-seed/`. Interdit : `git push`, `gh`.
- galass-ci en lecture seule : `git clone --depth 1 https://github.com/LordThiouk/galass-ci /tmp/galass-ci`. Pour antenly-ci, prends `main` (`git show main:opencode/<f>` ou `git worktree add /tmp/antenly-main main`).
- Ne lis jamais `evidence/`, `kuna_*.c`, `match_*.md`, `humanified_example.js`. Aucun secret.
- **Ne corrige pas les défauts de REVIEW.md dans ce run** (ce sera le run suivant).

## Copie (avec `cp`, jamais réécrit à la main) vers `lifeos-ci-seed/opencode/`
- Depuis antenly-ci (main) et/ou galass-ci : `livelog.sh`, `leaklog.sh`, `redact-log.sh`, `progress.sh`, `autosave.sh`, `autosave-deny.txt`, `checkpoint.sh`, `wippush.sh`, `done_check.sh`, `done-check-call.sh`, `split-diff.sh`, `run-fullrun.sh`, `step-agents.sh`, `install-hook-profile.sh`, `log-recipient.txt`, `preannot.sh`, `bench-capped`, `config/opencode.json`.
- Depuis galass-ci : `extra-repos.sh`, `merge-signed-carry.sh`, `emu-e2e.sh`.
- **Tous** leurs tests : `opencode/tests/*` des deux dépôts, dont `lib.sh` et `verdict-cli.lib`.
- Si un fichier est absent des deux dépôts, ne l'invente pas : note-le « absent » dans le tableau.
- Si un fichier existe dans les deux dépôts avec un contenu différent : prends la version la plus récente (`git log -1 --format=%cI -- <f>` dans chaque dépôt) ou la plus complète, et note le choix et la raison.
- Si un fichier existe déjà dans `lifeos-ci-seed/opencode/` : remplace-le par la copie de la source seulement si le fichier du seed était une réécriture d'un script existant ; sinon garde-le et note-le.
- Conserve les droits d'exécution (`cp -p`).

## Adaptations autorisées (minimales)
Uniquement ce qui est nécessaire : chemins, nom du dépôt (antenly-ci/galass-ci → lifeos-ci), `target_repo`. Rien d'autre. Chaque adaptation est listée.

## REPORT.md : nouvelle section « Copie (2026-11-25) »
- Tableau `fichier → source (dépôt:chemin@sha court) → identique / adapté (détail) / absent`.
- Choix entre versions divergentes, avec la raison.
- Relance `bash opencode/tests/run-all.sh` (depuis `lifeos-ci-seed/`) en **incluant les tests copiés** (ajoute-les à run-all.sh), `shellcheck` sur `opencode/*.sh targets/*.sh`, `actionlint` sur les workflows. Colle la **sortie brute**. Si un test copié échoue à cause d'une dépendance à l'ancien dépôt, ne le réécris pas : note l'échec et sa cause.

## Fin
- Vérifie que `git diff --name-only 9523ea4..HEAD | grep -v '^lifeos-ci-seed/'` est vide.
- Commits avec l'auteur `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. Résumé (SHA, nombre de fichiers copiés/adaptés, résultats des tests) dans `/tmp/task_done.md`.
