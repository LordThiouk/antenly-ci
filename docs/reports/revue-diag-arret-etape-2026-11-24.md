# Revue — un job FullRun s'arrête à l'étape demandée (24/11/2026)

## Objet

Revue de la branche `fix/diag-arret-etape-2026-11-24` (HEAD `2f40055`) contre `origin/main`
(`5647624`), sur le diagnostic `docs/reports/diag-arret-etape-2026-11-24.md`, le diff de la branche
(`.github/workflows/opencode-fullrun.yml`, `opencode/run-fullrun.sh`, `opencode/step-agents.sh`,
`opencode/done_check.sh`, `opencode/tests/stop-after-step-test.sh`) et les patches
`docs/patches/*.patch`.

Cette revue remplace la précédente : les trois patches (`diag-arret-etape`, `fix-pr52`,
`fix-pr52-r2`) sont désormais appliqués dans HEAD, le dernier par le commit `2f40055`.

Verdict : À CORRIGER

## Problèmes

### 1. Bloquant — `stop-after-step-test.sh` applique le patch r2 sur un HEAD qui le contient déjà

- Fichiers/lignes :
  - `opencode/tests/stop-after-step-test.sh:55-63` (extrait le workflow de HEAD puis `git apply` de r2)
  - `docs/patches/fix-pr52-r2-2026-11-24.patch` (contenu déjà présent dans HEAD)
  - `.github/workflows/opencode-fullrun.yml:68-71,651-673,1837-1842` (version déjà patchée)
  - HEAD `2f40055` (« applique tel quel docs/patches/fix-pr52-r2-2026-11-24.patch »)
- Gravité : **bloquant**.

Le test lit le workflow de HEAD, puis applique `fix-pr52-r2` sur cette copie. Or HEAD contient déjà
ce patch : l'application échoue forcément. Exécution réelle sur HEAD :

```
FAIL patch incrémental r2 : git apply impossible (error: patch failed: .github/workflows/opencode-fullrun.yml:68 ...)
39 OK, 1 FAIL, exit 1
```

et `git apply --check docs/patches/fix-pr52-r2-2026-11-24.patch` renvoie 1 sur HEAD. La séquence
complète `diag-arret-etape` → `fix-pr52` → `fix-pr52-r2` s'applique bien sur `origin/main` et produit
un workflow identique à celui de HEAD (vérifié sur une copie temporaire). `.github/workflows/ci-scripts.yml:76`
exécute tous les `opencode/tests/*-test.sh` et `stop-after-step-test.sh` n'est pas dans
`OC_CI_KNOWN_FAILING` : la CI de la PR échouera.

Attendu : tester directement le workflow de HEAD, ou rejouer la séquence de patches sur `origin/main`,
ou supprimer le patch devenu redondant. Aucun correctif n'a été appliqué dans cette revue.

### 2. Moyen — le rapport de diagnostic annonce des vérifications fausses

- Fichiers/lignes :
  - `docs/reports/diag-arret-etape-2026-11-24.md:97-98` (« 40 OK, 0 KO »)
  - `docs/reports/diag-arret-etape-2026-11-24.md:106` (`git apply --check` de r2 sur HEAD « OK »)
  - `docs/reports/diag-arret-etape-2026-11-24.md:53-59` (r2 « applicable sur le HEAD actuel »)
  - `docs/reports/diag-arret-etape-2026-11-24.md:85-89` (application de r2 sur une copie de HEAD)
- Gravité : **moyen**.

Sur HEAD, le test donne **39 OK / 1 FAIL** (exit 1), pas 40 OK / 0 KO, et `git apply --check` de r2
échoue. Le rapport décrit donc un état qui n'est plus celui de la branche et masque le problème
bloquant ci-dessus.

### 3. Moyen — un job borné combiné à `chain_enabled=true` peut finir vert sans PASS

- Fichiers/lignes :
  - `.github/workflows/opencode-fullrun.yml:1840-1842` (`finish_chain` dès que `stop_after_step` est posé)
  - `.github/workflows/opencode-fullrun.yml:2025-2043` (branche « chaîné » du statut final : `exit 0` sans contrôle de `DONE`)
  - `opencode/run-fullrun.sh:751-757,811-813` (sans PASS : `127`, `arret=tour-fini`)
- Gravité : **moyen**.

