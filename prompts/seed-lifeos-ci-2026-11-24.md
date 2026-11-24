# Amorçage du dépôt central `LordThiouk/lifeos-ci` (étape 1 : socle)

## Objectif
Produire, dans le dossier **`lifeos-ci-seed/`** à la racine de ce dépôt (antenly-ci, branche `seed/lifeos-ci-2026-11-24`), le contenu complet du futur dépôt `LordThiouk/lifeos-ci`. Ce dossier sera ensuite copié tel quel à la racine de lifeos-ci. Rien d'autre dans antenly-ci ne doit changer : **ne modifie aucun fichier hors de `lifeos-ci-seed/`**.

## Sources à réutiliser (une seule copie, dédoublonnée)
- `opencode/` et `.github/workflows/opencode-task.yml`, `opencode-fullrun.yml`, `ci.yml` de ce dépôt (antenly-ci).
- Le dépôt public galass-ci : `git clone --depth 1 https://github.com/LordThiouk/galass-ci /tmp/galass-ci` (lecture seule ; `gh` est interdit). Reprends ses `opencode/*.sh` (allowed-repos, extra-repos, etc.) et son mode de choix `target_repo`/`extra_repos`.
- Fusionne : quand un script existe des deux côtés, garde la version la plus récente/robuste et unifie-la, sans dupliquer. Interdit de lire : `evidence/`, `kuna_*.c`, `match_*.md`, `humanified_example.js`.

## Arborescence attendue dans `lifeos-ci-seed/`
```
README.md                          (court : rôle, modes, inputs, règles lifeos_write, quota)
models.txt                         (un modèle par ligne, ordre de priorité, uniquement opencode/*-free)
targets/allowed-repos.sh           (liste blanche + validation)
opencode/                          (scripts communs repris et unifiés)
opencode/lifeos-guard.sh           (garde-fou lifeos_write)
opencode/quota.sh                  (détection quota + choix du modèle)
opencode/notify.sh                 (webhook de fin)
opencode/tests/lifeos-guard-test.sh
opencode/tests/quota-test.sh
opencode/tests/allowed-repos-test.sh
opencode/tests/run-all.sh          (lance tous les tests, code de sortie ≠ 0 si un échoue)
.github/workflows/ci.yml
.github/workflows/task.yml
.github/workflows/_agent-run.yml
.github/workflows/_next.yml
.github/workflows/fr-plan-vera.yml
REPORT.md
```

## Spécifications

### targets/allowed-repos.sh
- Liste blanche exacte (propriétaire `LordThiouk`) : `antenly, antenly-ci, galass-ci, Galass_Rider, Galass_Driver, Galass_backend, galass-emu-actions-pub, lifeos, lifeos-ci`.
- Fonction/CLI qui valide `target_repo` et chaque élément de `extra_repos` (liste séparée par virgules/espaces, regex stricte `^[A-Za-z0-9._-]+$`, pas de `..`). Tout dépôt hors liste → refus, code ≠ 0.

### Inputs communs (task.yml et chaque fr-*.yml)
`workflow_dispatch` avec : `target_repo` (type `choice`, options = liste blanche, défaut `antenly`), `extra_repos` (string, défaut vide), `lifeos_write` (boolean, défaut **false**), `branch` (string, requis, jamais main/master, jamais `refs/*`, pas de `..`), `prompt_path` (string, requis ; schéma `prompts:<chemin>` lu sur la branche `fullrun-prompts` de **lifeos-ci**, ou `target:<chemin>` lu sur la branche cible), `isa_path` (string, défaut vide), `job_name` (string, requis, `^[A-Za-z0-9._-]{1,64}$`), `lifeos_ref` (string, défaut `main`), `timeout_minutes` (défaut 45, 10 à 90).

### Jetons et secrets
- Jeton unique : `secrets.CI_TOKEN` (accès à tous les dépôts). Autres secrets : `ISA_STAMP_KEY`, `OC_NOTIFY_URL`, `OC_NOTIFY_KEY`, `HF_TOKEN`. Ne jamais les afficher (`::add-mask::` si besoin), jamais les passer à opencode.
- Auteur des commits : `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`.
- Jamais de push sur `main`/`master` dans aucun dépôt : uniquement push fast-forward sur la branche `branch` puis PR (créée par le workflow, jamais par opencode). Vérification gitleaks avant push (reprendre la porte de `opencode-task.yml`). Interdits à opencode (config permission) : `git push*`, `git merge*`, `gh *`, `ssh`, `scp`, `*git remote*`, `*http.extraheader*`.

### Garde-fou lifeos_write (opencode/lifeos-guard.sh)
- `lifeos_write=false` (défaut) :
  - lifeos est cloné dans un répertoire **en lecture seule** (`chmod -R a-w`), sans identifiants dans le remote ;
  - si `target_repo=lifeos` ou si `extra_repos` contient `lifeos` en écriture → **refus** ;
  - avant tout push ou création de PR, le script vérifie que le dépôt destination n'est pas `LordThiouk/lifeos` (comparaison insensible à la casse, avec ou sans `.git`, URL https ou `owner/repo`) ; sinon refus, code ≠ 0, message `::error::`.
- `lifeos_write=true` : push sur une branche ≠ main/master puis PR vers lifeos autorisés.
- Dans tous les cas, refus de toute destination `main`/`master`.

