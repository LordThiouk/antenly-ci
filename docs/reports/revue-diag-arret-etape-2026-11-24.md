# Revue — un job FullRun s'arrête à l'étape demandée (24/11/2026)

## Objet

Revue de la branche `fix/diag-arret-etape-2026-11-24` (HEAD `1790416`) contre `origin/main`
(`5647624`), sur le diagnostic `docs/reports/diag-arret-etape-2026-11-24.md`, le wrapper
`opencode/run-fullrun.sh`, le mapping `opencode/step-agents.sh`, le validateur
`opencode/done_check.sh`, le workflow `.github/workflows/opencode-fullrun.yml` et les tests
`opencode/tests/stop-after-step-test.sh`, `first-link-prompt-test.sh`, `done-check-test.sh`.
Cette revue remplace la précédente (commits `7936c4f`, `f932b62`) : les correctifs `e2661ea`
(agent réellement dispatché, listes d'agents, mode ANY) et `1790416` (application du patch
`fix-pr52`) sont désormais dans le HEAD.

Verdict : À CORRIGER

## Problèmes

### 1. Bloquant — `stop-after-step-test.sh` échoue sur le HEAD (patch déjà appliqué)

- Fichiers/lignes :
  - `opencode/tests/stop-after-step-test.sh:54-62` (applique `fix-pr52` sur le workflow de HEAD)
  - `docs/patches/fix-pr52-2026-11-24.patch` (contenu déjà présent dans HEAD)
  - `.github/workflows/opencode-fullrun.yml:68-71,651-696` (version déjà patchée)
- Gravité : **bloquant**.

Le commit `1790416` a appliqué `docs/patches/fix-pr52-2026-11-24.patch` au workflow. Le test
extrait ensuite le workflow de HEAD puis exécute `git apply` de ce même patch : il échoue
forcément (`patch does not apply`). Exécution réelle sur HEAD :

```
FAIL patch incrémental : git apply impossible (error: patch failed: .github/workflows/opencode-fullrun.yml:68 ...)
```

soit **37 OK, 1 FAIL, exit 1**. Le test ne peut plus être vert tant que la cible du patch reste
HEAD. Le patch ne s'applique d'ailleurs plus ni sur HEAD ni seul sur `origin/main` ; il ne
s'applique qu'après `docs/patches/diag-arret-etape-2026-11-24.patch`. `.github/workflows/ci-scripts.yml:76`
exécute tous les `opencode/tests/*-test.sh` et `stop-after-step-test.sh` n'est pas dans
`OC_CI_KNOWN_FAILING` : la CI du PR échouera.

Attendu : appliquer la séquence de patches sur `origin/main`, ou tester directement le workflow de
HEAD (déjà patché), ou supprimer le patch devenu redondant.

### 2. Moyen — `stop_after_step` + `chain_enabled=true` dispatche quand même le lien suivant

- Fichiers/lignes :
  - `.github/workflows/opencode-fullrun.yml:1760-1763` (le step de chaînage ne teste que `chain_enabled`)
  - `.github/workflows/opencode-fullrun.yml:1937-1951` (calcule la phase suivante)
  - `.github/workflows/opencode-fullrun.yml:1952-1968` (dispatch du lien suivant)
  - `.github/workflows/opencode-fullrun.yml:261-271` (aucune exclusion mutuelle dans la garde)
  - `opencode/run-fullrun.sh:751-757` (seule la reprise du wrapper est désactivée)
- Gravité : **moyen**.

Le contrat de l'input `stop_after_step` (`.github/workflows/opencode-fullrun.yml:34-37`) est
« s'arrête après cette étape sans dispatcher la suite ». Or, quand `chain_enabled=true`, le step
« Décision de chaînage » ne lit jamais `OC_STOP_AFTER_STEP` : après un `OC_STOP=ok` il appelle
`unit --isa` puis `gh workflow run` pour le lien suivant. La garde n'interdit pas non plus de
combiner les deux inputs. `run-fullrun.sh` empêche bien la reprise *dans le job*, mais pas ce
redispatch au niveau workflow. Un job borné lancé par erreur en mode chaîné continuerait donc le
pipeline.

Attendu : soit refuser `stop_after_step` avec `chain_enabled=true` dans la garde, soit faire
`finish_chain`/`stop_chain` dans le step de chaînage dès que `OC_STOP_AFTER_STEP` est posé.

### 3. Faible — rapport de diagnostic obsolète (patch et tests annoncés à tort)

