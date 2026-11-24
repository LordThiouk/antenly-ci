# Revue — un job FullRun s'arrête à l'étape demandée (24/11/2026)

## Objet

Revue de la branche `fix/diag-arret-etape-2026-11-24` (HEAD `43283bd`) contre `origin/main`
(`5647624`), sur le diagnostic `docs/reports/diag-arret-etape-2026-11-24.md`, le diff de la branche
(`.github/workflows/opencode-fullrun.yml`, `opencode/run-fullrun.sh`, `opencode/step-agents.sh`,
`opencode/done_check.sh`, `opencode/tests/stop-after-step-test.sh`) et les patches
`docs/patches/*.patch`.

Les correctifs des revues précédentes sont désormais dans HEAD : `f932b62`, `1790416`,
`2f40055`, puis `43283bd` qui applique `fix-pr52-r3`.

Verdict : À CORRIGER

## Problèmes

### 1. Moyen — le rapport de diagnostic est obsolète sur l'état du patch r3

- Fichiers/lignes :
  - `docs/reports/diag-arret-etape-2026-11-24.md:59-64` (« patch incrémental applicable avec
    `git apply` sur le HEAD actuel », « workflow non modifié directement »)
  - `docs/reports/diag-arret-etape-2026-11-24.md:119` (`git apply --check` de r3 sur HEAD « OK »)
  - `docs/reports/diag-arret-etape-2026-11-24.md:145-146` (« doit être appliqué »)
  - `.github/workflows/opencode-fullrun.yml:2043-2048` (contrôle r3 présent)
  - HEAD `43283bd` (« applique tel quel docs/patches/fix-pr52-r3-2026-11-24.patch »)
- Gravité : **moyen**.

Le rapport décrit encore r3 comme un patch non appliqué. Or HEAD contient déjà le contrôle du
statut final borné chaîné, et `git apply --check docs/patches/fix-pr52-r3-2026-11-24.patch`
échoue sur HEAD (patch déjà appliqué), comme pour les trois patches précédents. Le rapport doit
être mis à jour : r3 est intégré, le patch est historique, et la vérification « `git apply --check`
r3 : OK » n'est plus vraie.

### 2. Moyen — `target_agent` contourne le mapping étape → agents sans contrôle d'appartenance

- Fichiers/lignes :
  - `.github/workflows/opencode-fullrun.yml:38-39` (description : « un seul agent de l'étape
    visée »)
  - `.github/workflows/opencode-fullrun.yml:269-272` (la garde ne valide que le charset)
  - `.github/workflows/opencode-fullrun.yml:657-671` (`target_agent` prioritaire sur le mapping)
  - `.github/workflows/opencode-fullrun.yml:678-686` (le prompt impose cet agent)
  - `opencode/step-agents.sh:22-35` (liste autorisée par étape)
  - `opencode/tests/stop-after-step-test.sh:117-120` (seuls des `target_agent` valides sont testés)
- Gravité : **moyen**.

Avec `stop_after_step`, `target_agent` est utilisé tel quel comme validateur, sans vérifier qu'il
appartient à la liste autorisée de l'étape. Vérifié sur le bloc réel de prep :

```
stop_after_step=vera  target_agent=Max       -> OC_DONE_AGENTS_EFFECTIVE=Max
stop_after_step=build target_agent=Silas     -> OC_DONE_AGENTS_EFFECTIVE=Silas
stop_after_step=verify target_agent=Designer -> OC_DONE_AGENTS_EFFECTIVE=Designer
```

Le job peut donc exiger le PASS d'un agent hors de la règle de Papa (Max pour vera, Silas pour
build, etc.), et le prompt lui demande de dispatcher cet agent. Le préflight ne le refuse que
lorsque `isa_path` est fourni ; un job borné sans ISA passe la garde. Attendu : refuser un
`target_agent` absent de `opencode/step-agents.sh` pour l'étape visée, ou l'intersecter avec la
liste autorisée, avant de le publier dans `OC_DONE_AGENTS_EFFECTIVE`, et couvrir ce cas dans
`stop-after-step-test.sh`.

