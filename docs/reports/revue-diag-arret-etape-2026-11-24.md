# Revue — un job FullRun s'arrête à l'étape demandée (24/11/2026)

## Objet

Revue de la branche `fix/diag-arret-etape-2026-11-24` (commits `7936c4f`, `f932b62`) contre
`origin/main`, sur le diagnostic `docs/reports/diag-arret-etape-2026-11-24.md`, le wrapper
`opencode/run-fullrun.sh`, le mapping `opencode/step-agents.sh`, le workflow
`.github/workflows/opencode-fullrun.yml` et le test `opencode/tests/stop-after-step-test.sh`.

Verdict : À CORRIGER

## Problèmes

### 1. Bloquant — le validateur d'un job borné impose un seul agent fixe, contraire à la règle du pipeline

- Fichiers/lignes :
  - `opencode/step-agents.sh:24-25` (`build` → `Forge`, `verify` → `Silas`)
  - `.github/workflows/opencode-fullrun.yml:655-666` (calcul de `OC_DONE_AGENTS_EFFECTIVE`)
  - `.github/workflows/opencode-fullrun.yml:671-682` (consigne de prompt)
  - `README.md:338-341`
  - `opencode/tests/stop-after-step-test.sh:37-40,105-106` (attentes de test qui figent le mapping)
- Gravité : **bloquant**.

La règle de `FullRunPipeline.ts` est : étape 4 `build` → `Designer`/`Aditi` (UI) **ou**
`Engineer`/`Forge`/`Anvil` (logique) ; étape 5 `verify` → `code-reviewer`, `Forge` **ou** `Silas`.
Le mapping ne retient que `Forge` et `Silas` et, dans le workflow, `OC_STOP_AFTER_STEP` est évalué
**avant** `OC_TARGET_AGENT` (lignes 657-662). Conséquences concrètes :

- `stop_after_step=build` + `target_agent=Designer` (ou `Anvil`, `Engineer`) : l'agent dispatché est
  `Designer`, mais `done_check` exige un PASS de `Forge`, jamais lancé. Sans reprise sur job borné
  (`run-fullrun.sh:750-756`), le job finit en `127` / `a:none:Forge` alors que le travail est
  légitime.
- `stop_after_step=verify` + `target_agent=code-reviewer` (ou `Forge`) : même blocage, avec un
  `a:none:Silas`. C'est précisément le scénario `next=code-reviewer` documenté dans
  `README.md:427,454`.
- La consigne de prompt devient contradictoire : la ligne 678 dit de dispatcher `OC_TARGET_AGENT`,
  la ligne 679 exige le PASS de l'agent fixe de `stop_after_step`.

Attendu : le validateur effectif doit suivre l'agent réellement imposé (`target_agent` prioritaire)
ou accepter l'ensemble des agents autorisés pour l'étape (liste séparée par des virgules), et le
prompt doit nommer le même agent que celui qui est dispatché.

### 2. Moyen — régression de la suite existante `first-link-prompt-test.sh`

- Fichiers/lignes :
  - `.github/workflows/opencode-fullrun.yml:666` (`echo ... >> "$GITHUB_ENV"` dans `prep`)
  - `opencode/tests/first-link-prompt-test.sh:22,86-99` (prep extrait et lancé sous `env -i` sans
    `GITHUB_ENV`, avec `set -euo pipefail`)
- Gravité : **moyen** (qualité de test ; pas d'impact produit direct en GitHub Actions, où
  `GITHUB_ENV` existe toujours).

Le nouveau bloc de `prep` écrit dans `$GITHUB_ENV`. Or `first-link-prompt-test.sh` exécute le vrai
`prep` sous `env -i` sans fournir `GITHUB_ENV` ; le script s'arrête alors sur
`prep.sh: line 73: GITHUB_ENV: unbound variable`. La suite affiche malgré tout `OK` quand `rg` est
présent, car elle ne contrôle pas le code retour et le prompt a été écrit avant le bloc fautif :
l'erreur est masquée et la fin de `prep` n'est plus réellement exercée. Le rapport de diagnostic
annonce pourtant cette suite comme passante.