### Quota (opencode/quota.sh + models.txt)
- `models.txt` : reprendre l'ordre de la chaîne actuelle d'antenly-ci (`opencode/deepseek-v4.1-flash-free`, `opencode/mimo-v2.6-flash-free`, `opencode/iceman-free`, `opencode/nemotron-3.5-lightning-free`, `opencode/beam-free`, `opencode/hy4-flash-free`). Lignes vides et `#` ignorées ; toute ligne non `^opencode/[a-z0-9.-]+-free$` → refus.
- Détection du **vrai** quota : uniquement dans le journal interne `~/.local/share/opencode/log/*` et dans les lignes d'erreur de la sortie opencode (lignes de niveau ERROR / erreurs fournisseur : `429`, `rate limit`, `quota`, `insufficient`, `exceeded`, `FreeUsageLimitError` ou équivalents réels trouvés dans les scripts existants). **Ignorer** les lignes de diff (`^[+-]`, `^@@`), les blocs de code et le contenu de fichiers : un fichier contenant le mot « quota » ne doit jamais déclencher la bascule.
- **Une seule bascule** par run vers le modèle suivant disponible de models.txt. Si le modèle de secours est lui aussi épuisé (ou s'il n'y en a plus) → statut `quota`, fin propre, **pas de lien suivant** (_next.yml ne déclenche rien). Aucun contournement (pas de rotation infinie, pas de modèle payant, pas de nouvelle clé).

### Workflows
- `_agent-run.yml` : workflow réutilisable (`workflow_call`) qui porte toute la logique commune : validation des entrées (allowed-repos.sh), checkout cible + extra_repos avec CI_TOKEN, clone lifeos (lecture seule ou non selon lifeos_write) à `lifeos_ref`, préparation du prompt (préambule + prompt + ISA si `isa_path`), installation opencode (version figée comme antenly-ci : `1.19.4`), quota.sh, exécution avec timeout, porte gitleaks, lifeos-guard.sh, push fast-forward sur `branch`, PR (brouillon) si absente, webhook de fin, sorties `status`, `model`, `head_sha`. `concurrency: group: agent-${{ inputs.target_repo }}`, `cancel-in-progress: false` (concurrence 1 par dépôt cible). `permissions` minimales. Condition `github.actor == 'LordThiouk'`.
- `task.yml` : tâche simple (revues, correctifs, réglages), appelle `_agent-run.yml` avec `agent: task`, aucun enchaînement.
- `fr-plan-vera.yml` : premier agent FullRun (Plan / Vera), appelle `_agent-run.yml` avec `agent: vera`, puis `_next.yml` si `status == ok`.
- `_next.yml` : réutilisable ; table d'enchaînement `vera → serena → engineer → anvil → forge-code → aditi-ui → forge-audit → silas → code-review → max` ; déclenche `gh workflow run fr-<phase>-<agent>.yml` suivant avec les mêmes inputs **seulement** si le statut est `ok` et que le workflow suivant existe ; sinon rien (journalise « fin de chaîne »). Jamais si statut `quota`.
- Webhook de fin (`opencode/notify.sh`, appelé en `if: always()` à chaque run) : `POST $OC_NOTIFY_URL`, en-têtes `Authorization: Bearer $OC_NOTIFY_KEY` et `X-Automation-Key: $OC_NOTIFY_KEY`, JSON construit avec `jq -cn` : `{job, agent, status, target_repo, branch, model, sha, run_url, message}`, `--max-time 15`, jamais bloquant.
- `ci.yml` : sur `push` et `pull_request`, lance `bash opencode/tests/run-all.sh` + `shellcheck` sur `opencode/*.sh targets/*.sh` + `actionlint` sur les workflows.

### Tests shell (sans réseau, sans secret, sans fausse clé ressemblant à un vrai jeton)
- `lifeos-guard-test.sh` : au minimum — false + destination lifeos (https, `owner/repo`, casse différente, `.git`) → refus ; false + destination antenly → OK ; true + lifeos branche feature → OK ; true + lifeos `main` → refus ; tout dépôt + `main`/`master` → refus ; false + target_repo=lifeos → refus.
- `quota-test.sh` : log interne avec vraie erreur 429/limite → bascule vers le modèle suivant ; sortie contenant un diff `+ quota exceeded` ou un bloc de code mentionnant quota → **pas** de bascule ; deuxième modèle aussi épuisé → statut `quota` et pas de lien suivant ; models.txt avec un modèle non `-free` → refus.
- `allowed-repos-test.sh` : dépôts autorisés OK, inconnus et injections (`../x`, `a;b`, `LordThiouk/autre`) refusés.

## Critères d'acceptation
1. Tous les fichiers listés existent dans `lifeos-ci-seed/`, scripts exécutables (`chmod +x`), `set -euo pipefail`.
2. `bash lifeos-ci-seed/opencode/tests/run-all.sh` passe (exécuté depuis `lifeos-ci-seed/`).
3. `shellcheck` sans erreur sur les scripts (installe-le si absent, `apt-get`/binaire officiel) ; `actionlint` sans erreur sur les 5 workflows (installe-le via le binaire officiel si possible ; sinon indique-le dans REPORT.md).
4. Aucune référence en dur à antenly-ci comme dépôt d'exécution dans les workflows (tout pointe vers lifeos-ci). Aucun secret ni valeur de clé.
5. Aucun fichier modifié hors de `lifeos-ci-seed/` (`git diff --name-only main... | grep -v '^lifeos-ci-seed/'` vide).
6. `lifeos-ci-seed/REPORT.md` : liste des fichiers repris (source antenly-ci/galass-ci → destination), décisions de fusion, et **sortie brute** collée de `run-all.sh`, `shellcheck` et `actionlint`.
7. Un ou plusieurs commits sur la branche courante, auteur `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. Résumé (SHA, tests, résultats) dans `/tmp/task_done.md`.
