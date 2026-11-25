# Inventaire des scripts — antenly-ci / galass-ci / lifeos-ci-seed

- Date : 2026-11-25
- Branche : `seed/lifeos-ci-2026-11-24`
- Périmètre : fichiers `*.sh`, `*.ts`, `*.py` sous les répertoires `opencode/` et `ci/`.
  Aucun répertoire `ci/` n'existe dans les trois sources ; seul `opencode/` a été inventorié.
- Sources : `antenly-ci` = dépôt courant (`.`), `galass-ci` = clone `https://github.com/LordThiouk/galass-ci` (profondeur 1), `lifeos-ci-seed` = `lifeos-ci-seed/`.
- Exclus des recherches : `node_modules`, `.git`, `dist`, `build`, `.venv`.
- Format des cellules : `sha256 court (nombre de lignes)`. `—` = fichier absent de la source.

## Étape A — table de correspondance par nom de fichier

| Fichier | antenly-ci | galass-ci | lifeos-ci-seed | Statut |
|---|---|---|---|---|
| `agent-idle-test.sh` | `a8e309d493f2 (118 l.)` | `a8e309d493f2 (118 l.)` | `99b8a38a222d (118 l.)` | **différent** |
| `allowed-repos-cwd-test.sh` | — | `d9b92a32e8a2 (148 l.)` | `a34cd87ad8fa (148 l.)` | **différent** |
| `allowed-repos-lifeos-test.sh` | — | — | `3bcbcdcd3dff (88 l.)` | **unique** (lifeos-ci-seed) |
| `allowed-repos-test.sh` | — | `75e67344837c (57 l.)` | `3ac0f755c9fb (67 l.)` | **différent** |
| `allowed-repos.sh` | — | `67623897a7ff (27 l.)` | `67623897a7ff (27 l.)` | **identique** (2 sources) |
| `autosave-test.sh` | `e019782fe662 (188 l.)` | `c44813c53195 (190 l.)` | `c44813c53195 (190 l.)` | **différent** |
| `autosave.sh` | `2eaa914d11ca (239 l.)` | `26bcd9c93433 (249 l.)` | `26bcd9c93433 (249 l.)` | **différent** |
| `chain-step-test.sh` | `6fb2b50616ca (301 l.)` | `18438fa309f6 (485 l.)` | `a99664e5d0a0 (301 l.)` | **différent** |
| `checkpoint-watchdog-verdict-test.sh` | `f802f2eae8dc (193 l.)` | `93c0a347eb37 (193 l.)` | `4e5c46d4c2d2 (193 l.)` | **différent** |
| `checkpoint.sh` | `eb4726026dfd (201 l.)` | `98162c3c3cfa (201 l.)` | `c17b75950428 (202 l.)` | **différent** |
| `critical-frozen-tools-test.sh` | — | — | `d95443b2b93f (61 l.)` | **unique** (lifeos-ci-seed) |
| `critical-git-isolation-test.sh` | — | — | `e35c84dcd36d (120 l.)` | **unique** (lifeos-ci-seed) |
| `critical-state-isolation-test.sh` | — | — | `b01e51858f18 (80 l.)` | **unique** (lifeos-ci-seed) |
| `done-check-call.sh` | `6d28d082d126 (11 l.)` | `6d28d082d126 (11 l.)` | `6d28d082d126 (11 l.)` | **identique** (3 sources) |
| `done-check-test.sh` | `e048f4e5c3b6 (800 l.)` | `480c9fd841b5 (790 l.)` | `5629ed508ecb (800 l.)` | **différent** |
| `done_check.sh` | `1a6a42108cb4 (389 l.)` | `478489ea9637 (348 l.)` | `1a6a42108cb4 (389 l.)` | **différent** |
| `emu-e2e.sh` | — | `685010bc0fe9 (585 l.)` | `685010bc0fe9 (585 l.)` | **identique** (2 sources) |
| `extra-repos-test.sh` | — | `b23258651c8d (436 l.)` | `8dafc0f57687 (436 l.)` | **différent** |
| `extra-repos.sh` | — | `978399e958d2 (476 l.)` | `57f2d8cebc8a (480 l.)` | **différent** |
| `ffmpeg-install-test.sh` | `7e5becc1595d (41 l.)` | — | `559a95187587 (41 l.)` | **différent** |
| `first-link-prompt-test.sh` | `7e217eec9b43 (147 l.)` | `c5e657464170 (148 l.)` | `7860ba9223ea (147 l.)` | **différent** |
| `hmac-state-test.sh` | `6b1f78d363f3 (270 l.)` | `53fb48cf408c (319 l.)` | `de9f9db80da7 (319 l.)` | **différent** |
| `hook-profile-install-test.sh` | `c193dcf69845 (98 l.)` | `c193dcf69845 (98 l.)` | `e2bd67e2032f (98 l.)` | **différent** |
| `install-hook-profile.sh` | `c288bbe74040 (92 l.)` | `080e532c3b38 (94 l.)` | `080e532c3b38 (94 l.)` | **différent** |
| `internals-test.sh` | `3022d090e4ef (61 l.)` | `248efa5d0631 (61 l.)` | `3022d090e4ef (61 l.)` | **différent** |
| `leaklog-test.sh` | `63b64f0d6df0 (82 l.)` | `055d29d6ca5f (92 l.)` | `2f500e83322b (92 l.)` | **différent** |
| `leaklog.sh` | `a79d106cb6b2 (70 l.)` | `a79d106cb6b2 (70 l.)` | `a79d106cb6b2 (70 l.)` | **identique** (3 sources) |
| `lib.sh` | `f78d2b129ecf (18 l.)` | `f78d2b129ecf (18 l.)` | `f78d2b129ecf (18 l.)` | **identique** (3 sources) |
| `lifeos-chain-test.sh` | — | — | `1f49a3fb51d7 (75 l.)` | **unique** (lifeos-ci-seed) |
| `lifeos-guard-test.sh` | — | — | `dfa13e636bc9 (69 l.)` | **unique** (lifeos-ci-seed) |
| `lifeos-guard.sh` | — | — | `992909b9491b (164 l.)` | **unique** (lifeos-ci-seed) |
| `livelog-test.sh` | `01f5c07a498b (143 l.)` | `74a228115cd5 (164 l.)` | `c509cf896be8 (164 l.)` | **différent** |
| `livelog.sh` | `52a7606a3ef8 (189 l.)` | `8592ea047602 (204 l.)` | `7cf5b455be3d (208 l.)` | **différent** |
| `memcap-livelog-test.sh` | `0bff9a33ec16 (63 l.)` | — | `0bff9a33ec16 (63 l.)` | **identique** (2 sources) |
| `memcap-test.sh` | `421798fa2294 (95 l.)` | — | `421798fa2294 (95 l.)` | **identique** (2 sources) |
| `merge-signed-carry-test.sh` | — | `7ef5d6f5897f (221 l.)` | `4374ae71e64e (221 l.)` | **différent** |
| `merge-signed-carry.sh` | — | `559f1a7ccc1b (269 l.)` | `559f1a7ccc1b (269 l.)` | **identique** (2 sources) |
| `notify-test.sh` | — | — | `9540d5157bb1 (97 l.)` | **unique** (lifeos-ci-seed) |
| `notify.sh` | — | — | `3d885d91b61d (68 l.)` | **unique** (lifeos-ci-seed) |
| `oc-deadline-test.sh` | `eba03dc58e23 (140 l.)` | `eba03dc58e23 (140 l.)` | `2bc5163e09d0 (140 l.)` | **différent** |
| `preannot-test.sh` | `10d91359aa2d (290 l.)` | — | `1e08dc6404da (290 l.)` | **différent** |
| `preannot.sh` | `686e1585d884 (338 l.)` | — | `40317d227e10 (340 l.)` | **différent** |
| `preflight-test.sh` | `6a635206d586 (144 l.)` | — | `3b456f7f6c58 (144 l.)` | **différent** |
| `progress.sh` | `8ab7bf8f98e3 (124 l.)` | `257d9c1e8ca7 (124 l.)` | `257d9c1e8ca7 (124 l.)` | **différent** |
| `prompt-contract-test.sh` | `d37ee3b7caf0 (86 l.)` | `d01e8f333ac9 (96 l.)` | `9a277ba4e02c (96 l.)` | **différent** |
| `quota-test.sh` | — | — | `4f142a72d0f7 (107 l.)` | **unique** (lifeos-ci-seed) |
| `quota.sh` | — | — | `a33023e0792f (225 l.)` | **unique** (lifeos-ci-seed) |
| `redact-log.sh` | `afafc1e213b1 (79 l.)` | `274df9e222a1 (72 l.)` | `afafc1e213b1 (79 l.)` | **différent** |
| `redact-test.sh` | `19d106649af7 (84 l.)` | — | `19d106649af7 (84 l.)` | **identique** (2 sources) |
| `run-all.sh` | — | — | `23a19fdecdec (95 l.)` | **unique** (lifeos-ci-seed) |
| `run-fullrun.sh` | `af0f9f89c23a (822 l.)` | `9016ef94020b (728 l.)` | `dafa081b3bb9 (827 l.)` | **différent** |
| `split-diff-test.sh` | `cc8a7eeb4822 (80 l.)` | `cc8a7eeb4822 (80 l.)` | `cc8a7eeb4822 (80 l.)` | **identique** (3 sources) |
| `split-diff.sh` | `8bc5b5cde390 (111 l.)` | `8bc5b5cde390 (111 l.)` | `8bc5b5cde390 (111 l.)` | **identique** (3 sources) |
| `stall-resume-test.sh` | `0f9a344b6ab2 (444 l.)` | `37325bd6c057 (442 l.)` | `1b465f3da981 (444 l.)` | **différent** |
| `start-step-test.sh` | `775628ef6378 (53 l.)` | `e5b8337dfadd (53 l.)` | `3212b83b081a (53 l.)` | **différent** |
| `step-agents.sh` | `f80f0aa15d91 (54 l.)` | — | `f80f0aa15d91 (54 l.)` | **identique** (2 sources) |
| `stop-after-step-test.sh` | `e3b144ee79d4 (257 l.)` | — | `865e8ecd7749 (257 l.)` | **différent** |
| `stop-step-target-agent-test.sh` | — | `f55a60087dbe (64 l.)` | `ed63cba540c7 (64 l.)` | **différent** |
| `subagent-fail-test.sh` | `6f9e0588c81c (67 l.)` | `6f9e0588c81c (67 l.)` | `6f9e0588c81c (67 l.)` | **identique** (3 sources) |
| `turn-end-test.sh` | `967ee27dc354 (122 l.)` | `56fc0687db83 (122 l.)` | `e287e9d5b6cc (122 l.)` | **différent** |
| `unit-contract-test.sh` | — | `4116f6b56f0a (145 l.)` | `474de53f948c (145 l.)` | **différent** |
| `watchdog-test.sh` | `fe753b0d040b (84 l.)` | `5027f602ed38 (87 l.)` | `5027f602ed38 (87 l.)` | **différent** |
| `wippush-test.sh` | `df14225a4adf (164 l.)` | `e1383bcec08f (176 l.)` | `9562e1787a9a (176 l.)` | **différent** |
| `wippush.sh` | `97e0dc2de590 (254 l.)` | `54307e994db6 (270 l.)` | `e58054e959fc (274 l.)` | **différent** |
| `with-emulators-test.sh` | — | `7d5a42cbfc23 (610 l.)` | `3f687c1b4838 (610 l.)` | **différent** |

