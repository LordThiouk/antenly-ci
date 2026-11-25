# REPORT — amorçage du socle `LordThiouk/lifeos-ci`

Date : 2026-11-24. Branche : `seed/lifeos-ci-2026-11-24` (dépôt `antenly-ci`).
Tout le contenu ci-dessous est destiné à être copié tel quel à la racine de
`lifeos-ci` (le dossier `lifeos-ci-seed/` disparaît).

## Fichiers repris et destinations

| Source | Destination dans `lifeos-ci-seed/` | Décision |
| --- | --- | --- |
| `galass-ci/opencode/allowed-repos.sh` | `targets/allowed-repos.sh` | Repris et étendu à la liste blanche LordThiouk (9 dépôts), validation stricte (`^[A-Za-z0-9._-]+$`, pas de `..`), CLI `list/check/validate`, normalisation des `extra_repos` (virgules et espaces, doublons refusés). |
| `antenly-ci/opencode/run-fullrun.sh` (gestion 429 / `FreeUsageLimitError`) + `opencode-task.yml` (`model_main` / `model_chain`) | `opencode/quota.sh` + `models.txt` | Détection unifiée : journal interne + lignes d'erreur réelles uniquement ; diffs et blocs de code ignorés ; une seule bascule dans `_agent-run.yml`. Liste des modèles reprise de l'ordre actuel d'antenly-ci. |
| `antenly-ci/.github/workflows/opencode-task.yml` (notification de fin) | `opencode/notify.sh` | Extrait en script unique, JSON `jq`, en-têtes `Authorization` + `X-Automation-Key`, `--max-time 15`, jamais bloquant. |
| `galass-ci/opencode/extra-repos.sh` (mode `target_repo` / `extra_repos`) | `.github/workflows/_agent-run.yml` | Le mode de sélection et le checkout des dépôts supplémentaires sont intégrés au workflow réutilisable ; la validation reste centralisée dans `targets/allowed-repos.sh`. |
| `antenly-ci/.github/workflows/opencode-task.yml` (validation, checkout, installation opencode 1.19.4, gitleaks, push fast-forward) | `.github/workflows/_agent-run.yml` | Logique commune factorisée une seule fois ; ajout du clone lifeos lecture seule, du garde-fou, des PR brouillon et des sorties `status`/`model`/`head_sha`. |
| `galass-ci/.github/workflows/opencode-task.yml` + `opencode-fullrun.yml` (inputs et liste blanche) | `.github/workflows/task.yml`, `fr-plan-vera.yml`, `_next.yml` | `target_repo` en `choice` aligné sur la liste blanche ; `extra_repos`, `lifeos_write`, `branch`, `prompt_path`, `isa_path`, `job_name`, `lifeos_ref`, `timeout_minutes`. |
| `galass-ci/.github/workflows/ci.yml` + `antenly-ci/.github/workflows/ci-scripts.yml` | `.github/workflows/ci.yml` | Tests shell + `shellcheck` + `actionlint` épinglé. |
| (nouveau) | `opencode/lifeos-guard.sh` | Garde-fou `lifeos_write` (destination, lecture seule, main/master). |
| (nouveau) | `opencode/tests/*.sh` | Tests sans réseau ni secret ; `run-all.sh` renvoie un code non nul si un test échoue. |
| `antenly-ci` chaîne de modèles par défaut | `models.txt` | Une seule copie, ordre de priorité conservé, uniquement des `opencode/*-free`. |
| (nouveau) | `README.md` | Rôle, modes, inputs, règles `lifeos_write`, quota. |

## Décisions de fusion

- Une seule liste blanche, dans `targets/allowed-repos.sh` : les options
  `target_repo` des workflows publics sont alignées dessus et un test le vérifie.
- Aucun script dupliqué : `_agent-run.yml` porte la logique commune ; `task.yml`
  et `fr-plan-vera.yml` ne font que transmettre les inputs.
- `lifeos_write=false` est le défaut ; lifeos est cloné en lecture seule et le
  remote est remis à une URL sans identifiants. `lifeos_write=true` n'autorise
  qu'une branche de fonctionnalité (jamais `main`/`master`).
- Quota : une seule bascule par run. Si le modèle de secours est aussi épuisé,
  le statut devient `quota` et `_next.yml` ne déclenche aucun lien.
- Enchaînement : `vera → serena → engineer → anvil → forge-code → aditi-ui →
  forge-audit → silas → code-review → max`. Le lien suivant n'est lancé que si le
  statut est `ok` et que le fichier `fr-<phase>-<agent>.yml` existe.
- `actionlint` a été lancé depuis une copie du dossier à la racine du futur dépôt
  (le dossier `lifeos-ci-seed/` est imbriqué dans `antenly-ci`, ce qui fausse la
  résolution des `uses: ./.github/workflows/...`). Dans le futur dépôt, la commande
  exacte est `actionlint .github/workflows/*.yml`.

## Sorties brutes

### `bash opencode/tests/run-all.sh`

```text
$ bash opencode/tests/run-all.sh
==> allowed-repos-test.sh
PASS allowed-repos-test : 28 cas
<== ok allowed-repos-test.sh
==> lifeos-guard-test.sh
PASS lifeos-guard-test : 23 cas
<== ok lifeos-guard-test.sh
==> quota-test.sh
PASS quota-test : 8 cas
<== ok quota-test.sh
PASS : 3 suite(s) de tests
exit=0
```

### `shellcheck` (version 0.11.0)

```text
$ shellcheck -x opencode/*.sh targets/*.sh
exit=0
```

### `actionlint` (version 1.7.7)

```text
$ actionlint .github/workflows/*.yml   # depuis une copie à la racine du futur dépôt
exit=0
```

## Contrôles complémentaires

- Aucun secret, aucune fausse clé ; aucune référence à `antenly-ci` comme dépôt
  d'exécution (il ne reste que l'option de cible et la liste blanche).
- Aucun fichier modifié hors de `lifeos-ci-seed/`.
- Scripts exécutables (`chmod +x`) et en `set -euo pipefail`.

## Fix1 (2026-11-25)

Correctifs du socle : notification qui remonte le code HTTP (sans avaler l'erreur),
transmission complète de `lifeos_write` dans la chaîne FullRun, et écriture LifeOS
sur une branche dédiée poussée par le workflow puis ouverte en PR brouillon.

### `bash opencode/tests/run-all.sh`

```text
$ bash opencode/tests/run-all.sh
==> allowed-repos-test.sh
PASS allowed-repos-test : 28 cas
<== ok allowed-repos-test.sh
==> lifeos-chain-test.sh
PASS lifeos-chain-test : 23 cas
<== ok lifeos-chain-test.sh
==> lifeos-guard-test.sh
PASS lifeos-guard-test : 23 cas
<== ok lifeos-guard-test.sh
==> notify-test.sh
PASS notify-test : 21 cas
<== ok notify-test.sh
==> quota-test.sh
PASS quota-test : 8 cas
<== ok quota-test.sh
PASS : 5 suite(s) de tests
exit=0
```

### `shellcheck` (version 0.11.0)

```text
$ shellcheck -x opencode/*.sh targets/*.sh opencode/tests/*.sh
exit=0
```

### `actionlint` (version 1.7.7)

```text
$ actionlint .github/workflows/*.yml   # depuis une copie à la racine du futur dépôt
exit=0
```