### 3. Faible — en borné + chaîné, `finish_chain` court-circuite les portes d'échec du chaînage

- Fichiers/lignes :
  - `.github/workflows/opencode-fullrun.yml:1837-1842` (`finish_chain` dès que
    `IN_STOP_AFTER_STEP` est posé, avant `CHECK_OUTCOME`, `PUSH_OUTCOME`, `save_state`,
    `restore_state` et `OC_STOP`)
  - `.github/workflows/opencode-fullrun.yml:2043-2048` (statut final : seul `DONE=ok` est exigé)
- Gravité : **faible**.

Un job borné lancé avec `chain_enabled=true` termine la chaîne immédiatement, sans évaluer les
portes placées plus bas. Les échecs de `check`/`push`/`save_state`/`publish_state` font encore
échouer le job par le statut du step, mais un `restore_state` refusé (le step sort 0 avec
`status=refused`) ou un `OC_STOP` anormal (`erreur`, `silence`, `plafond`, `vide`, `annulation`,
sortie absente ; le step `oc` est `continue-on-error`) ne sont plus bloquants si `DONE=ok`.
Vérifié en exécutant les blocs réels : `IN_STOP_AFTER_STEP=vera` + `OC_STOP=erreur` +
`DONE=ok` donne `rc=0` au statut final. Le même job borné non chaîné échoue (`OC_OUTCOME`
n'est pas `success`). Attendu : évaluer les portes peu coûteuses (`CHECK_OUTCOME`,
`PUSH_OUTCOME`, `OC_STOP`, statut de restauration) avant le `finish_chain` du job borné, ou les
revérifier dans le statut final.

### 4. Faible — le contrôle r3 n'est pas couvert par le test permanent

- Fichiers/lignes :
  - `opencode/tests/stop-after-step-test.sh:164-188` (teste l'arrêt anticipé du chaînage, pas le
    statut final r3)
  - `docs/reports/diag-arret-etape-2026-11-24.md:100` (r3 validé seulement sur un worktree
    temporaire)
- Gravité : **faible**.

Le test permanent ne vérifie pas qu'un job borné chaîné sans PASS échoue au statut final. Le
contrôle r3 peut donc régresser sans être détecté. Un scénario borné + `chain_enabled=true` +
`DONE=ko` (exit 1) et `DONE=ok` (exit 0), exécuté sur le bloc « Statut final » extrait, serait
utile.

### 5. Faible — la description de `target_agent` contredit le mode ANY du job borné