### Totaux Étape A

- Noms de fichier distincts : **65**
- Instances de fichiers scannées : antenly-ci **42**, galass-ci **44**, lifeos-ci-seed **65** (total 151).
- Identiques (tous les shas présents égaux) : **13**
- Différents (au moins deux shas distincts) : **40**
- Présents dans une seule source : **12**

## Étape B — Fichiers différents (ou de rôle équivalent)

Une ligne par fichier différent : version à garder en priorité, puis ce qui manque aux autres.
La recommandation générale est de garder la version `lifeos-ci-seed` (déjà fusionnée et adaptée aux
chemins) ; les exceptions où une autre source est plus complète sont signalées explicitement.

### Lot 1 (fichiers 1 à 10)

- `agent-idle-test.sh` — À garder : **antenly/galass** (`a8e309d493f2`, 118 l.), identiques entre eux. La version seed (`99b8a38a222d`) n'est que le correctif de chemin `$HERE/../`→`$HERE/../../` ; aucun écart de test.
- `allowed-repos-cwd-test.sh` — À garder : **seed** (`a34cd87ad8fa`, 148 l.) ; seul écart avec galass (`d9b92a32e8a2`) : la profondeur de chemin (`/../`→`/../../`).
- `allowed-repos-test.sh` — À garder : **seed** (`3ac0f755c9fb`, 67 l.), version restaurée de galass + 10 l. d'assertions adaptées à lifeos-ci. galass (`75e67344837c`, 57 l.) n'a pas ces assertions supplémentaires.
- `autosave-test.sh` — À garder : **seed = galass** (`c44813c53195`, 190 l.) : liste de fichiers interdits actualisée (`.env`, credentials, google-services, keystores, secrets PSP). antenly (`e019782fe662`, 188 l.) teste l'ancienne liste (`keys.json`, corpus, evidence).
- `autosave.sh` — À garder : **seed = galass** (`26bcd9c93433`, 249 l.) : réintègre les enregistrements signés via `merge-signed-carry.sh` avant le commit `wip(carry)` + deny list galass. antenly (`2eaa914d11ca`, 239 l.) n'a pas la fusion des carry signés.
- `chain-step-test.sh` — À garder : **galass** (`18438fa309f6`, 485 l.), nettement plus complet : `start_step` jamais rejoué, `emu_inflight`, `chain_enabled=false`, borne à 25 inputs. seed/antonly (`301 l.`) n'ont pas ces cas → porter les extras dans le fichier seed (déjà adapté aux chemins).
- `checkpoint-watchdog-verdict-test.sh` — À garder : **seed** (`4e5c46d4c2d2`, 193 l.) : mêmes tests, noms d'environnement `TARGET_DIR`/`OC_MODEL_FALLBACK` attendus par le `run-fullrun` seed. antonly/galass utilisent `ANTENLY_DIR`/`OC_MODEL_CHAIN` ; aucun test manquant.
- `checkpoint.sh` — À garder : **seed** (`c17b75950428`, 202 l.) : `STATUS="done"` et `REPO` accepte `TARGET_DIR` puis `ANTENLY_DIR`. antonly/galass (`201 l.`) ne lisent que `ANTENLY_DIR`.
- `done-check-test.sh` — À garder : **seed = antonly** (`e048f4e5c3b6`, 800 l.) qui couvre le code actuel (`OC_DONE_AGENTS_ANY`, sans repli `REPORT.md`). galass (`480c9fd841b5`, 790 l.) contient les cas 9e/9f du repli `REPORT.md` que le `done_check.sh` seed n'implémente pas → à porter avec la fonctionnalité, sinon ils échouent.
- `done_check.sh` — À garder : **seed = antonly** (`1a6a42108cb4`, 389 l.) : `OC_DONE_AGENTS_ANY` + `OC_DONE_ONLY`. galass (`478489ea9637`, 348 l.) possède en plus le repli automatique `REPORT.md` absent de seed → candidat à porter (avec ses tests 9e/9f).