### 3. Faible — rapport de diagnostic obsolète et test de patch neutralisé

- Fichiers/lignes :
  - `docs/reports/diag-arret-etape-2026-11-24.md:53-56,103`
  - `opencode/tests/stop-after-step-test.sh:52-58`
- Gravité : **faible**.

Le rapport affirme que le workflow n'est pas modifié dans l'arbre et que le patch doit encore être
appliqué, alors que le commit `f932b62` l'a appliqué (`.github/workflows/opencode-fullrun.yml` est
bien modifié sur la branche). De même, le test ne vérifie plus `git apply` : il détecte les
marqueurs déjà présents et se contente du repli. Le patch s'applique néanmoins encore sur
`origin/main` (vérifié par `git apply --check`), donc pas de problème fonctionnel.

### 4. Faible — changement de comportement hors job borné avec `target_agent`

- Fichiers/lignes : `.github/workflows/opencode-fullrun.yml:655-664`, `README.md:338-341`
- Gravité : **faible**.

Un job non borné (`chain_enabled=false`, sans `stop_after_step`) qui renseigne `target_agent` mais
laisse `done_agents` vide exige désormais le PASS de `target_agent` au lieu de `Max` (ancien défaut).
C'est documenté, mais c'est un changement au-delà du périmètre « job borné » ; à confirmer comme
voulu.

### 5. Faible — `set -u` global dans un script présenté comme sourçable

- Fichier/ligne : `opencode/step-agents.sh:14`
- Gravité : **faible**.

Le script est documenté comme sourçable ; le sourcing active `set -u` dans le shell appelant. Aucun
appel sourcé n'existe aujourd'hui (le workflow et les tests l'exécutent via `bash`), donc pas
d'impact actuel.

## Points vérifiés

- Arrêt d'un job borné : `opencode/run-fullrun.sh:88-95,750-756,812` désactive bien toute reprise
  quand `OC_STOP_AFTER_STEP` est posé ; sans PASS, sortie `127` / `arret=tour-fini` /
  `stop_after_no_resume=<étape>`.
- Consigne de prompt « Étape finale imposée » présente (`...:671-682`) et l'agent effectif est
  consommé par le préflight (`...:725`), le step `oc` (`...:1099`), le validateur final
  (`...:1506`) et le dispatch du chaînage (`...:1946`).
- Chaînage `chain_enabled=true` : `chain-step-test.sh` passe ; le dispatch transmet toujours une
  valeur non vide (`Max` par défaut hors job borné).
- Aucun secret introduit : `step-agents.sh` et les blocs ajoutés ne lisent ni n'exposent de secret ;
  aucune nouvelle variable sensible.
- `git apply --check docs/patches/diag-arret-etape-2026-11-24.patch` sur le workflow de
  `origin/main` : code 0.
- `bash -n` sur `run-fullrun.sh`, `step-agents.sh` et `stop-after-step-test.sh` : OK.

## Tests exécutés (environnement local, 24/11/2026)

- `bash opencode/tests/stop-after-step-test.sh` : **23 OK, 0 KO**.
- `bash opencode/tests/chain-step-test.sh` : OK.
- `bash opencode/tests/start-step-test.sh` : 13 OK.
- `bash opencode/tests/turn-end-test.sh` : 6 OK.
- `bash opencode/tests/prompt-contract-test.sh` : 5 OK.
- `bash opencode/tests/first-link-prompt-test.sh` : échoue d'abord faute de `rg` dans
  l'environnement ; avec un shim `rg` minimal, la suite affiche OK mais `prep` s'arrête sur
  `GITHUB_ENV: unbound variable` (problème 2).
- `bash opencode/tests/preflight-test.sh` : 24 OK, 1 KO avec le shim `rg` (limite du shim, pas du
  correctif) ; `rg` absent et `bun` absent dans l'environnement local.
