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

| Étape | Agent validateur |
|---|---|
| `scaffold`, `completeness_pre`, `vera` (0-2) | `Algorithm` |
| `serena` (3) | `Architect` |
| `build` (4) | `Forge` |
| `verify` (5) | `Silas` |
| `max`, `close` (6-7) | `Max` |

### 2. Workflow (livré en patch)

`.github/workflows/opencode-fullrun.yml` n'est **pas** modifié dans l'arbre : le diff est dans
`docs/patches/diag-arret-etape-2026-11-24.patch`, applicable sur `main` avec `git apply`.

Le patch :

- met `done_agents` à vide par défaut et accepte le vide dans la garde ;
- calcule `OC_DONE_AGENTS_EFFECTIVE` dans le step de préparation : `done_agents` explicite, sinon
  l'agent de `stop_after_step`, sinon `target_agent`, sinon `Max` ;
- ajoute au prompt une section **« Étape finale imposée »** avec l'étape, l'agent validateur et
  l'interdiction explicite de lancer l'étape suivante ;
- utilise l'agent effectif dans le préflight, le step `oc`, le validateur final et le dispatch du
  chaînage.

### 3. Wrapper opencode

`opencode/run-fullrun.sh` mémorise `STOP_AFTER` et **désactive toute reprise** quand il est posé.
Sans PASS de l'agent de l'étape, le job rend `127` (`arret=tour-fini`) et écrit
`stop_after_no_resume=<étape>` dans le statut, au lieu de dérouler la suite.

### 4. Test et documentation

- `opencode/tests/stop-after-step-test.sh` : mapping, application du patch, calcul de l'agent
  effectif, consigne de prompt, consommation par le workflow et deux scénarios bout en bout du
  wrapper (PASS → arrêt immédiat ; pas de PASS → aucune reprise).
- `README.md` : `done_agents` vide par défaut, mapping, et arrêt sans reprise des jobs bornés.

## Vérifications

- `bash opencode/tests/stop-after-step-test.sh` : **23 OK, 0 KO**.
- Workflow patché appliqué temporairement, puis suites existantes :
  `preflight-test.sh` 24 OK / 0 KO ;
  `first-link-prompt-test.sh`, `prompt-contract-test.sh`, `chain-step-test.sh`,
  `start-step-test.sh`, `turn-end-test.sh` : OK.
- `bash -n` sur `run-fullrun.sh`, `step-agents.sh` et tous les blocs `run` du workflow : OK.
- `git apply --check docs/patches/diag-arret-etape-2026-11-24.patch` sur le workflow d'origine : OK.

Échecs restants de la suite complète, **indépendants de ce correctif** et liés à l'environnement
local : `bun` absent (`done-check-test.sh`, `checkpoint-watchdog-verdict-test.sh`), clé `age`
absente (`leaklog-test.sh`), et `watchdog-test.sh` instable sur la course « worker déjà terminé
avant le kill ». La CI installe ces outils et ne présente pas ces limites.

## Limites

- Le mapping est centralisé mais reste une hypothèse de contrat pour `scaffold` et
  `completeness_pre` (`Algorithm`). Les six étapes de la règle « un job = une étape » sont couvertes
  explicitement.
- La consigne de prompt réduit fortement le risque, mais un modèle peut encore dépasser son tour ;
  dans ce cas le wrapper s'arrête sans reprise (127) au lieu de continuer le pipeline.
- Le patch workflow doit être appliqué pour que `stop_after_step` prenne effet côté GitHub Actions.

## Fichiers

- `opencode/step-agents.sh` (nouveau)
- `opencode/run-fullrun.sh`
- `opencode/tests/stop-after-step-test.sh` (nouveau)
- `docs/patches/diag-arret-etape-2026-11-24.patch` (nouveau)
- `docs/reports/diag-arret-etape-2026-11-24.md` (ce rapport)
- `README.md`