### Lot 2 (fichiers 11 à 20)

- `extra-repos-test.sh` — À garder : **seed** (`8dafc0f57687`, 436 l.) = galass + profondeur de chemin. Aucun test manquant.
- `extra-repos.sh` — À garder : **seed** (`57f2d8cebc8a`, 480 l.) : cherche `allowed-repos.sh` dans `opencode/` puis `../targets/`, `set +e` après le source. galass (`978399e958d2`, 476 l.) ne regarde que `opencode/allowed-repos.sh`.
- `ffmpeg-install-test.sh` — À garder : **seed** (`559a95187587`, 41 l.) = antonly + profondeur de chemin (`../../..`). Aucun écart fonctionnel.
- `first-link-prompt-test.sh` — À garder : **seed ≈ antonly** (`147 l.`) : vérifie le rc de `prep`, `IN_CHAIN_PROGRESS`, noms d'environnement récents. galass (`c5e657464170`, 148 l.) utilise `IN_CHAIN_COUNT`/`OC_MODEL_FALLBACK` et ne teste pas le rc.
- `hmac-state-test.sh` — À garder : **seed = galass** (`de9f9db80da7`, 319 l.) : ~49 l. de cas supplémentaires. antonly (`6b1f78d363f3`, 270 l.) n'a pas ces assertions (signature/clé ISA).
- `hook-profile-install-test.sh` — À garder : **seed** (`e2bd67e2032f`, 98 l.) = antonly/galass + profondeur de chemin. Identique fonctionnellement.
- `install-hook-profile.sh` — À garder : **seed = galass** (`080e532c3b38`, 94 l.) : le refus est aussi écrit sur `stderr` (lisible par les appelants et les tests). antonly (`c288bbe74040`, 92 l.) n'émet que l'annotation `::error::` sur stdout.
- `internals-test.sh` — À garder : **seed = antonly** (`3022d090e4ef`, 61 l.) : env `ANTENLY_DIR`/`OC_MODEL_CHAIN`. galass (`248efa5d0631`) utilise `TARGET_DIR`/`OC_MODEL_FALLBACK` ; aucun test manquant.
- `leaklog-test.sh` — À garder : **seed = galass** (`2f500e83322b`, 92 l.) : fabrique une paire `age` jetable pour vérifier le déchiffrement partout. antonly (`63b64f0d6df0`, 82 l.) dépend de la clé privée de la box (`~/.config/age/fullrun-logs.key`) et ne peut pas déchiffrer en CI.
- `livelog-test.sh` — À garder : **seed = galass** (`c509cf896be8`, 164 l.) : ~21 l. de cas en plus vs antonly (`01f5c07a498b`, 143 l.).

