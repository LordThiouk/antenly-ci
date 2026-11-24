# Diagnostic — un job FullRun ne s'arrête pas après l'étape demandée (24/11/2026)

## Objet

Un job FullRun lancé avec `stop_after_step` doit exécuter **une seule** étape, puis s'arrêter dès
que l'agent de cette étape a rendu un verdict PASS. Deux runs récents ont continué le pipeline
(ou attendu le mauvais agent) jusqu'au plafond de temps. Ce rapport identifie les causes, décrit le
correctif et les tests.

## Constats

### Run `45328234540` — étape `vera`

- Job `moteur-corrections-vera-2026-11-24-r2`, `start_step=vera`, `stop_after_step=vera`,
  `chain_enabled=false`.
- Opencode a aussi écrit `scripts/corpus/bench/*.py` (environ 1 200 lignes) sur la branche antenly
  `fullrun/moteur-corrections-2026-11-24`, commit `03bddd8` : travail **après** l'étape demandée.
- Fin après environ 1 h 05 : `a:none:Max`, timeout. Le validateur attendait `Max`, absent du run.

### Run `45320422961` — étape `serena`

- Job galass-ci, `start_step=serena`, `stop_after_step=serena`, `done_agents=Architect`.
- Opencode a déroulé `build`, `verify`, `max`, `close`.
- Fin sur `DONE_REASON: a:time`, `OC_STOP: tour` : le validateur attendait `Architect`, qui n'avait
  jamais été dispatché.

## Causes

1. **`stop_after_step` n'était qu'une variable d'environnement.** Le workflow l'exportait en
   `OC_STOP_AFTER_STEP`, puis `run-fullrun.sh` en `FULLRUN_STOP_AFTER_STEP` pour LifeOS. Aucune
   consigne explicite n'était ajoutée au prompt et aucune garde CI n'empêchait les étapes suivantes.
   La seule barrière était `done_check.sh`.
2. **Le validateur attendait `Max` par défaut.** L'input `done_agents` valait `Max` même pour un job
   borné à `vera` (agent `Algorithm`) ou `serena` (agent `Architect`). `done_check.sh` rendait donc
   `a:none:Max` / `a:none:Architect`, et `run-fullrun.sh` relançait une session de reprise.
3. **La reprise pouvait ouvrir l'étape suivante.** Même avec le bon agent, une reprise repartait du
   point de sauvegarde et pouvait continuer le pipeline, ce qu'un job borné ne doit jamais faire.

## Correctif

### 1. Mapping unique étape → agent

Nouveau `opencode/step-agents.sh` (sourçable ou exécutable) :

| Étape | Agent(s) validateur(s) |
|---|---|
| `scaffold`, `completeness_pre`, `vera` (0-2) | `Algorithm` |
| `serena` (3) | `Architect` |
| `build` (4) | `Designer`/`Aditi` (UI) ou `Engineer`/`Forge`/`Anvil` (logique) |
| `verify` (5) | `code-reviewer`, `Forge` ou `Silas` |
| `max`, `close` (6-7) | `Max` |

### 2. Workflow (livré en patch)

Les premier et deuxième correctifs ont été appliqués au workflow par les commits `f932b62` (patch
`diag-arret-etape`) et `1790416` (patch `fix-pr52`) : ces deux patchs sont donc **déjà dans HEAD** et
ne doivent plus être réappliqués. Les corrections de la revue du 24/11 qui restaient ouvertes sont
livrées dans le patch **incrémental** `docs/patches/fix-pr52-r2-2026-11-24.patch`, applicable avec
`git apply` sur le HEAD actuel de la branche (workflow non modifié directement).

Le correctif complet (premiers patchs + r2) :

- met `done_agents` à vide par défaut et accepte le vide dans la garde ;
- calcule `OC_DONE_AGENTS_EFFECTIVE` dans le step de préparation : `done_agents` explicite, sinon
  dans un job borné `target_agent` (prioritaire, car c'est l'agent réellement dispatché), sinon la
  liste des agents autorisés de `stop_after_step`, sinon `Max` ; hors job borné, `Max` reste maître
  même si `target_agent` est fourni (chaînage manuel inchangé) ;
