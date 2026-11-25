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