### Lot 3 (fichiers 21 à 30)

- `livelog.sh` — À garder : **seed** (`7cf5b455be3d`, 208 l.) : `REMOTE` dérivé de `TARGET_REPO` via `allowed-repos.sh`, jeton `GALASS_TOKEN`, commit `galass.local`. galass (`8592ea047602`, 204 l.) est proche ; antonly (`52a7606a3ef8`, 189 l.) reste figé sur antenly.
- `merge-signed-carry-test.sh` — À garder : **seed** (`4374ae71e64e`, 221 l.) = galass + profondeur de chemin. Aucun écart fonctionnel.
- `oc-deadline-test.sh` — À garder : **seed** (`2bc5163e09d0`, 140 l.) ; antonly et galass (`eba03dc58e23`) sont identiques, seed n'ajoute qu'un correctif de profondeur de chemin.
- `preannot-test.sh` — À garder : **seed** (`1e08dc6404da`, 290 l.) = antonly + profondeur `../../..`. Aucun écart.
- `preannot.sh` — À garder : **seed** (`40317d227e10`, 340 l.) : 2 commentaires `shellcheck` (`SC2016`, `SC2154`) en plus. antonly (`686e1585d884`, 338 l.) est sinon identique.
- `preflight-test.sh` — À garder : **seed** (`3b456f7f6c58`, 144 l.) = antonly + profondeur de chemin. Aucun écart.
- `progress.sh` — À garder : **seed = galass** (`257d9c1e8ca7`, 124 l.) : utilise `TARGET_DIR`, nom préféré du `run-fullrun` seed. antonly (`8ab7bf8f98e3`) utilise `ANTENLY_DIR` ; fonctionnellement identique.
- `prompt-contract-test.sh` — À garder : **seed = galass** (`9a277ba4e02c`, 96 l.) : section B et substitution multi-variables. antonly (`d37ee3b7caf0`, 86 l.) est l'ancienne version (section 5.D, six variables).
- `redact-log.sh` — À garder : **seed = antonly** (`afafc1e213b1`, 79 l.) : masque aussi les noms de fichiers du corpus audio (faux positifs `generic-api-key` de gitleaks). galass (`274df9e222a1`, 72 l.) ne les masque pas.
- `run-fullrun.sh` — À garder : **seed** (`dafa081b3bb9`, 827 l.) : accepte `TARGET_DIR` et `ANTENLY_DIR`, source `allowed-repos`, gère `stop_after_step`/`target_agent`, versions de boucle les plus récentes. antenly (`af0f9f89c23a`, 822 l.) n'accepte que `ANTENLY_DIR` ; galass (`9016ef94020b`, 728 l.) est plus ancien.

### Lot 4 (fichiers 31 à 40)

- `stall-resume-test.sh` — À garder : **seed ≈ antonly** (`1b465f3da981`, 444 l.) : env `ANTENLY_DIR`/`OC_MODEL_CHAIN` (compatibles seed), cas de repli simple. galass (`37325bd6c057`, 442 l.) utilise `TARGET_DIR`/`OC_MODEL_FALLBACK`.
- `start-step-test.sh` — À garder : **seed** (`3212b83b081a`, 53 l.) = meilleure version + profondeur (`../../..`). Aucun écart fonctionnel.
- `stop-after-step-test.sh` — À garder : **seed** (`865e8ecd7749`, 257 l.) = antonly + profondeur de chemin.
- `stop-step-target-agent-test.sh` — À garder : **seed** (`ed63cba540c7`, 64 l.) = galass + profondeur de chemin.
- `turn-end-test.sh` — À garder : **seed ≈ antonly** (`e287e9d5b6cc`, 122 l.) : env `ANTENLY_DIR`/`OC_MODEL_CHAIN`. galass (`56fc0687db83`) utilise `TARGET_DIR`/`OC_MODEL_FALLBACK`.
- `unit-contract-test.sh` — À garder : **seed** (`474de53f948c`, 145 l.) = galass + profondeur de chemin.
- `watchdog-test.sh` — À garder : **seed = galass** (`5027f602ed38`, 87 l.) : accepte `passage interrompu` selon coreutils 9.4 et vérifie réellement la relance. antonly (`fe753b0d040b`, 84 l.) exige le texte exact `relance`, instable sur runner.
- `wippush-test.sh` — À garder : **seed = galass** (`9562e1787a9a`, 176 l.) : ~12 l. de cas en plus vs antonly (`df14225a4adf`, 164 l.).
- `wippush.sh` — À garder : **seed** (`e58054e959fc`, 274 l.) : `REMOTE` dérivé de `TARGET_REPO`/liste blanche via `allowed-repos.sh`, garde-fous. galass (`54307e994db6`, 270 l.) est proche ; antonly (`97e0dc2de590`, 254 l.) reste figé sur antenly.
- `with-emulators-test.sh` — À garder : **seed** (`3f687c1b4838`, 610 l.) = galass + profondeur de chemin.