- pose `OC_DONE_AGENTS_ANY=1` pour un job borné : un seul PASS parmi les agents autorisés suffit ;
- ajoute au prompt une section **« Étape finale imposée »** avec l'étape et le même agent que celui
  qui est dispatché (`target_agent` s'il est fourni, sinon la liste autorisée), plus l'interdiction
  explicite de lancer l'étape suivante ;
- rend `stop_after_step` exclusif avec le chaînage : le step « Décision de chaînage » termine la
  chaîne sans `gh workflow run` dès que l'input est posé, avant toute lecture d'état ;
- utilise l'agent effectif dans le préflight, le step `oc`, le validateur final et le dispatch du
  chaînage.

### 3. Wrapper opencode

`opencode/run-fullrun.sh` mémorise `STOP_AFTER` et **désactive toute reprise** quand il est posé.
Sans PASS de l'agent de l'étape, le job rend `127` (`arret=tour-fini`) et écrit
`stop_after_no_resume=<étape>` dans le statut, au lieu de dérouler la suite.

### 4. Test et documentation

- `opencode/tests/stop-after-step-test.sh` : mapping, application du seul patch incrémental r2 sur
  une copie du workflow de HEAD (les patchs déjà intégrés ne sont plus rejoués), calcul de l'agent
  effectif, consigne de prompt, consommation par le workflow, absence de dispatch du lien suivant
  avec `stop_after_step` + `chain_enabled=true`, et deux scénarios bout en bout du wrapper
  (PASS → arrêt immédiat ; pas de PASS → aucune reprise).
- `opencode/tests/first-link-prompt-test.sh` : ne dépend plus de `rg` (grep -E), donc plus de faux
  échec quand ripgrep manque localement.
- `README.md` : `done_agents` vide par défaut, mapping, arrêt sans reprise des jobs bornés et
  exclusivité `stop_after_step`/chaînage.

## Vérifications

- `bash opencode/tests/stop-after-step-test.sh` : **40 OK, 0 KO** (patch r2 appliqué sur une copie
  du workflow de HEAD).
- Workflow patché (r2) appliqué temporairement, puis suites existantes :
  `first-link-prompt-test.sh` 13 OK / 0 KO ; `chain-step-test.sh`, `start-step-test.sh`,
  `turn-end-test.sh`, `prompt-contract-test.sh` : OK.
- `preflight-test.sh` reste dépendant de `rg` et du CLI lifeos (limites d'environnement local ; la
  CI installe ripgrep et le CLI épinglé).
- `bash -n` sur `run-fullrun.sh`, `step-agents.sh`, `done_check.sh` et tous les blocs `run` du
  workflow : OK.
- `git apply --check docs/patches/fix-pr52-r2-2026-11-24.patch` sur le HEAD de la branche : OK.
- `git apply --check docs/patches/fix-pr52-2026-11-24.patch` sur HEAD : échoue, attendu (déjà
  appliqué) ; le test ne le rejoue plus.

Échecs restants de la suite complète, **indépendants de ce correctif** et liés à l'environnement
local : `done-check-test.sh` exige le dépôt lifeos voisin (`FullRunVerdict.ts`/`FullRunVerdictParse.ts`)
et, sous `GITHUB_ACTIONS`, le marqueur root `/etc/fullrun-done-test-mode` ; les tests ciblés du mode
ANY (`12h` à `12l`) passent avec un CLI de verdict local. `leaklog-test.sh` exige une clé `age`.
La CI installe ces outils et ne présente pas ces limites.

## Limites

- Le mapping est centralisé mais reste une hypothèse de contrat pour `scaffold` et
  `completeness_pre` (`Algorithm`). Les six étapes de la règle « un job = une étape » sont couvertes
  explicitement.
- La consigne de prompt réduit fortement le risque, mais un modèle peut encore dépasser son tour ;
  dans ce cas le wrapper s'arrête sans reprise (127) au lieu de continuer le pipeline.
- Le patch workflow r2 (les deux premiers patchs sont déjà dans HEAD) doit être appliqué pour que
  l'exclusivité `stop_after_step`/chaînage et le comportement `target_agent` hors job borné prennent
  effet côté GitHub Actions.

## Fichiers

- `opencode/step-agents.sh` (mapping ; le mode par défaut et `--list` renvoient la même liste
  complète des agents autorisés)
- `opencode/run-fullrun.sh`
- `opencode/done_check.sh` (`OC_DONE_AGENTS_ANY=1`)
- `opencode/tests/stop-after-step-test.sh`
- `opencode/tests/first-link-prompt-test.sh` (`GITHUB_ENV` fourni au prep, sans dépendance à `rg`)
- `opencode/tests/done-check-test.sh` (mode ANY)
- `docs/patches/diag-arret-etape-2026-11-24.patch` (premier patch, appliqué par `f932b62`)
- `docs/patches/fix-pr52-2026-11-24.patch` (deuxième patch, appliqué par `1790416`)
- `docs/patches/fix-pr52-r2-2026-11-24.patch` (correctifs de la revue restants, incrémental sur HEAD)
- `docs/reports/diag-arret-etape-2026-11-24.md` (ce rapport)
- `README.md`
