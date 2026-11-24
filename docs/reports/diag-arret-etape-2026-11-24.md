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

### 2. Workflow (patchs déjà intégrés + patch r3)

Les trois premiers correctifs sont déjà dans HEAD : `f932b62` (patch `diag-arret-etape`), `1790416`
(patch `fix-pr52`) et `2f40055` (patch `fix-pr52-r2`). Ces patchs ne doivent plus être réappliqués :
`git apply --check` échoue sur HEAD (déjà appliqué), ce qui est attendu.

Le point restant de la revue r3 — un job borné combiné à `chain_enabled=true` pouvait finir vert sans
PASS — est livré dans le patch **incrémental** `docs/patches/fix-pr52-r3-2026-11-24.patch`,
applicable avec `git apply` sur le HEAD actuel (workflow non modifié directement). Il ajoute au step
« Statut final » un contrôle : en mode chaîné, dès que `stop_after_step` est posé, le job échoue si
`DONE` n'est pas `ok`. Le step de chaînage termine déjà la chaîne sans `gh workflow run`, donc aucun
lien suivant n'est dispatché.

Le correctif complet (patchs intégrés + r3) :

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
- ne finit jamais vert sans PASS en mode chaîné quand `stop_after_step` est posé : le « Statut
  final » exige `DONE=ok` (r3) ;
- utilise l'agent effectif dans le préflight, le step `oc`, le validateur final et le dispatch du
  chaînage.

### 3. Wrapper opencode

`opencode/run-fullrun.sh` mémorise `STOP_AFTER` et **désactive toute reprise** quand il est posé.
Sans PASS de l'agent de l'étape, le job rend `127` (`arret=tour-fini`) et écrit
`stop_after_no_resume=<étape>` dans le statut, au lieu de dérouler la suite. En outre, `run_watched`
surveille déjà le PASS **pendant** la passe (`done_check` toutes les `OC_DONE_CHECK_SEC`, coupure
après `OC_DONE_IDLE_SEC` d'inactivité) : l'arrêt intra-tour est donc largement porté par le script,
la consigne de prompt n'étant qu'une sécurité supplémentaire.

### 4. Test et documentation

- `opencode/tests/stop-after-step-test.sh` : vérifie l'arbre **courant tel quel** (aucune lecture ni
  application de `docs/patches/`) : mapping, calcul de l'agent effectif, consigne de prompt,
  consommation par le workflow, absence de dispatch du lien suivant avec `stop_after_step` +
  `chain_enabled=true`, et trois scénarios bout en bout du wrapper (PASS → arrêt immédiat ; pas de
  PASS → aucune reprise ; PASS d'un agent autorisé en mode ANY → arrêt immédiat). Le correctif r3
  (statut final borné chaîné) est validé sur un worktree temporaire, jamais dans le test permanent.
- `opencode/tests/first-link-prompt-test.sh` : ne dépend plus de `rg` (grep -E), donc plus de faux
  échec quand ripgrep manque localement.
- `README.md` : `done_agents` vide par défaut, mapping, arrêt sans reprise des jobs bornés et
  exclusivité `stop_after_step`/chaînage.

## Vérifications

- `bash opencode/tests/stop-after-step-test.sh` sur l'arbre courant : **39 OK, 0 FAIL, exit 0**.
- `bash opencode/tests/chain-step-test.sh` : 44 OK, exit 0.
- `bash opencode/tests/start-step-test.sh` : 12 OK, exit 0.
- `bash opencode/tests/first-link-prompt-test.sh` : 13 OK, exit 0.
- `bash opencode/tests/turn-end-test.sh` : 6 ok, exit 0.
- `bash opencode/tests/prompt-contract-test.sh` : 5 ok, exit 0.
- `bash opencode/tests/preflight-test.sh` : échoue localement faute de `rg` (`rg: command not
  found`, 5 OK / 20 FAIL) ; la CI installe ripgrep et le CLI lifeos épinglé.
- `bash opencode/tests/done-check-test.sh` : non exécutable localement (`bun` absent ; présent en
  CI).
- `bash -n` sur `run-fullrun.sh`, `step-agents.sh`, `done_check.sh`, `stop-after-step-test.sh` : OK.
- `git apply --check docs/patches/fix-pr52-r3-2026-11-24.patch` sur HEAD : OK.
- `git apply --check` des patchs `fix-pr52-r2` et `fix-pr52` sur HEAD : échoue (déjà appliqués),
  attendu ; le test ne les rejoue plus.
- r3 appliqué sur un worktree temporaire : borné chaîné sans PASS → exit 1 ; borné chaîné avec PASS
  → exit 0 ; lien intermédiaire sans PASS → exit 0 (inchangé) ; le test `stop-after-step-test.sh` y
  passe aussi (39 OK / 0 FAIL).

Échecs restants de la suite complète, **indépendants de ce correctif** et liés à l'environnement
local : `done-check-test.sh` exige le dépôt lifeos voisin (`FullRunVerdict.ts`/`FullRunVerdictParse.ts`)
et, sous `GITHUB_ACTIONS`, le marqueur root `/etc/fullrun-done-test-mode` ; les tests ciblés du mode
ANY (`12h` à `12l`) passent avec un CLI de verdict local. `leaklog-test.sh` exige une clé `age`.
La CI installe ces outils et ne présente pas ces limites.

## Limites

- Le mapping est centralisé mais reste une hypothèse de contrat pour `scaffold` et
  `completeness_pre` (`Algorithm`). Les six étapes de la règle « un job = une étape » sont couvertes
  explicitement.
- **Arrêt intra-tour (limite connue, non bloquante).** Le script ne s'appuie pas que sur le prompt :
  `run_watched` interroge `done_check` toutes les `OC_DONE_CHECK_SEC` (60 s par défaut) et coupe la
  session dès que le PASS est vérifié et que la session est inactive depuis `OC_DONE_IDLE_SEC`
  (180 s), avant la fin du tour. Il reste un cas résiduel : si le modèle poursuit l'étape suivante
  dans le même tour avant que cette détection ne coupe (ou produit des commits qui rendent le PASS
  non « postérieur au dernier commit de code »), du travail supplémentaire peut être écrit. La
  consigne de prompt réduit fortement ce risque sans le supprimer ; un job borné ne reprend jamais
  et, sans PASS vérifié, échoue en `127` au lieu de continuer le pipeline.
- Le patch workflow r3 (les trois premiers patchs sont déjà dans HEAD) doit être appliqué pour que
  le statut final refuse un job borné chaîné sans PASS côté GitHub Actions.

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
- `docs/patches/fix-pr52-r2-2026-11-24.patch` (troisième patch, appliqué par `2f40055`)
- `docs/patches/fix-pr52-r3-2026-11-24.patch` (statut final borné chaîné : PASS exigé, incrémental
  sur HEAD, non appliqué directement)
- `docs/reports/diag-arret-etape-2026-11-24.md` (ce rapport)
- `README.md`