### Fichiers de noms différents mais de même rôle

- Aucun couple renommé détecté : tous les tests et outils partagés portent le même nom de fichier
  d'une source à l'autre (les écarts sont des versions, pas des renommages).
- Seule collision de nom dans le seed : `opencode/allowed-repos.sh` (bibliothèque sourcée, 27 l.,
  `67623897a7ff`) et `targets/allowed-repos.sh` (CLI, 105 l., `5e889d46ef8f`). Même nom, rôles
  différents : ne pas fusionner ; le CLI `targets/` est un sur-ensemble fonctionnel (liste plus
  large, `validate`/`normalize_extra_repos`).

### Doublons dans `lifeos-ci-seed/`

- **Aucun doublon de contenu interne** : sur les 66 scripts `*.sh/*.ts/*.py` du seed (65 dans le
  périmètre `opencode/` + `targets/allowed-repos.sh`), aucun sha256 n'apparaît deux fois.
- **Aucun doublon de nom de base** dans `opencode/` ; la seule collision est `allowed-repos.sh`
  (`opencode/` vs `targets/`), aux rôles distincts.
- **21 scripts distincts (27 instances) sont des copies octet pour octet d'un fichier upstream**
  (doublons délibérés de la graine) :
  - identiques à antenly **et** galass : `done-check-call.sh`, `leaklog.sh`, `lib.sh`,
    `split-diff-test.sh`, `split-diff.sh`, `subagent-fail-test.sh` ;
  - identiques à antenly seul : `done_check.sh`, `internals-test.sh`, `memcap-livelog-test.sh`,
    `memcap-test.sh`, `redact-log.sh`, `redact-test.sh`, `step-agents.sh` ;
  - identiques à galass seul : `allowed-repos.sh`, `autosave-test.sh`, `autosave.sh`,
    `emu-e2e.sh`, `install-hook-profile.sh`, `merge-signed-carry.sh`, `progress.sh`,
    `watchdog-test.sh`.
- Les 25 fichiers de `opencode/tests/upstream-fullrun/` sont des copies **relocalisées** de tests
  upstream (écart limité à la profondeur de chemin `../`→`../../`, plus quelques versions plus
  récentes prises à galass : `hmac-state`, `leaklog`, `livelog`, `prompt-contract`, `watchdog`,
  `wippush`). Ils ne doublonnent aucun test plat du seed (aucun nom de base commun avec
  `opencode/tests/`).

## Synthèse

- Noms de fichier : **65** ; instances scannées : **151**.
- Identiques (tous shas présents égaux) : **13** ; différents : **40** ; uniques à une source : **12**.
- Doublons internes de contenu dans le seed : **0** ; collision de nom : **1** (`allowed-repos.sh`,
  rôles distincts) ; copies octet pour octet d'upstream : **21** scripts (27 instances).
- Base recommandée : **seed** (fusion la plus complète et adaptée aux chemins).
  À porter depuis galass : les cas supplémentaires de `chain-step-test.sh` et le repli
  `REPORT.md` (`done_check.sh` + tests 9e/9f de `done-check-test.sh`).

---

# Workflows et steps — antenly-ci / galass-ci / lifeos-ci-seed

- Date : 2026-11-25
- Branche : `seed/lifeos-ci-2026-11-24`
- Périmètre : fichiers `.github/workflows/*.yml` des trois sources.
- Sources : `antenly-ci` = dépôt courant (`.`), `galass-ci` = clone `/tmp/galass-ci`
  (`https://github.com/LordThiouk/galass-ci`, profondeur 1), `lifeos-ci-seed` = `lifeos-ci-seed/`.
- Exclus des recherches : `node_modules`, `.git`, `dist`, `build`, `.venv`.
- Méthode : extraction des lignes `- name:` (numéro de ligne + libellé). `rg` étant absent du
  runner, l'extraction a été faite avec `grep -nE '^[[:space:]]+- name:'` puis `sed` ; résultat
  consigné dans `/tmp/steps.txt`. Les steps `uses:` sans `name:` (checkout, setup-bun, etc.) ne
  sont donc **pas** comptés ; ils sont signalés à part quand ils créent un doublon de rôle.

## Étape A — table de correspondance par fichier de workflow

| Workflow | antenly-ci | galass-ci | lifeos-ci-seed | Rôle / remarque |
|---|---|---|---|---|
| `opencode-fullrun.yml` | 32 steps | 33 steps | 32 steps | FullRun monolithique (même lignée antenly→seed) |
| `opencode-task.yml` | 16 steps | 12 steps | — | Tâche simple ; remplacé dans le seed par `task.yml` + `_agent-run.yml` |
| `ci.yml` | 16 steps | 5 steps | 14 steps | **Rôles différents** : antenly = CI de l'app (Postgres/RLS/preannot) ; galass = tests opencode ; seed = shellcheck/actionlint + tests shell |
| `ci-scripts.yml` | 5 steps | — (rôle assuré par `ci.yml`) | 5 steps | Tests opencode ; antenly et seed sont **identiques** |
| `isa-human-tick.yml` | 7 steps | 9 steps | — | human-tick / human-verify |
| `_agent-run.yml` | — | — | 15 steps | Moteur réutilisable appelé par `task.yml` et `fr-*.yml` |
| `_next.yml` | — | — | 1 step | Chaînage vers le prochain agent |
| `fr-plan-vera.yml` | — | — | 0 step local | Wrapper : délègue à `_agent-run.yml` puis `_next.yml` |
| `task.yml` | — | — | 0 step local | Wrapper : délègue à `_agent-run.yml` |
| `inventory-pass2.yml` | 11 steps | — | — | Inventaire (spécifique antenly) |
| `inventory-probe.yml` | 13 steps | — | — | Inventaire (spécifique antenly) |
| `language.yml` | 17 steps | — | — | Détection de parole (spécifique antenly) |
| `pr-dispatch.yml` | 1 step | — | — | Redispatch CI (spécifique antenly) |
| **Total** | **118 steps / 9 fichiers** | **59 steps / 4 fichiers** | **67 steps / 7 fichiers** | |