- Fichiers/lignes :
  - `docs/reports/diag-arret-etape-2026-11-24.md:53-57` (« patch incrémental applicable sur le HEAD »)
  - `docs/reports/diag-arret-etape-2026-11-24.md:87` (« 39 OK, 0 KO »)
  - `docs/reports/diag-arret-etape-2026-11-24.md:94` (`git apply --check` sur HEAD « OK »)
  - `opencode/tests/stop-after-step-test.sh:6-8` (commentaire « l'applique sur la version de HEAD »)
- Gravité : **faible**.

À HEAD, le patch `fix-pr52` est déjà appliqué : `git apply --check` renvoie 1 sur HEAD et le test
donne 37 OK / 1 FAIL, pas 39 OK / 0 KO. Le rapport décrit donc un état qui n'est plus celui de la
branche ; il induit en erreur sur la validité des vérifications annoncées.

### 4. Faible — changement hors job borné quand `target_agent` est fourni

- Fichiers/lignes :
  - `.github/workflows/opencode-fullrun.yml:656-667` (`target_agent` prioritaire même sans `stop_after_step`)
  - `.github/workflows/opencode-fullrun.yml:1111,1960`
  - `README.md:338-341`
  - `opencode/tests/stop-after-step-test.sh:129`
- Gravité : **faible**.

Un run non borné (`chain_enabled=false`, sans `stop_after_step`) qui renseigne `target_agent` et
laisse `done_agents` vide exige désormais le PASS de `target_agent` au lieu de `Max` (ancien
défaut). C'est documenté et probablement voulu, mais c'est un changement au-delà du périmètre
« job borné » : la demande de revue exige que le chaînage manuel (`chain_enabled=false`) reste
inchangé. Sans `target_agent`, le comportement reste bien `Max`.

### 5. Faible — l'accesseur mono-agent du mapping reste plus étroit que la règle du pipeline

- Fichier/ligne : `opencode/step-agents.sh:19-32`
- Gravité : **faible**.

`fullrun_step_agent` (mode sans `--list`) renvoie toujours `Forge` pour `build` et `Silas` pour
`verify`, alors que la règle de `FullRunPipeline.ts` autorise aussi `Designer`/`Aditi`/`Engineer`/
`Anvil` (build) et `code-reviewer`/`Forge` (verify). Aucun appelant actuel n'utilise ce mode pour
valider (le workflow et les tests passent par `--list`), donc pas d'impact immédiat ; c'est un
piège pour un futur appelant qui prendrait le mode par défaut pour le validateur.

## Points vérifiés

- **Arrêt d'un job borné** : `opencode/run-fullrun.sh:91-95,751-757,813` désactive toute reprise
  quand `OC_STOP_AFTER_STEP` est posé ; sans PASS, sortie `127` / `arret=tour-fini` /
  `stop_after_no_resume=<étape>`. Les deux scénarios bout en bout du test (PASS → arrêt immédiat ;
  pas de PASS → un seul tour, aucune reprise) passent.
- **Mapping par étape conforme à la règle de Papa** : `opencode/step-agents.sh:34-45` couvre
  vera → `Algorithm`, serena → `Architect`, build → `Designer,Aditi,Engineer,Forge,Anvil`,
  verify → `code-reviewer,Forge,Silas`, max/close → `Max`. Le workflow utilise bien `--list` pour
  un job borné (`.github/workflows/opencode-fullrun.yml:662,681`) : un seul agent fixe ne bloque
  plus un job légitime.
- **`target_agent` prioritaire** : l'agent réellement dispatché est exigé seul
  (`.github/workflows/opencode-fullrun.yml:659-660`) ; la consigne de prompt nomme le même agent
  (`...:676-693`). Cas `Designer`, `Anvil`, `code-reviewer` couverts par le test.
- **Mode ANY** : `opencode/done_check.sh:271-302,304-330` exige qu'un même agent satisfasse a et b ;
  les tests `12h` à `12l` de `done-check-test.sh` encodent ce comportement (non exécutables ici,
  `bun` absent).
- **`first-link-prompt-test.sh`** : le `GITHUB_ENV` manquant est corrigé
  (`opencode/tests/first-link-prompt-test.sh:90-91`) et le code retour de `prep` est contrôlé.
- **Pas de secret** : aucun secret ni valeur sensible introduits dans `step-agents.sh`, les blocs
  ajoutés du workflow, `done_check.sh`, `run-fullrun.sh` ou les tests.
- **`bash -n`** : OK sur `run-fullrun.sh`, `step-agents.sh`, `done_check.sh`,
  `stop-after-step-test.sh` et tous les blocs `run` du workflow.

## Risque résiduel (non bloquant)

En mode ANY, le validateur accepte le PASS de n'importe quel agent autorisé de l'étape
(`opencode/done_check.sh:271-287`), pas nécessairement celui réellement dispatché. Le prompt parle
pourtant de « celui de l'agent dispatché ». Les garde-fous `postérieur au dernier commit de code` +
`hooks.log` limitent le risque, mais un PASS valide d'un autre agent autorisé pourrait suffire si
l'agent dispatché n'a pas rendu de verdict. À garder en tête ; ce n'est pas un blocage.

## Tests exécutés (environnement local, 24/11/2026)

- `bash opencode/tests/stop-after-step-test.sh` : **37 OK, 1 FAIL, exit 1** — problème 1.
- `bash opencode/tests/chain-step-test.sh` : OK, exit 0.
- `bash opencode/tests/start-step-test.sh` : OK, exit 0.
- `bash opencode/tests/turn-end-test.sh` : OK, exit 0.
- `bash opencode/tests/prompt-contract-test.sh` : OK, exit 0.
- `bash opencode/tests/first-link-prompt-test.sh` : échoue localement faute de `rg` (limite
  d'environnement ; la CI installe ripgrep).
- `bash opencode/tests/preflight-test.sh` : échoue localement faute de `rg` et de CLI lifeos
  (limites d'environnement).
- `bash opencode/tests/done-check-test.sh` : non exécutable localement (`bun` absent ; présent en
  CI).
- `git apply --check` : `diag-arret-etape` s'applique sur `origin/main`, puis `fix-pr52` s'applique
  après lui ; aucun des deux ne s'applique sur HEAD (déjà appliqués).
