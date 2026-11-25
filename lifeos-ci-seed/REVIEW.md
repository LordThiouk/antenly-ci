# Revue du socle lifeos-ci

Branche revue : `seed/lifeos-ci-2026-11-24` (dossier `lifeos-ci-seed/`).
Périmètre : scripts `opencode/*.sh`, `targets/*.sh`, `opencode/tests/*` et
workflows `.github/workflows/*.yml` du dossier `lifeos-ci-seed/`.
Revue statique, sans modification du code. Références de comparaison :
`antenly-ci` `main` et `galass-ci` (`git clone --depth 1`).

Contrôles exécutés pendant la revue :

- `bash lifeos-ci-seed/opencode/tests/run-all.sh` : 5 suites, 0 échec.
- `shellcheck -x lifeos-ci-seed/opencode/*.sh lifeos-ci-seed/targets/*.sh lifeos-ci-seed/opencode/tests/*.sh` : code 0.
- `actionlint` non relancé (binaire absent du runner).

Ces tests sont utiles mais ne détectent pas les défauts de sécurité ci-dessous :
`lifeos-chain-test.sh` est un test statique (`grep`) qui n'exécute ni la chaîne
ni le dispatch réel.

## 1. Provenance

### Scripts

| Fichier de `lifeos-ci-seed/` | Source | Décision / diff résumé |
| --- | --- | --- |
| `opencode/lifeos-guard.sh` | — (nouveau) | Nouveau garde-fou `lifeos_write`. Aucun script équivalent dans `antenly-ci` ou `galass-ci` ; les contrôles existants sont dans les workflows. Logique réécrite, mais contournable (normalisation d’URL incomplète, contrôle readonly ponctuel, ne couvre pas `lifeos` en `target_repo`/`extra_repos` quand `lifeos_write=true`). |
| `opencode/notify.sh` | `antenly-ci/.github/workflows/opencode-task.yml:540-566` (step « Notification de fin »), `antenly-ci/.github/workflows/opencode-fullrun.yml:2059-2160`, `galass-ci/.github/workflows/opencode-fullrun.yml:2145-2166` | Factorisé en script autonome. Ajout utile du code HTTP. Régression : clé passée en arguments `curl` (`-H`) au lieu de stdin `-K -`, pas de `set +x`, script exécuté depuis `ci/` modifiable après opencode. |
| `opencode/quota.sh` | `antenly-ci/.github/workflows/opencode-task.yml:470-489` (détection quota simple), `antenly-ci/opencode/run-fullrun.sh:682-687` (429), `galass-ci/.github/workflows/opencode-fullrun.yml` (chaîne/quota) | Réécrit/étendu (journal interne, `--since-file`, codes 0/10/20, `models.txt`). Bascule unique correcte, modèles `-free` validés. Faux positifs possibles sur lignes de contexte de diff/espace, code indenté hors fence et prose (§2.11). |
| `opencode/tests/allowed-repos-test.sh` | `galass-ci/opencode/tests/allowed-repos-test.sh` | Adapté à la liste LordThiouk, ajoute `validate`, injections, doublons, alignement des options workflow. Ne vérifie pas l’absence de copie en dur dans les scripts/workflows ni le cas `target_repo` répété en `extra_repos`. |
| `opencode/tests/lifeos-chain-test.sh` | — (nouveau) | Test statique (`grep`) de la chaîne et des marqueurs `lifeos_write`. Ne détecte pas `-f` vs `-F`, absence de `--ref`, falsification de statut, ni contournements runtime. |
| `opencode/tests/lifeos-guard-test.sh` | — (nouveau) | Couvre formes de base. Manque URL avec identifiants, `www.github.com`, `.git/` final, query/fragment, port (§2.5). |
| `opencode/tests/notify-test.sh` | — (nouveau) | Vérifie code HTTP et non-divulgation de la clé dans la sortie stdout/stderr du script. Ne couvre pas l’exposition en argv `curl` ni l’exécution depuis `ci/` modifiable. |
| `opencode/tests/quota-test.sh` | — (nouveau) | Couvre 429/rate limit, blocs ``` et lignes `+/-` de diff, `--since-file`. Manque lignes de contexte diff (espace), code indenté hors fence, prose ambiguë (§2.11). |
| `opencode/tests/run-all.sh` | — (nouveau) | Lance les `*-test.sh`. Factorisation simple ; `galass-ci/.github/workflows/ci.yml` itère directement mais le besoin est équivalent. |
| `targets/allowed-repos.sh` | `galass-ci/opencode/allowed-repos.sh` (cœur `allowed_repos_list`/`allowed_repo`) + options `target_repo` de `antenly-ci/.github/workflows/opencode-task.yml` | **Réécrit/déplacé sans nécessité forte**. Le fichier galass existant faisait déjà le travail ; le cœur est identique. Changements : liste LordThiouk, ajout `validate`/`normalize_extra_repos`, déplacement `opencode/` → `targets/`. La duplication liste/`choice` workflow persiste. |

### Workflows

| Fichier de `lifeos-ci-seed/` | Source | Décision / diff résumé |
| --- | --- | --- |
| `.github/workflows/_agent-run.yml` | `antenly-ci/.github/workflows/opencode-task.yml`, `galass-ci/.github/workflows/opencode-task.yml`, `galass-ci/.github/workflows/opencode-fullrun.yml`, `galass-ci/opencode/extra-repos.sh` | Réécrit en workflow réutilisable. Regroupe validation, checkout, prompt, opencode, quota, gitleaks, push, PR, notification. Perte de protections existantes : outils figés/root-owned, isolation git/hooks, `--redact`, merge-base/branche, refus `.github/workflows`, séparation job opencode/push, redaction journal (§2). |
| `.github/workflows/_next.yml` | `galass-ci/.github/workflows/opencode-fullrun.yml` (chaînage/dispatch) | Réécrit en table d’agents. Chaîne nominale correcte, arrêt sur `quota`. Défauts : `lifeos_write` passé avec `-f`, pas de `--ref`, condition acteur incomplète, `actions: write` large, pas de vérification `result == success` côté caller (§2.9, §2.10, §2.12, §2.14). |
| `.github/workflows/ci.yml` | `galass-ci/.github/workflows/ci.yml`, `antenly-ci/.github/workflows/ci-scripts.yml` | Adapté : tests + shellcheck + actionlint. `actionlint` non épinglé par SHA ; `opencode/tests/*.sh` non passés à shellcheck. |
| `.github/workflows/fr-plan-vera.yml` | `galass-ci/.github/workflows/opencode-task.yml` (dispatch) + `galass-ci/.github/workflows/opencode-fullrun.yml` (premier maillon) | Nouveau wrapper FullRun. `lifeos_write` déclaré booléen et transmis. Défaut : chaînage conditionné sur `needs.vera.outputs.status == 'ok'` seulement, pas `needs.vera.result == 'success'` (§2.10). |
| `.github/workflows/task.yml` | `antenly-ci/.github/workflows/opencode-task.yml`, `galass-ci/.github/workflows/opencode-task.yml` | Adapté en wrapper simple. `lifeos_write` a `default: false` (vérifié). Pas d’enchaînement. |

### Réutilisations existantes non exploitées

- **`galass-ci/opencode/extra-repos.sh`** : faisait déjà checkout/push/PR des dépôts supplémentaires avec protections importantes : git isolé sans hooks (`extra-repos.sh:82-99`), hook `pre-push` (`:188-189`), contrôle d’ancêtre/branche (`:219-224`), refus `.github/workflows` (`:245-249`), gitleaks avec config/ignore au SHA de base, copie nue et `--redact` (`:250-286`), push via copie nue/env isolé/`--no-verify` (`:293-346`). `_agent-run.yml` réimplémente partiellement ce flux et perd ces protections.
- **`galass-ci/opencode/allowed-repos.sh`** : liste blanche existante. Le changement de liste LordThiouk justifie une adaptation, pas une réécriture complète ni un déplacement imposé ; garder une source unique et éviter la duplication avec les `choice` workflow.
- **Porte gitleaks existante** : `antenly-ci/.github/workflows/opencode-task.yml:490-538` et `galass-ci/.github/workflows/opencode-task.yml:299-339` incluent `--redact`, contrôle branche, merge-base, refus `.github/workflows` et git sans hooks. `_agent-run.yml:437,474` utilise `gitleaks detect` sans ces garde-fous.
- **Notification** : `antenly-ci/.github/workflows/opencode-task.yml:540-566` et `galass-ci/.github/workflows/opencode-fullrun.yml:2145-2166` existaient déjà. La factorisation `notify.sh` est acceptable, mais doit garder le passage de clé par stdin (`-K -`) et ne pas s’exécuter depuis un checkout modifiable.
- **`antenly-ci/opencode/redact-log.sh`, `livelog.sh`, `leaklog.sh`, `wippush.sh`** : scripts existants. Le socle n’utilise pas `redact-log.sh` ; la sortie opencode est écrite brute dans `$RUNNER_TEMP/oc/run-*.log` (`_agent-run.yml:352-357`). Pas de publication actuelle observée, mais toute conservation/artefact futur devra redacter avant écriture/publication.

## 2. Défauts bloquants

### [x] 2.1. Critique — Scripts/outils du checkout `ci/` modifiables et exécutés après opencode

> Corrigé (commit `515d2d3`, test `opencode/tests/critical-frozen-tools-test.sh`) :
> copie root-owned `opencode/`, `targets/` et `models.txt` dans
> `/opt/lifeos-ci-tools` **avant** opencode (`_agent-run.yml`, step « Outils de
> confiance figés »), `chmod go-w /opt`, puis toutes les étapes post-opencode
> (garde-fou, quota, gitleaks, push, PR, notification) utilisent
> `$TOOLS_DIR/...` et jamais `ci/...`.

`_agent-run.yml:110-115` checkout `ci` en écriture ; `:303-325` autorise opencode à éditer `*` et `external_directory: *`; `:337-408` exécute opencode dans ce contexte. Ensuite `:361` exécute `ci/opencode/quota.sh`, `:436,473` exécutent `ci/opencode/lifeos-guard.sh`, `:515-517` exécute `ci/opencode/notify.sh`, et le push utilise `CI_TOKEN` (`:414`). `quota.sh` est aussi utilisé avant opencode (`:343`) mais la réexécution post-opencode est critique.

Impact : contournement du garde-fou `lifeos_write`, falsification du statut quota, exfiltration potentielle de `OC_NOTIFY_KEY`/`CI_TOKEN` via script modifié. C’est un contournement direct du garde-fou et un risque de fuite de secrets.

Correction suggérée : figer les outils avant opencode dans un répertoire root-owned hors workspace agent (modèle galass `install-hook-profile.sh`/`/opt/fullrun-tools` ou copie root-owned dans `$RUNNER_TEMP` avant opencode puis `chmod a-w`), invoquer par chemin absolu, et ne jamais exécuter un script provenant de `ci/` après le début d’opencode. Vérifier l’intégrité (SHA256) des scripts/outils avant usage.

### [x] 2.2. Critique — Hooks/filtres git des dépôts agent exécutés avec `CI_TOKEN`

> Corrigé (commit `515d2d3`, test `opencode/tests/critical-git-isolation-test.sh`) :
> push depuis une copie nue (`git init --bare` + fetch local), environnement
> `env -i`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`,
> `-c core.hooksPath=/dev/null`, `-c core.fsmonitor=false`, `--no-verify` ;
> le jeton n'est présent que dans l'environnement du push de la copie nue.
> Le test fonctionnel prouve qu'un `pre-push` et un `include.path` locaux ne
> s'exécutent pas.

`_agent-run.yml:426-441` et `:460-478` exécutent `git add/commit/push` directement dans `target/`, `extra/*` et `lifeos` avec `CI_TOKEN` en environnement (`:414`), sans `core.hooksPath=/dev/null`, sans `core.fsmonitor=false`, sans `--no-verify`, sans copie nue isolée. opencode peut modifier `.git/hooks/*`, `.git/config`, `.gitattributes` ou filtres.

Impact : exécution de code contrôlé par l’agent pendant une étape authentifiée, contournement des contrôles, fuite possible du jeton.

Correction suggérée : reprendre le modèle galass : copie nue fraîche, `env -i`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `-c core.hooksPath=/dev/null`, `-c core.fsmonitor=false`, `push --no-verify --porcelain` (`galass-ci/opencode/extra-repos.sh:82-99,293-346`; `galass-ci/.github/workflows/opencode-task.yml:310-339`). Interdire toute écriture dans `.git/`.

### [x] 2.3. Critique — État mutable post-opencode (`GITHUB_ENV`, `GITHUB_OUTPUT`, `$RUNNER_TEMP`, checkout `ci/`)

> Corrigé (commit `515d2d3`, test `opencode/tests/critical-state-isolation-test.sh`) :
> plus de `GITHUB_ENV` de sécurité ; `extra_repos` normalisé dans un output de
> step (valeur gérée par Actions), SHA de départ écrits en root dans
> `/opt/lifeos-ci-state`, opencode lancé avec `env -i` et un `HOME`/`TMPDIR`
> dédiés (aucun accès à `GITHUB_ENV`/`GITHUB_OUTPUT`/`GITHUB_PATH`/`$RUNNER_TEMP`),
> statut/modèle publiés par un step `id: oc` qui relit l'état root.

`_agent-run.yml:147` écrit `EXTRA_REPOS_NORM` dans `GITHUB_ENV`; `:406-407,497` écrivent des outputs ; les états sont dans `$RUNNER_TEMP/agent-repos.txt`, `agent-extra-base.txt`, `lifeos-base.txt` (`:176,187,220-226,419,460,462`). Après opencode, le job relit ces fichiers/valeurs et exécute des actions sensibles. opencode hérite aussi de variables d’environnement du runner et peut écrire dans les chemins accessibles.

Impact : falsification de `status/model/head_sha`, contournement de la logique de push/chaîne, modification de la liste des dépôts à pousser, potentielle réintroduction de `lifeos`/branche interdite si les contrôles sont relus depuis l’état mutable. Combiné à 2.1, permet de contourner le garde-fou.

Correction suggérée : séparer opencode et push/notify en jobs distincts. Le job push ne doit consommer que des inputs workflow immuables et des artefacts validés/recréés, jamais un script ou état modifiable par l’agent. Ne pas réutiliser `GITHUB_ENV` pour des valeurs de sécurité après opencode ; recalculer/valider depuis les inputs.

### 2.4. Élevée — Aucune vérification des modifications `.github/workflows` avant push

`_agent-run.yml:426-441` pousse `target/` et `extra/*` sans refuser `.github/workflows`; `:460-478` pousse `lifeos` sans ce contrôle. L’existant refuse : `antenly-ci/.github/workflows/opencode-task.yml:509-514`, `galass-ci/.github/workflows/opencode-task.yml:326-328`, `galass-ci/opencode/extra-repos.sh:245-249`.

Impact : un dépôt cible peut recevoir un workflow malveillant exécutable avec les secrets du dépôt cible lors d’un run futur.

Correction suggérée : avant chaque push, `git diff --name-only "$base..$h" -- .github/workflows` doit être vide ; sinon échec fermé. Si `lifeos-ci` doit être une exception explicite pour cette tâche, la documenter et la limiter strictement au dépôt/chemin prévu.

### 2.5. Élevée — Normalisation URL incomplète dans `lifeos-guard.sh`

`opencode/lifeos-guard.sh:19-32` retire seulement des préfixes exacts et `.git` final. Ne gère pas les identifiants dans l’URL (`https://token@github.com/...`), `www.github.com`, port, slash final après `.git`, query/fragment. `lg_check_destination` (`:101-118`) utilise `lg_is_lifeos` pour le refus `lifeos_write=false`.

Impact : contournement possible du garde-fou `destination` si une forme non normalisée est acceptée en entrée. Le risque est aggravé par 2.1/2.3.

Correction suggérée : parser l’URL avec un parseur strict (ou regex robuste) pour extraire hôte/chemin, supprimer credentials/port/query/fragment, normaliser `.git` et slashes, n’accepter que `github.com`, comparer `owner/repo` en minuscules. Ajouter tests : `https://x-access-token@github.com/LordThiouk/lifeos.git`, `https://www.github.com/LordThiouk/lifeos/`, `https://github.com/LordThiouk/lifeos.git/`, `.../lifeos?x=1`, `.../lifeos#x`.

### 2.6. Élevée — `lifeos_write=false` ne garantit pas une lecture seule réelle

`_agent-run.yml:210-213` applique `chmod -R a-w lifeos` puis `lifeos-guard.sh readonly`. `lifeos-guard.sh:121-129` vérifie seulement la présence de bits d’écriture à l’instant T. opencode est propriétaire du checkout et peut `chmod u+w`; il peut aussi modifier via scripts/étapes compromis (2.1).

Impact : le clone `lifeos/` peut redevenir modifiable pendant le run alors que `lifeos_write=false`.

Correction suggérée : exécuter opencode dans un sandbox sans accès écriture à `lifeos/`, ou monter/copier lifeos sous propriétaire distinct root:root en lecture seule (bind-mount ro / overlay / permissions système impossibles à lever par l’utilisateur runner). Revalider avant toute décision sensible ; ne jamais pousser `lifeos/` si `lifeos_write=false`.

### 2.7. Élevée — `lifeos` autorisé comme `target_repo`/`extra_repos` contourne le flux dédié

`targets/allowed-repos.sh:11` inclut `lifeos`. `lifeos-guard.sh:82-96` interdit `lifeos` seulement quand `lifeos_write=false`. Avec `lifeos_write=true`, `_agent-run.yml:154-162,164-189,426-441` clone/pousse `lifeos` comme dépôt cible ou extra vers `$IN_BRANCH`, pas vers `lifeos-ci/<job_name>` ni via la PR brouillon dédiée (`:460-494`). `allowed-repos.sh` n’interdit pas non plus `target_repo` répété dans `extra_repos`.

Impact : écritures/push sur `lifeos` hors branche dédiée prévue, contournement de la règle “branche + PR brouillon” spécifique lifeos.

Correction suggérée : refuser `lifeos` dans `target_repo` et `extra_repos` (ou le traiter uniquement via le canal `lifeos/` dédié). Ajouter contrôle `target_repo ∉ extra_repos`. Ajouter tests.

### 2.8. Élevée — Porte gitleaks incomplète

`_agent-run.yml:437,474` : `gitleaks detect --source "$dir" --log-opts="$base..$h" --no-banner >/dev/null` (pas de `--redact`, pas de config/ignore au SHA de base, pas de copie nue, pas de contrôle merge-base/branche, pas d’isolation git, dépend du PATH). Comparer aux existants : `antenly-ci/.github/workflows/opencode-task.yml:509-516`, `galass-ci/opencode/extra-repos.sh:250-286`, `galass-ci/.github/workflows/opencode-task.yml:321-339`.

Impact : contrôle contournable ou fragile ; fuite possible d’indices sensibles en cas de changement de comportement/logs ; faux négatifs via config/ignore contrôlés par l’agent si jamais utilisés.

Correction suggérée : porte gitleaks en copie nue, binaire root-owned à chemin absolu, `--redact`, config/ignore extraits du SHA de base, `merge-base --is-ancestor`, vérification HEAD/branche inchangée, refus `.github/workflows`, échec fermé.

### 2.9. Élevée — `_next.yml` passe `lifeos_write` en `-f` et omet `--ref`

`_next.yml:127-136` : `gh workflow run "$next_wf" --repo "$GITHUB_REPOSITORY" ... -f lifeos_write="$LIFEOS_WRITE" ...` sans `--ref`. Les inputs appelés déclarent `lifeos_write` en `type: boolean` (`fr-plan-vera.yml:28-32`, `task.yml:28-32`). `gh workflow run` utilise `-F` pour les valeurs typées/booléennes JSON.

Impact : perte/mauvais typage de `lifeos_write` au maillon suivant ; dispatch sur la branche par défaut au lieu de la branche courante, pouvant exécuter un workflow différent de celui de la chaîne.

Correction suggérée : utiliser `-F lifeos_write="$LIFEOS_WRITE"` (ou `-F lifeos_write=${LIFEOS_WRITE}`) et ajouter `--ref "${GITHUB_REF_NAME}"` (ou la ref de chaîne explicitement validée). Tester avec un faux `gh` qui capture les args.

### 2.10. Élevée — Chaînage conditionné au seul output `status`, pas au résultat réel du job

`fr-plan-vera.yml:80-82` : `needs.vera.outputs.status == 'ok'` sans `needs.vera.result == 'success'`. `_next.yml:93-100` s’arrête sur statut non `ok`, ce qui est bien, mais il fait confiance au statut transmis. Le statut est produit par l’étape opencode (`_agent-run.yml:406-407`) et peut être influencé par l’état mutable (2.3) ; un job peut aussi écrire `status=ok` puis échouer ensuite.

Impact : chaînage possible après échec réel/push échoué ou sur statut falsifié. Risque de perte de contrôle de la chaîne.

Correction suggérée : conditionner le chaînage à `needs.<job>.result == 'success' && needs.<job>.outputs.status == 'ok'`; dans `_next`, refuser tout statut non explicitement autorisé et, idéalement, vérifier une preuve non modifiable par l’agent (artefact signé/attestation du job push séparé).

### 2.11. Moyenne — Détection quota sujette aux faux positifs

`opencode/quota.sh:81-99` ignore les lignes commençant par `+`, `-`, `@@` et le contenu dans fences ```/~~~. Elle ne traite pas les lignes de contexte diff (préfixe espace), les en-têtes diff (`diff --git`, `index`, `---`, `+++`), ni le code indenté hors fence. `q_line_is_error` (`:59-76`) peut matcher de la prose contenant `error` + `quota/exceeded/insufficient`.

Impact : bascule/quota erroné, arrêt de chaîne ou comportement non déterministe sur du contenu de dépôt.

Correction suggérée : ignorer lignes de diff unifiées complètes (contexte inclus), en-têtes diff, et blocs indentés; restreindre la détection aux motifs fournisseur structurés dans logs/sortie outil (codes HTTP 429, `rate_limit`, `FreeUsageLimitError`, `AI_APICallError`, `insufficient_quota`, `usage limit`) avec ancrage/contextes attendus. Ajouter tests de faux positifs.

### 2.12. Moyenne — Condition acteur incomplète

`_agent-run.yml:85` et `_next.yml:70` ne testent que `github.actor == 'LordThiouk'`. Les workflows galass testent aussi `github.triggering_actor` (`galass-ci/.github/workflows/opencode-task.yml:161`, `galass-ci/.github/workflows/opencode-fullrun.yml:161`).

Impact : un re-run/déclenchement avec acteur déclencheur différent peut être accepté selon le contexte GitHub.

Correction suggérée : exiger `github.actor == 'LordThiouk' && github.triggering_actor == 'LordThiouk'`.

### 2.13. Moyenne — Notification : clé en argument `curl`, pas de `set +x`, script modifiable

`opencode/notify.sh:44-48` passe la clé dans des headers en arguments de commande. Pas de `set +x` (`:6`). `_agent-run.yml:503-517` exécute le script depuis `ci/` modifiable avec `OC_NOTIFY_KEY` en env.

Impact : exposition potentielle de la clé via `ps`/traces; exfiltration triviale si script modifié (2.1).

Correction suggérée : `set +x`; passer headers/URL via stdin `curl -K -` (modèle `galass-ci/.github/workflows/opencode-fullrun.yml:2145-2166`); exécuter un script figé root-owned ou inline dans une étape non modifiable.

### 2.14. Moyenne — Permission `actions: write` inutilement large dans `_next.yml`

`_next.yml:73-75` donne `actions: write` au job, mais le dispatch utilise `GH_TOKEN: ${{ secrets.CI_TOKEN }}` (`:79`). Le caller `fr-plan-vera.yml` ne déclare pas cette permission.

Impact : surface de permission plus large que nécessaire côté `GITHUB_TOKEN`.

Correction suggérée : retirer `actions: write` si `CI_TOKEN` suffit; sinon utiliser `GITHUB_TOKEN` et limiter `CI_TOKEN`. Documenter le scope minimal du PAT.

## 3. Défauts non bloquants

1. `_agent-run.yml:426-441` ne vérifie pas que le HEAD est encore sur `$IN_BRANCH` ni `merge-base --is-ancestor $base $h` avant push. Le push non forcé limite certains cas, mais le contrôle explicite existe dans `galass-ci/.github/workflows/opencode-task.yml:310-323`.
2. `_agent-run.yml:352-357` écrit la sortie opencode brute dans `$RUNNER_TEMP/oc/run-*.log` sans redaction. Pas de publication observée, mais réutiliser `antenly-ci/opencode/redact-log.sh` avant toute conservation/artefact.
3. `_agent-run.yml:397-398` considère `/tmp/task_done.md` comme signal de succès même si aucun commit. Sur runner persistant/compromis, un fichier préexistant peut fausser le statut. Supprimer `/tmp/task_done.md` avant run et n’accepter qu’un fichier créé pendant la tentative courante.
4. `targets/allowed-repos.sh:44-58` refuse les doublons extra mais pas `target_repo` présent dans `extra_repos`. Ajouter le contrôle.
5. `ci.yml:38-53` télécharge actionlint sans vérification SHA256/pinning fort; `shellcheck` ne cible pas `opencode/tests/*.sh`.
6. Les workflows `fr-*.yml` annoncés par `_next.yml` sont absents sauf `fr-plan-vera.yml` : la chaîne s’arrête après Vera. Comportement à documenter clairement comme socle partiel.

## 4. Vérifications positives

- `task.yml:28-32` et `fr-plan-vera.yml:28-32` déclarent `lifeos_write` en `boolean` avec `default: false`.
- `fr-plan-vera.yml:66,90` transmet `lifeos_write` à `_agent-run.yml` et `_next.yml`; `_next.yml:130` transmet la valeur (problème de typage `-f`, pas omission).
- Bascule quota unique dans `_agent-run.yml:349-379` (`switched`), arrêt `quota` sur deuxième bascule/code 20. `quota.sh` valide uniquement `opencode/*-free`.
- `_next.yml:93-100` ne chaîne pas sur `quota` (statut nominal).
- Concurrence par dépôt cible : `_agent-run.yml:90-92`, `group: agent-${{ inputs.target_repo }}`, `cancel-in-progress: false`.
- Aucun secret passé dans l’étape opencode (`_agent-run.yml:337-408` n’expose pas `CI_TOKEN`/`OC_NOTIFY_KEY`). Les remotes target/extra sont checkouts avec `persist-credentials: false`; push lifeos/target utilise `GIT_ASKPASS`.
- Aucun secret observé en dur dans les fichiers seed revus; `::add-mask::` utilisé pour l’en-tête base64 (`_agent-run.yml:170-171,200-201`).

## Verdict

VERDICT: À CORRIGER

Corrections obligatoires :
1. Figer les outils (`quota.sh`, `lifeos-guard.sh`, `notify.sh`, `gitleaks`) hors portée d’opencode et les exécuter par chemin absolu ; ne jamais exécuter un script du checkout `ci/` après opencode (§2.1).
2. Isoler git pour tout push/commit post-agent : copie nue, `env -i`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `core.hooksPath=/dev/null`, `core.fsmonitor=false`, `--no-verify`, aucun hook/filtre du workspace agent (§2.2).
3. Séparer job opencode et job push/notify ; ne pas faire confiance à `GITHUB_ENV`, `GITHUB_OUTPUT` post-opencode, ni à `$RUNNER_TEMP` modifiable par l’agent ; revalider les inputs immuables (§2.3).
4. Refuser toute modification de `.github/workflows` avant push (sauf exception explicitement documentée et contrôlée) (§2.4).
5. Durcir `lifeos-guard.sh` : normalisation stricte URL (credentials, `www`, port, query/fragment, slash, `.git`), tests de contournement (§2.5).
6. Rendre la lecture seule de `lifeos/` réellement non contournable quand `lifeos_write=false` (sandbox/propriétaire root/mount ro) et revalider avant décision (§2.6).
7. Interdire `lifeos` en `target_repo`/`extra_repos` ou le router exclusivement vers le flux dédié `lifeos-ci/<job_name>` avec PR brouillon ; refuser `target_repo` dupliqué en `extra_repos` (§2.7).
8. Reprendre la porte gitleaks existante : `--redact`, config/ignore au SHA de base, copie nue, binaire absolu, merge-base/branche, échec fermé (§2.8).
9. Dans `_next.yml`, passer `lifeos_write` avec `-F` typé et ajouter `--ref "${GITHUB_REF_NAME}"` (ou ref de chaîne validée) (§2.9).
10. Conditionner le chaînage à `needs.vera.result == 'success'` et à un statut `ok` fiable/non falsifiable ; ne jamais chaîner sur échec (§2.10).
11. Durcir `quota.sh` contre faux positifs diff/contexte/code indenté/prose et ajouter tests de non-régression (§2.11).
12. Ajouter `github.triggering_actor == 'LordThiouk'` aux conditions d’acteur (§2.12).
13. Notification : `set +x`, clé/headers via stdin `curl -K -`, script figé ou inline ; ne pas exécuter depuis `ci/` modifiable (§2.13).
14. Réduire `actions: write` dans `_next.yml` au strict nécessaire ou aligner sur le jeton réellement utilisé (§2.14).
