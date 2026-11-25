# lifeos-ci

Socle CI d'automatisation opencode pour les dépôts `LordThiouk`.

## Rôle

- `task.yml` : tâche opencode simple (revue, correctif, réglage), sans enchaînement.
- `fr-plan-vera.yml` : premier agent FullRun (Plan / Vera), puis `_next.yml` si le run
  est `ok`.
- `_agent-run.yml` : logique commune (validation, checkouts, prompt, quota,
  gitleaks, push fast-forward, PR brouillon, notification).
- `_next.yml` : table `vera → serena → engineer → anvil → forge-code → aditi-ui →
  forge-audit → silas → code-review → max`. Rien n'est déclenché si le statut
  n'est pas `ok` (notamment `quota`) ou si le workflow suivant n'existe pas.

## Inputs communs

`target_repo` (choice, liste blanche), `extra_repos`, `lifeos_write` (bool,
défaut `false`), `branch`, `prompt_path`, `isa_path`, `job_name`, `lifeos_ref`
(défaut `main`), `timeout_minutes` (10 à 90).

`prompt_path` accepte `prompts:<chemin>` (branche `fullrun-prompts` de lifeos-ci)
ou `target:<chemin>` (branche cible).

## Règles lifeos_write

- `false` (défaut) : lifeos est cloné en lecture seule (`chmod -R a-w`), sans
  identifiants dans le remote. `target_repo=lifeos` et tout `lifeos` en
  `extra_repos` sont refusés. Aucun push ni PR vers `LordThiouk/lifeos`.
- `true` : les changements lifeos sont committés par le workflow sur une branche
  dédiée `lifeos-ci/<job_name>`, poussés par le workflow puis ouverts en PR
  brouillon vers lifeos. Jamais `main`/`master`, jamais de fusion automatique.
- Dans tous les cas, `main`/`master` sont des destinations interdites. Le
  workflow pousse en fast-forward et ouvre la PR ; opencode ne pousse jamais.

## Quota et modèles

`models.txt` liste les modèles gratuits par ordre de priorité (uniquement
`opencode/*-free`). `opencode/quota.sh` ne détecte le quota que dans le journal
interne `~/.local/share/opencode/log/*` et dans les vraies lignes d'erreur
fournisseur (429, rate limit, quota, insufficient, exceeded, FreeUsageLimitError).
Les diffs et les blocs de code sont ignorés. Une seule bascule par run : si le
modèle de secours est aussi épuisé, le run finit avec le statut `quota`, sans
lien suivant.

## Clé de porte : `start_step`

Input facultatif du workflow (vide par défaut). `start_step=verify` (ou `build`, `max`, `close`, `0` à `7` ; jamais `deploy`) demande au run de démarrer à cette étape. C'est une **demande**, pas un forçage : LifeOS (`FullRunCarry.proveStart`) n'ouvre la porte que si chaque étape avant a un verdict signé (HMAC `isa_stamp`) ancré sur le commit actuel ; sinon le run redescend à la première étape non prouvée et la raison est écrite dans le log et dans le mandat de l'agent. Si l'étape demandée échoue, retour au build. La valeur passe par l'environnement d'opencode (`FULLRUN_START_STEP`, posé par `run-fullrun.sh`), que l'agent ne peut pas modifier. Aucune garde n'est affaiblie : Max PASS reste obligatoire à la fin. Nécessite la version de LifeOS qui contient `start_step` (`lifeos_ref`) ; une version plus ancienne ignore simplement la variable.

### Préflight du lien : où la porte démarre vraiment

Un lien lancé avec `start_step=verify`, `chain_phase=verify` et `next=code-reviewer` ne démarre à `verify` que si le carry contient un verdict **signé** pour le build. Tant qu'aucun run n'a passé la porte build, il n'y en a pas : la porte redescend au build (« étape 4 (build) : pas de verdict signé »), et `code-reviewer`, agent de `verify`, y est rejeté (« step build rejects agent »). Deux runs de ~95 min ont été perdus ainsi (22 nov. 2026) sans une seule revue, un troisième était bloqué de la même façon. La redescente est voulue ; ce qui manquait était de le savoir avant de dépenser le run.

Le step **Préflight du lien** (`id: preflight`, avant le gel des outils et avant opencode) appelle `LIFEOS/TOOLS/FullRunPreflight.ts` de LifeOS quand `start_step` et `isa_path` sont donnés. Il est en lecture seule : il n'ouvre aucune porte, n'écrit ni `GITHUB_ENV`, ni ISA, ni carry, et ne reçoit aucun secret.

**Table des codes de sortie** (une seule table, celle du CLI lifeos ; le step la traduit) :