- Fichiers/lignes :
  - `.github/workflows/opencode-fullrun.yml:38-39` (« vide = tous les agents requis de l'étape »)
  - `.github/workflows/opencode-fullrun.yml:657-673` et `README.md:338-341` (vide + borné =
    un seul PASS parmi les agents autorisés, `OC_DONE_AGENTS_ANY=1`)
- Gravité : **faible**.

Sans `target_agent`, un job borné ne requiert plus tous les agents de l'étape mais un seul PASS
parmi eux. La description de l'input n'a pas été mise à jour et induit en erreur.

### 6. Faible — le mapping de `scaffold`/`completeness_pre` reste une hypothèse

- Fichiers/lignes :
  - `opencode/step-agents.sh:25-26` (`scaffold` et `completeness_pre` → `Algorithm`)
  - `docs/reports/diag-arret-etape-2026-11-24.md:134-135` (hypothèse reconnue)
- Gravité : **faible**.

La règle citée ne couvre que les étapes 2 à 7. Si `FullRunPipeline.ts` n'utilise pas `Algorithm`
pour ces deux étapes, un job borné y échouera faute de PASS. L'hypothèse est documentée ; à
confirmer côté lifeos.

## Points vérifiés

- **Arrêt d'un job borné (sans chaînage)** : `opencode/run-fullrun.sh:91-95,751-757,813` désactive
  toute reprise quand `OC_STOP_AFTER_STEP` est posé ; sans PASS, sortie `127` / `arret=tour-fini` /
  `stop_after_no_resume=<étape>`. Les scénarios du test (PASS → arrêt immédiat ; pas de PASS → un
  seul tour, aucune reprise) passent.
- **Chaînage manuel (`chain_enabled=false`) inchangé** : sans `stop_after_step`, `done_agents` vide
  retombe sur `Max` même si `target_agent` est fourni
  (`.github/workflows/opencode-fullrun.yml:657-671`), couvert par
  `opencode/tests/stop-after-step-test.sh:123`.
- **Mapping 2-7 conforme à la règle de Papa** : `opencode/step-agents.sh:22-35` donne
  vera → `Algorithm`, serena → `Architect`, build → `Designer,Aditi,Engineer,Forge,Anvil`,
  verify → `code-reviewer,Forge,Silas`, max/close → `Max`. Le mode par défaut et `--list`
  renvoient la même liste complète : aucun agent fixe (Forge pour build, Silas pour verify)
  n'est imposé par défaut. Le seul agent fixe possible vient d'un `target_agent` explicite
  (problème 2).
- **Mode ANY** : `opencode/done_check.sh:271-289` exige qu'un même agent satisfasse a et b. Test
  ad hoc avec un faux CLI/bun (voir plus bas) : `Max` seul ou `Silas` seul parmi
  `Max,Silas` → `done_check=ok` ; mode non-ANY → `a:none:Silas` / `a:none:Max`.
- **Statut final r3** : extrait et exécuté sur le workflow courant ; borné chaîné + `DONE=ko` →
  `rc=1` ; borné chaîné + `DONE=ok` → `rc=0` ; non borné + `DONE=ko` → `rc=0` (comportement
  historique).
- **Pas de secret introduit** : `gitleaks detect --source . --log-opts="origin/main..HEAD"` :
  aucun leak.
- **`bash -n`** : OK sur `run-fullrun.sh`, `step-agents.sh`, `done_check.sh`,
  `stop-after-step-test.sh`.
- **`shellcheck -S error`** : OK sur ces mêmes scripts.

## Risque résiduel (non bloquant)

- En mode ANY, `opencode/done_check.sh:271-289` accepte le PASS de n'importe quel agent autorisé de
  l'étape, pas nécessairement celui réellement dispatché. Les garde-fous « postérieur au dernier
  commit de code » et `hooks.log` limitent le risque, mais la formulation du prompt (« celui de
  l'agent dispatché ») est plus stricte que le validateur.
- L'arrêt intra-tour reste dépendant du prompt et de la surveillance `done_check` : si le modèle
  écrit l'étape suivante avant la coupure, du travail supplémentaire peut être produit. La reprise
  et le lien suivant sont bien bloqués ; la limite est documentée dans le diagnostic.

## Tests exécutés (environnement local, 24/11/2026)

- `bash opencode/tests/stop-after-step-test.sh` : **39 OK, 0 FAIL, exit 0**.
- `bash opencode/tests/chain-step-test.sh` : exit 0.
- `bash opencode/tests/start-step-test.sh` : exit 0.
- `bash opencode/tests/first-link-prompt-test.sh` : exit 0.
- `bash opencode/tests/turn-end-test.sh` : exit 0.
- `bash opencode/tests/prompt-contract-test.sh` : exit 0.
- `bash opencode/tests/preflight-test.sh` : 5 OK / 20 FAIL, exit 1, à cause de `rg` absent
  localement (limite d'environnement ; la CI installe ripgrep).
- `bash opencode/tests/done-check-test.sh` : non exécutable localement (`bun` absent). Les cas ANY
  ont été vérifiés à part avec un faux CLI/bun : `Max` seul et `Silas` seul parmi `Max,Silas` →
  `done_check=ok` ; mode non-ANY → `a:none:Silas` / `a:none:Max`.
- `git apply --check` des patches `diag-arret-etape`, `fix-pr52`, `fix-pr52-r2` et `fix-pr52-r3`
  sur HEAD : échec attendu (déjà appliqués).
- `gitleaks detect` sur `origin/main..HEAD` : aucun leak.
