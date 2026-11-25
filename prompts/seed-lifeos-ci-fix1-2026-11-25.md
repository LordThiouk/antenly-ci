# Correctifs du socle lifeos-ci (fix1)

Contexte : branche `seed/lifeos-ci-2026-11-24`, socle déjà produit (commits f14305e, 5f4cc45). **Modifie uniquement des fichiers sous `lifeos-ci-seed/`.** Interdit : `git push`, `gh`. Ne lis jamais `evidence/`, `kuna_*.c`, `match_*.md`, `humanified_example.js`.

## 1) Notification : ne plus avaler l'erreur
- `lifeos-ci-seed/opencode/notify.sh` et toute étape de notification dans `lifeos-ci-seed/.github/workflows/*.yml` : supprimer tout `>/dev/null || true` muet.
- Garder la notification **non bloquante** pour le run (code de sortie 0 du script même en échec), mais récupérer le code HTTP (`curl -sS -o <fichier temp> -w '%{http_code}'`), l'afficher (`notify: HTTP <code>`) et émettre `::warning::notification échouée (HTTP <code>)` si ce n'est pas 2xx (y compris 000/timeout).
- Ne jamais afficher la clé (`OC_NOTIFY_KEY`) ni les en-têtes ; ne pas afficher le corps de réponse s'il peut contenir des données sensibles (au plus 200 caractères, sans en-têtes).
- Test : `opencode/tests/notify-test.sh` avec un faux `curl` dans le PATH (sans réseau) : 200 → pas de warning ; 401/500/000 → `::warning::` présent, sortie 0 ; la valeur de la clé n'apparaît jamais dans la sortie.

## 2) FullRun et écriture LifeOS
Les agents FullRun écrivent dans LifeOS (ISA via ISATool, verdicts, agents).
- `fr-plan-vera.yml` (et le modèle de futur `fr-*.yml`) expose l'input `lifeos_write` (boolean) et le transmet à `_agent-run.yml` et `_next.yml`.
- `_next.yml` retransmet `lifeos_write` (et tous les autres inputs) **à chaque maillon** de la chaîne (`-f lifeos_write=...`), sans perte ni retour au défaut.
- Dans `_agent-run.yml`, si `lifeos_write=true` : les changements LifeOS sont committés sur une branche dédiée (jamais `main`/`master`), poussés par le workflow (pas par opencode) puis ouverts en PR vers `LordThiouk/lifeos` ; `lifeos-guard.sh` reste appliqué. Si `false` : lifeos en lecture seule, comme aujourd'hui.
- `task.yml` garde `lifeos_write` à `false` par défaut.
- Tests : `opencode/tests/lifeos-chain-test.sh` (analyse statique des YAML avec `yq`/`grep`, sans réseau) : `fr-plan-vera.yml` déclare `lifeos_write` et le passe ; `_next.yml` transmet `lifeos_write` au maillon suivant ; `task.yml` a `default: false` ; aucune destination `main`/`master` pour LifeOS. Ajouter ces tests à `run-all.sh`.

## Fin
- Relance `bash opencode/tests/run-all.sh` (depuis `lifeos-ci-seed/`), `shellcheck` sur les scripts et `actionlint` sur les workflows ; colle la **sortie brute** dans une nouvelle section `## Fix1 (2026-11-25)` de `lifeos-ci-seed/REPORT.md`.
- Vérifie que `git diff --name-only f14305e^..HEAD | grep -v '^lifeos-ci-seed/'` est vide.
- Commits avec l'auteur `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. Résumé (SHA, tests, résultats) dans `/tmp/task_done.md`.