| Code | Sens | Effet sur le job |
|------|------|------------------|
| `0` | cohérent : la porte s'ouvre où `start_step` le demande | passe |
| `2` | la porte ne s'ouvre pas où `start_step` le demande (redescente) ; **échoue seul**, même sans chaînage ou avec `chain_phase=build` ; ligne `relance conseillée : start_step=… chain_phase=… next=(vide)` | échec avant opencode |
| `3` | agent imposé par le chaînage (`next`, phase verify) inconnu ou refusé par la porte à l'étape de départ (ex. `Max` en verify, faute de frappe) | échec avant opencode |
| `4` | claims **ouvertes hors périmètre gelé** alors que la porte s'ouvre à verify ou après | échec avant opencode |
| `5` | `chain_phase` incohérent avec l'étape où la porte s'ouvre (ex. `close` alors qu'elle s'ouvre à `max`) | échec avant opencode |
| `64` | entrée invalide (ISA absente, `start_step` ou `chain_phase` invalide, option inconnue) | échec avant opencode |
| `70` | crash interne du CLI (tout autre code inattendu est traité de même) : le contrôle **n'a pas eu lieu** | annotation d'**erreur** `PRÉFLIGHT EN PANNE` et bandeau du résumé ; le run continue, la porte juge seule |

Plusieurs échecs peuvent coexister (le JSON liste tous les codes) ; le code de sortie est le plus prioritaire (2, 4, 3, 5).

Décision sur le périmètre : à verify ou après, **toute claim ouverte hors du périmètre gelé fait échouer (code 4)**. Le build devait la cocher avec preuve, ou elle devait porter un marqueur valide avant le lancement. Au build, ces claims sont le travail du run : pas d'échec.

Le préflight lit **le même état que `initPipeline`** : un état de run restauré (`prev_run_id`) est repris tel quel et `start_step` est alors ignoré, donc pas de faux conflit quand le carry est absent mais l'état est à verify. Sans état, il rejoue la preuve du carry. `phase: complete` : `start_step` ignoré.

- **LifeOS sans `FullRunPreflight.ts`** (`lifeos_ref` ancien) : annotation d'**erreur** `PRÉFLIGHT NON ÉVALUÉ` (jamais silencieux), la porte jugera seule.
- Sortie publique (journal et résumé du job, publics) : **compteurs et codes seulement** ; aucun identifiant de claim, aucun chemin. Les identifiants ne sortent qu'avec `--details`, en local.

Périmètre : le gel a lieu à l'ouverture du run, dès l'étape 4. Un marqueur `[scope:…]` posé **pendant** le build ne sert qu'au run suivant. Le marquage doit donc être dans l'ISA, sur la branche, **avant** le lancement ; il est écrit par l'auteur de l'ISA, jamais par l'outil. Une claim qui reste dans le périmètre (comme ISC-35 dans l'incident) doit être cochée par le vérificateur avec preuve : le préflight ne coche rien et n'élargit rien.

Paramètres du lien suivant : tant que le carry n'a pas de verdict build signé, `start_step=build`, `chain_phase=build`, `next` vide. Une fois le build passé (carry signé sur le commit courant), `start_step=verify`, `chain_phase=verify`, `next=<agent>` (ex. `code-reviewer`), `done_agents` inchangé. Les liens suivants du chaînage laissent `start_step` vide.

## Verdict de fin de run : source unique

Le verdict est lu par le CLI lifeos `LIFEOS/TOOLS/FullRunVerdict.ts` (source unique, même règle que le pipeline). En production `done_check.sh` n'exécute qu'UN couple : `/opt/fullrun-tools/FullRunVerdict.js` (bundle construit à l'étape de gel, échec dur s'il manque) par `/opt/fullrun-tools/bun` avec `/opt/fullrun-tools/bunfig.toml` (vide), dans ce dossier et avec un environnement minimal ; chaque fichier et chaque dossier parent y sont à root, sans lien symbolique ni droit d'écriture pour le groupe ou les autres. `OC_VERDICT_CLI`/`OC_BUN` ne valent que sous `OC_DONE_TEST_MODE=1` (scripts de test ; sous GITHUB_ACTIONS, seulement avec le marqueur root `/etc/fullrun-done-test-mode` posé par `ci.yml`), et chaque appelant (workflow, `run-fullrun.sh`, `checkpoint.sh`) les vide ; aucun repli `~/.claude`. Règle : `pass` = code 0 et sortie `pass`, `unknown` (code 3) = inconclusif, CLI inutilisable = `a:verdict-cli`, jamais PASS.

## Sécurité

- Jeton unique `CI_TOKEN` ; jamais passé à opencode ni affiché.
- Auteur des commits : `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`.
- Porte gitleaks avant tout push.
- opencode ne peut ni `git push`, ni `git merge`, ni `gh`, ni `ssh`/`scp`, ni
  toucher `git remote` ou `http.extraheader`.

## Tests

```bash
bash opencode/tests/run-all.sh
shellcheck -x opencode/*.sh targets/*.sh
actionlint .github/workflows/*.yml
```