### Steps présents dans une seule source (même nom de workflow)

Comparaison par **nom exact** de step. Un step présent une seule fois parmi les sources qui
possèdent le fichier est listé ci-dessous.

- `ci-scripts.yml` (antenly, seed) : **aucun step unique** — les deux fichiers sont identiques.
- `opencode-fullrun.yml` (antenly, galass, seed) :
  - antenly : aucun ;
  - seed : aucun ;
  - galass (8) : `Garde du secret GALASS_TOKEN`, `Checkout galass-ci`,
    `Valider target_repo et extra_repos (liste blanche unique)`,
    `Checkout du dépôt cible (lecture seule)`, `Checkout des dépôts supplémentaires`,
    `Préparer le dépôt cible et le prompt`,
    `Contrôles et push des dépôts supplémentaires (jamais main, jamais force)`,
    `PR en brouillon des dépôts supplémentaires (jamais fusionnées)`.
    → Ce sont les steps **extra_repos** + **jeton/validation** propres à galass, absents du
    fullrun antenly/seed.
- `opencode-task.yml` (antenly, galass) :
  - antenly (11) : `Checkout du dépôt cible (branche)`,
    `Checkout acr-senegal en lecture seule (cible antenly)`,
    `Préparer acr-senegal (branches + lecture seule)`, `Préparer prompt et SHA de départ`,
    `Installer Node, Python/uv, opencode et gitleaks`, les deux steps ffmpeg,
    `Vérifier ffmpeg et ffprobe`, `Installer la CLI Hugging Face (cible antenly)`,
    `Télécharger le corpus HF (cible antenly, optionnel)`,
    `Contrôle gitleaks et push fast-forward` ;
  - galass (7) : `Garde du secret GALASS_TOKEN`, `Checkout galass-ci`,
    `Valider target_repo (liste blanche unique)`, `Checkout du dépôt cible (lecture seule)`,
    `Préparer le prompt et le SHA de départ`,
    `Installer opencode et gitleaks (épinglés, sha256 vérifié)`,
    `Contrôle gitleaks et push en avance rapide`.
- `isa-human-tick.yml` (antenly, galass) :
  - antenly (1) : `gitleaks (diff de ce tick uniquement)` ;
  - galass (3) : `Checkout galass-ci (allowed-repos.sh)`,
    `Valider target_repo (liste blanche unique)`,
    `gitleaks (diff de ce tick uniquement, épinglé, sha256 vérifié)`.
- `ci.yml` (antenly, galass, seed) : les trois fichiers n'ont pas le même rôle, la comparaison
  par nom est donc peu significative :
  - antenly (12) : `Statut pending sur le commit antenly`, `ffmpeg/ffprobe présents avant pytest`,
    `Audit de sécurité interne (ISC-27)`, `Pile de dev (Postgres 16.4, ClickHouse 24.8, SeaweedFS 3.80)`,
    `Migrations (...)`, `Sondes d'intégration RLS (...)`, `Arrêt de la pile`,
    `Pipeline preannot présent ?`, `Dépendances ina + TensorFlow CPU`,
    `test_preannot_pipeline.py avec le vrai segmenteur`, `Python licences (deny GPL/AGPL)`,
    `Statut sur le commit antenly` ;
  - galass (2) : `Tests opencode`, `gitleaks detect (épinglé, sha256 vérifié)` ;
  - seed (9) : `Checkout`, `Installer ShellCheck si absent`, `ShellCheck`,
    `Installer ripgrep (tests shell)`, `Installer actionlint (binaire officiel épinglé)`,
    `Actionlint`, `Setup bun (épinglé par SHA)`, `Vérifier ffmpeg et ffprobe`, `Tests shell`.

### Workflows présents dans une seule source

- antenly uniquement : `inventory-pass2.yml`, `inventory-probe.yml`, `language.yml`,
  `pr-dispatch.yml`.
- seed uniquement : `_agent-run.yml`, `_next.yml`, `fr-plan-vera.yml`, `task.yml`.
- Aucun workflow unique à galass (ses 4 fichiers ont un équivalent de nom dans les autres sources).

## Étape B — workflows de même rôle

### `opencode-fullrun.yml` — FullRun monolithique

**Base à garder : `lifeos-ci-seed/.github/workflows/opencode-fullrun.yml`** (32 steps).
C'est la version de la lignée antenly la plus récente et la plus sûre : elle ajoute au fullrun
antenly la gestion d'un état `has_state=true` dont le téléchargement échoue (arrêt de chaîne au
lieu d'un cold start silencieux), l'avertissement si la suppression de l'artefact d'état échoue,
l'assainissement `safe_raw` des raisons de chaînage, et les contrôles `m1`/`m2`/`m4` (valeurs
`.next` par phase, `isa_path` re-validé, valeurs loggées assainies). Elle source aussi
`allowed-repos.sh` depuis `/opt/fullrun-tools` avant push/PR.

À porter depuis **galass** (steps/entrées absents du fullrun seed) :

- `with_emulators` (entrée `boolean`, défaut `false`) + env `WITH_EMULATORS` + `IN_WITH_EMU` ;
- préparation e2e dans « Outils de contrôle figés » : jeton `GALASS_TOKEN` root `0600` dans
  `/opt/fullrun-live/emu-e2e.token`, fichier `emu-run`/`emu-resume`, état `emu-e2e.state`, et
  sudoers dédié `/etc/sudoers.d/fullrun-emu-e2e` (sous-ensemble strict de `emu-e2e.sh`) ;