Quand `stop_after_step` et `chain_enabled=true` sont fournis ensemble, le wrapper peut rendre `127`
sans PASS, puis le step « Décision de chaînage » termine la chaîne (`block=false`, `continue=false`).
Le step « Statut final » prend alors la branche chaînée et sort **0** sans jamais vérifier `DONE` :
le job borné est arrêté (aucun lien suivant dispatché, l'exigence principale est tenue) mais il peut
être vert sans le verdict exigé, contrairement au même job borné en `chain_enabled=false`
(`.github/workflows/opencode-fullrun.yml:2045-2050`).

Attendu : refuser la combinaison dans la garde, ou faire contrôler `DONE`/le PASS au statut final
lorsque `stop_after_step` est posé, même en mode chaîné.

### 4. Faible — l'arrêt strict à l'étape reste dépendant du prompt pour le travail intra-tour

- Fichiers/lignes :
  - `.github/workflows/opencode-fullrun.yml:677-699` (consigne « Étape finale imposée »)
  - `opencode/run-fullrun.sh:737,751-757,811-813` (`maybe_finish`/fin de tour, puis pas de reprise)
- Gravité : **faible** (limite documentée dans le diagnostic).

La reprise et le lien suivant sont bien bloqués, mais la seule barrière contre le passage à l'étape
suivante **dans le même tour** est la consigne du prompt. Si le modèle écrit l'étape suivante avant
de rendre la main, `maybe_finish` constate le PASS de l'étape cible et sort 0 après ce travail
supplémentaire (scénario du run `45328234540`). La consigne réduit fortement le risque, sans le
supprimer ; ce n'est pas un blocage de cette revue.

## Risque résiduel (non bloquant)

En mode ANY, `opencode/done_check.sh:271-287` accepte le PASS de n'importe quel agent autorisé de
l'étape, pas nécessairement celui réellement dispatché. Les garde-fous « postérieur au dernier commit
de code » et `hooks.log` limitent le risque, mais la formulation du prompt (« celui de l'agent
dispatché ») est plus stricte que le validateur.

## Points vérifiés

- **Arrêt d'un job borné (sans chaînage)** : `opencode/run-fullrun.sh:91-95,751-757,813` désactive
  toute reprise quand `OC_STOP_AFTER_STEP` est posé ; sans PASS, sortie `127` / `arret=tour-fini` /
  `stop_after_no_resume=<étape>`. Les deux scénarios bout en bout du test (PASS → arrêt immédiat ;
  pas de PASS → un seul tour, aucune reprise) passent.
- **Chaînage manuel (`chain_enabled=false`) inchangé** : sans `stop_after_step`, `done_agents` vide
  retombe sur `Max` même si `target_agent` est fourni
  (`.github/workflows/opencode-fullrun.yml:668-670`), comportement couvert par
  `opencode/tests/stop-after-step-test.sh:130-132` (OK). `chain-step-test.sh` et `start-step-test.sh`
  passent.
- **Mapping par étape conforme à la règle de Papa** : `opencode/step-agents.sh:22-40` couvre
  vera → `Algorithm`, serena → `Architect`, build → `Designer,Aditi,Engineer,Forge,Anvil`,
  verify → `code-reviewer,Forge,Silas`, max/close → `Max`. Les deux accesseurs (mode par défaut et
  `--list`) renvoient la même liste complète : aucun agent fixe (Forge pour build, Silas pour verify)
  ne peut plus bloquer un job légitime. Un `target_agent` unique reste voulu : c'est l'agent
  réellement dispatché.
- **Agent effectif** : calculé une fois dans le step prep
  (`.github/workflows/opencode-fullrun.yml:657-673`) puis consommé par le préflight (l. 740), le step
  `oc` (l. 1114-1115), le validateur final (l. 1522-1523) et le dispatch du chaînage (l. 1971).
- **Mode ANY** : `opencode/done_check.sh:271-331` exige qu'un même agent satisfasse a et b ; les
  tests `12h` à `12l` de `done-check-test.sh` encodent ce comportement (non exécutables ici, `bun`
  absent).
- **Pas de secret introduit** : `gitleaks detect --source . --log-opts="origin/main..HEAD"` :
  aucun leak. Le seul résultat d'un scan complet de l'historique
  (`opencode/tests/hmac-state-test.sh:20`, clé de test factice) est antérieur à la branche et déjà
  sur `origin/main`.
- **`bash -n`** : OK sur `run-fullrun.sh`, `step-agents.sh`, `done_check.sh`,
  `stop-after-step-test.sh`.

## Tests exécutés (environnement local, 24/11/2026)

- `bash opencode/tests/stop-after-step-test.sh` : **39 OK, 1 FAIL, exit 1** — problème 1.
- `bash opencode/tests/chain-step-test.sh` : OK, exit 0.
- `bash opencode/tests/start-step-test.sh` : OK, exit 0.
- `bash opencode/tests/turn-end-test.sh` : OK, exit 0.
- `bash opencode/tests/prompt-contract-test.sh` : OK, exit 0.
- `bash opencode/tests/first-link-prompt-test.sh` : OK, exit 0.
- `bash opencode/tests/preflight-test.sh` : échoue localement faute de `rg` (5 ok, 20 ko), limite
  d'environnement ; la CI installe ripgrep et le CLI lifeos épinglé.
- `bash opencode/tests/done-check-test.sh` : non exécutable localement (`bun` absent ; présent en
  CI).
- `git apply --check` : r2 échoue sur HEAD (déjà appliqué) ; la séquence
  `diag-arret-etape` → `fix-pr52` → `fix-pr52-r2` s'applique sur `origin/main` et reproduit le
  workflow de HEAD à l'identique.
