# lifeos-ci

Socle CI d'automatisation opencode pour les dépôts `LordThiouk`.

## Rôle

- `task.yml` : tâche opencode simple (revue, correctif, réglage), sans enchaînement.
- `fr-plan-vera.yml` : premier agent FullRun (Plan / Vera), puis `_next.yml` si le run
  est `ok`.
- `_agent-run.yml` : logique commune (validation, checkouts, prompt, quota,
  gitleaks, push fast-forward, PR brouillon, notification).
- `_next.yml` : table `vera → serena → engineer → anvil → forge-code → aditi-ui →
  forge-audit → silas → code-review → max`. Rien n'est déclenché si le statut
  n'est pas `ok` (notamment `quota`) ou si le workflow suivant n'existe pas.

## Inputs communs

`target_repo` (choice, liste blanche), `extra_repos`, `lifeos_write` (bool,
défaut `false`), `branch`, `prompt_path`, `isa_path`, `job_name`, `lifeos_ref`
(défaut `main`), `timeout_minutes` (10 à 90).

`prompt_path` accepte `prompts:<chemin>` (branche `fullrun-prompts` de lifeos-ci)
ou `target:<chemin>` (branche cible).

## Règles lifeos_write

- `false` (défaut) : lifeos est cloné en lecture seule (`chmod -R a-w`), sans
  identifiants dans le remote. `target_repo=lifeos` et tout `lifeos` en
  `extra_repos` sont refusés. Aucun push ni PR vers `LordThiouk/lifeos`.
- `true` : les changements lifeos sont committés par le workflow sur une branche
  dédiée `lifeos-ci/<job_name>`, poussés par le workflow puis ouverts en PR
  brouillon vers lifeos. Jamais `main`/`master`, jamais de fusion automatique.
- Dans tous les cas, `main`/`master` sont des destinations interdites. Le
  workflow pousse en fast-forward et ouvre la PR ; opencode ne pousse jamais.

## Quota et modèles

`models.txt` liste les modèles gratuits par ordre de priorité (uniquement
`opencode/*-free`). `opencode/quota.sh` ne détecte le quota que dans le journal
interne `~/.local/share/opencode/log/*` et dans les vraies lignes d'erreur
fournisseur (429, rate limit, quota, insufficient, exceeded, FreeUsageLimitError).
Les diffs et les blocs de code sont ignorés. Une seule bascule par run : si le
modèle de secours est aussi épuisé, le run finit avec le statut `quota`, sans
lien suivant.

## Sécurité

- Jeton unique `CI_TOKEN` ; jamais passé à opencode ni affiché.
- Auteur des commits : `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`.
- Porte gitleaks avant tout push.
- opencode ne peut ni `git push`, ni `git merge`, ni `gh`, ni `ssh`/`scp`, ni
  toucher `git remote` ou `http.extraheader`.

## Tests

```bash
bash opencode/tests/run-all.sh
shellcheck -x opencode/*.sh targets/*.sh
actionlint .github/workflows/*.yml
```