- `Garde du secret` (galass : `GALASS_TOKEN` ; à adapter en `CI_TOKEN` pour lifeos-ci) ;
- `Valider target_repo et extra_repos (liste blanche unique)` ;
- `Checkout du dépôt cible (lecture seule)` et `Checkout des dépôts supplémentaires` ;
- `Contrôles et push des dépôts supplémentaires (jamais main, jamais force)` ;
- `PR en brouillon des dépôts supplémentaires (jamais fusionnées)`.

À noter : le fullrun seed reste **figé sur antenly** (`Checkout antenly`,
`Checkout antenly-ci`, corpus HF « cible antenly », secrets `ANTENLY_TOKEN`,
`ANTENLY_PUSH_TOKEN`, `ANTENLY_CI_DISPATCH_TOKEN`) ; il n'est pas encore générique lifeos-ci.
La version galass est, elle, générique (dépôt cible + dépôts supplémentaires).

### `opencode-task.yml` → `task.yml` + `_agent-run.yml`

**Base à garder : `lifeos-ci-seed/.github/workflows/_agent-run.yml` (15 steps) + le wrapper
`task.yml`.** C'est la seule version générique (dépôt cible + `extra_repos` + `lifeos_write`),
réutilisable par `task.yml` et par les `fr-*.yml`, avec quota, garde-fou lifeos, gitleaks épinglé,
`--redact`, `merge-base --is-ancestor`, push en copie nue `env -i`, `--no-verify` et PR brouillon.
Le wrapper `task.yml` (0 step local) ne fait que transmettre les entrées à `_agent-run.yml`.

À porter depuis **antenly** (`opencode-task.yml`) :

- `ffmpeg (binaire statique, sans miroirs Ubuntu)` + `ffmpeg (secours apt)` +
  `Vérifier ffmpeg et ffprobe` ;
- `Installer la CLI Hugging Face (cible antenly)` et
  `Télécharger le corpus HF (cible antenly, optionnel)` ;
- `Checkout acr-senegal en lecture seule` + `Préparer acr-senegal (branches + lecture seule)`
  (uniquement si la cible antenly reste supportée) ;
- installation explicite de Node/Python/uv (`Installer Node, Python/uv, opencode et gitleaks`),
  le seed ne fait qu'un `npm install -g opencode-ai` en supposant Node présent sur le runner.

À porter depuis **galass** (`opencode-task.yml`) :

- refus explicite des modifications `.github/workflows` avant push (galass l. 326-327) : c'est
  la seule protection de la porte gitleaks encore absente de `_agent-run.yml` ;
- `Garde du secret` (galass : `GALASS_TOKEN` ; à décliner en `CI_TOKEN`).

Défauts constatés dans le seed, à corriger avec ce lot :

- `_next.yml` dispatche `-f lifeos_write="$LIFEOS_WRITE"` alors que l'entrée est `type: boolean`
  (il faut `-F`) ;
- `task.yml` et `fr-plan-vera.yml` dupliquent le même schéma d'entrées et ne diffèrent que par
  `agent:` et le bloc `next` : un seul wrapper paramétré suffirait ;
- `fr-plan-vera.yml` conditionne l'enchaînement à `needs.vera.outputs.status == 'ok'` sans
  vérifier `needs.vera.result == 'success'`.

### `ci.yml` et `ci-scripts.yml`

Le nom `ci.yml` recouvre **trois rôles différents** ; il ne faut pas les fusionner :

- antenly `ci.yml` (16 steps) = CI de l'application antenly : pile Postgres/ClickHouse/SeaweedFS,
  migrations, sondes RLS, pipeline preannot, licences Python. Sans équivalent dans le seed :
  à conserver tel quel pour la cible antenly, pas un candidat à la fusion.
- galass `ci.yml` (5 steps) = tests des scripts opencode + `gitleaks detect` épinglé.
- seed `ci.yml` (14 steps) = shellcheck + actionlint + bun + ffmpeg + tests shell.

**Base à garder pour la CI « scripts » : `lifeos-ci-seed/.github/workflows/ci.yml`** (superset
lint/shell) **et `lifeos-ci-seed/.github/workflows/ci-scripts.yml`** (tests opencode), qui est
**identique à antenly `ci-scripts.yml`** (5 steps, aucun step unique).

À porter depuis **galass `ci.yml`** :

- `gitleaks detect (épinglé, sha256 vérifié)` — absent de `ci-scripts.yml` (le seed n'a pas de
  porte de secrets sur les tests opencode).

À porter depuis le **seed `ci.yml`** :

- remplacer `secrets.LIFEOS_READ_TOKEN` par `secrets.CI_TOKEN` dans `ci-scripts.yml` (l. 46) :
  le seed a déjà migré `ci.yml` (l. 36) et `_agent-run.yml` (`CI_TOKEN`) ; `ci-scripts.yml` est
  le dernier fichier resté sur l'ancien jeton.

**Doublons internes au seed entre `ci.yml` et `ci-scripts.yml`** (les deux se déclenchent sur
`pull_request` et `push`) :

- `Checkout LifeOS (lecture seule, CLI de verdict)` : deux fois ;
- `Installer age (épinglé, sha256 vérifié)` : deux fois (plus une troisième dans
  `opencode-fullrun.yml`) ;
- installation de `ripgrep` : deux fois (`Installer ripgrep` / `Installer ripgrep (tests shell)`),
  plus une troisième dans `opencode-fullrun.yml` ;
- `Marqueur root du mode test (suite de tests seulement)` : deux fois ;
- `setup-bun` (via `uses:`, non nommé dans `ci-scripts.yml`) : deux fois ;
- tests `shell` vs `opencode` : deux jobs qui partagent tout le socle d'installation.

Recommandation : garder un seul workflow CI (ou deux workflows mais un job commun) et y fondre
les steps communs ; le commentaire d'en-tête de `ci-scripts.yml` (« Distinct de ci.yml, qui teste
antenly lui-même ») est d'ailleurs **faux dans le seed**, où `ci.yml` teste aussi les scripts.

### `isa-human-tick.yml`

**Base à garder : `galass-ci/.github/workflows/isa-human-tick.yml`** (9 steps). C'est la version
la plus complète et la plus sûre.

À porter depuis **galass** (absents d'antenly) :

- `Checkout galass-ci (allowed-repos.sh)` — le checkout des outils de la liste blanche
  (à décliner en `Checkout lifeos-ci` pour le seed) ;
- `Valider target_repo (liste blanche unique)` avant tout checkout de la cible ;
- `gitleaks (diff de ce tick uniquement, épinglé, sha256 vérifié)` — antenly n'épingle pas le
  binaire (`gitleaks (diff de ce tick uniquement)`, sans sha256).

Le seed ne contient **pas** `isa-human-tick.yml` : si lifeos-ci doit garder le human-tick, le
porter depuis galass. Le jeton de push cible de galass est `GALASS_TOKEN` ; pour lifeos-ci,
utiliser `CI_TOKEN` (comme `_agent-run.yml`) et garder `LIFEOS_READ_TOKEN` uniquement pour le
checkout en lecture du dépôt lifeos.

### Points de sécurité : `with_emulators`, sudoers et jetons

- **`with_emulators` n'existe que dans galass** : entrée `boolean` (`opencode-fullrun.yml` l. 100),
  env `WITH_EMULATORS` (l. 196), bloc de préparation e2e (l. 820-850). Absent d'antenly et du seed.
- **Sudoers** : le fullrun antenly **et** seed posent `/etc/sudoers.d/fullrun-preannot`
  (une seule commande `preannot`, `env_reset`, `secure_path` strict). Galass ajoute
  `/etc/sudoers.d/fullrun-emu-e2e` (sous-ensemble `emu-e2e.sh run|resolve-refs|status *`) pour
  `with_emulators`. Le seed n'a donc **que** le sudoers preannot.
- **Référence morte dans le seed** : `opencode-fullrun.yml` l. 2027 teste `IN_WITH_EMU`, mais ni
  l'entrée `with_emulators` ni l'env `WITH_EMULATORS`/`IN_WITH_EMU` n'existent dans le fichier
  seed. La branche emu est donc toujours fausse et l'identifiant de run e2e n'est jamais
  persistant dans l'état de chaînage : fonctionnalité perdue à la copie depuis galass.
- **Jeton de `ci-scripts.yml`** : `secrets.LIFEOS_READ_TOKEN` (l. 46) → à remplacer par
  `secrets.CI_TOKEN`. Le seed utilise déjà `CI_TOKEN` dans `ci.yml` (l. 36), `_agent-run.yml`
  (garde l. 156, push l. 522) et `_next.yml` (l. 79).
- **Jetons du fullrun seed** : encore spécifiques antenly (`ANTENLY_TOKEN`, `ANTENLY_PUSH_TOKEN`,
  `ANTENLY_CI_DISPATCH_TOKEN`, plus `LIFEOS_READ_TOKEN`) ; galass utilise `GALASS_TOKEN` pour la
  cible. Pour lifeos-ci, converger vers `CI_TOKEN` (cible) + `LIFEOS_READ_TOKEN` (lecture lifeos).
- Les jetons restent hors d'opencode : fichiers root `0600` (`/opt/fullrun-live/…`), `env -i`,
  `::add-mask::` de l'en-tête base64. Ne pas réintroduire de jeton dans l'étape opencode.

## Synthèse Workflows et steps

- **Volumes** : antenly 118 steps / 9 workflows ; galass 59 / 4 ; seed 67 / 7.
- **Bases recommandées par rôle** :
  - FullRun monolithique : **seed** `opencode-fullrun.yml`, + `with_emulators`/sudoers
    `fullrun-emu-e2e`, `extra_repos` (validation, checkout, push, PR) et jeton générique
    `CI_TOKEN` venus de galass ;
  - tâche simple : **seed** `_agent-run.yml` + `task.yml`, + ffmpeg/corpus HF/acr-senegal
    d'antenly et refus `.github/workflows` de galass ;
  - CI scripts : **seed** `ci.yml` + `ci-scripts.yml` fusionnés, + `gitleaks detect` de galass,
    et `LIFEOS_READ_TOKEN` → `CI_TOKEN` ;
  - human-tick : **galass** `isa-human-tick.yml` (validation liste blanche + gitleaks épinglé).
- **Doublons internes au seed** :
  - deux moteurs FullRun complets (`opencode-fullrun.yml` vs `_agent-run.yml` + `fr-plan-vera.yml`
    + `_next.yml`) qui dupliquent checkout cible, clone lifeos, installation opencode,
    configuration, exécution, porte gitleaks/push/PR, notification et statut final ;
  - `ci.yml` et `ci-scripts.yml` dupliquent checkout LifeOS, installation `age`, `ripgrep`,
    `setup-bun` et marqueur root (et se déclenchent tous deux sur PR/push) ;
  - `age` est installé 3 fois (ci, ci-scripts, fullrun) et `ripgrep` 3 fois ; ffmpeg
    statique+apt est dupliqué entre `ci.yml` et `opencode-fullrun.yml` ;
  - `task.yml` et `fr-plan-vera.yml` dupliquent le schéma d'entrées (un seul wrapper paramétré
    suffirait).
- **Cap de convergence** : garder `opencode-fullrun.yml` (seed) comme base FullRun tant que
  `_agent-run.yml` n'a pas rattrapé l'état de chaînage, le corpus HF, le journal chiffré et le
  sudoers preannot ; utiliser `_agent-run.yml` pour les tâches simples ; supprimer l'un des deux
  moteurs ensuite.


