# REPORT — amorçage du socle `LordThiouk/lifeos-ci`

Date : 2026-11-24. Branche : `seed/lifeos-ci-2026-11-24` (dépôt `antenly-ci`).
Tout le contenu ci-dessous est destiné à être copié tel quel à la racine de
`lifeos-ci` (le dossier `lifeos-ci-seed/` disparaît).

## Fichiers repris et destinations

| Source | Destination dans `lifeos-ci-seed/` | Décision |
| --- | --- | --- |
| `galass-ci/opencode/allowed-repos.sh` | `targets/allowed-repos.sh` | Repris et étendu à la liste blanche LordThiouk (9 dépôts), validation stricte (`^[A-Za-z0-9._-]+$`, pas de `..`), CLI `list/check/validate`, normalisation des `extra_repos` (virgules et espaces, doublons refusés). |
| `antenly-ci/opencode/run-fullrun.sh` (gestion 429 / `FreeUsageLimitError`) + `opencode-task.yml` (`model_main` / `model_chain`) | `opencode/quota.sh` + `models.txt` | Détection unifiée : journal interne + lignes d'erreur réelles uniquement ; diffs et blocs de code ignorés ; une seule bascule dans `_agent-run.yml`. Liste des modèles reprise de l'ordre actuel d'antenly-ci. |
| `antenly-ci/.github/workflows/opencode-task.yml` (notification de fin) | `opencode/notify.sh` | Extrait en script unique, JSON `jq`, en-têtes `Authorization` + `X-Automation-Key`, `--max-time 15`, jamais bloquant. |
| `galass-ci/opencode/extra-repos.sh` (mode `target_repo` / `extra_repos`) | `.github/workflows/_agent-run.yml` | Le mode de sélection et le checkout des dépôts supplémentaires sont intégrés au workflow réutilisable ; la validation reste centralisée dans `targets/allowed-repos.sh`. |
| `antenly-ci/.github/workflows/opencode-task.yml` (validation, checkout, installation opencode 1.19.4, gitleaks, push fast-forward) | `.github/workflows/_agent-run.yml` | Logique commune factorisée une seule fois ; ajout du clone lifeos lecture seule, du garde-fou, des PR brouillon et des sorties `status`/`model`/`head_sha`. |
| `galass-ci/.github/workflows/opencode-task.yml` + `opencode-fullrun.yml` (inputs et liste blanche) | `.github/workflows/task.yml`, `fr-plan-vera.yml`, `_next.yml` | `target_repo` en `choice` aligné sur la liste blanche ; `extra_repos`, `lifeos_write`, `branch`, `prompt_path`, `isa_path`, `job_name`, `lifeos_ref`, `timeout_minutes`. |
| `galass-ci/.github/workflows/ci.yml` + `antenly-ci/.github/workflows/ci-scripts.yml` | `.github/workflows/ci.yml` | Tests shell + `shellcheck` + `actionlint` épinglé. |
| (nouveau) | `opencode/lifeos-guard.sh` | Garde-fou `lifeos_write` (destination, lecture seule, main/master). |
| (nouveau) | `opencode/tests/*.sh` | Tests sans réseau ni secret ; `run-all.sh` renvoie un code non nul si un test échoue. |
| `antenly-ci` chaîne de modèles par défaut | `models.txt` | Une seule copie, ordre de priorité conservé, uniquement des `opencode/*-free`. |
| (nouveau) | `README.md` | Rôle, modes, inputs, règles `lifeos_write`, quota. |

## Décisions de fusion

- Une seule liste blanche, dans `targets/allowed-repos.sh` : les options
  `target_repo` des workflows publics sont alignées dessus et un test le vérifie.
- Aucun script dupliqué : `_agent-run.yml` porte la logique commune ; `task.yml`
  et `fr-plan-vera.yml` ne font que transmettre les inputs.
- `lifeos_write=false` est le défaut ; lifeos est cloné en lecture seule et le
  remote est remis à une URL sans identifiants. `lifeos_write=true` n'autorise
  qu'une branche de fonctionnalité (jamais `main`/`master`).
- Quota : une seule bascule par run. Si le modèle de secours est aussi épuisé,
  le statut devient `quota` et `_next.yml` ne déclenche aucun lien.
- Enchaînement : `vera → serena → engineer → anvil → forge-code → aditi-ui →
  forge-audit → silas → code-review → max`. Le lien suivant n'est lancé que si le
  statut est `ok` et que le fichier `fr-<phase>-<agent>.yml` existe.
- `actionlint` a été lancé depuis une copie du dossier à la racine du futur dépôt
  (le dossier `lifeos-ci-seed/` est imbriqué dans `antenly-ci`, ce qui fausse la
  résolution des `uses: ./.github/workflows/...`). Dans le futur dépôt, la commande
  exacte est `actionlint .github/workflows/*.yml`.

## Sorties brutes

### `bash opencode/tests/run-all.sh`

```text
$ bash opencode/tests/run-all.sh
==> allowed-repos-test.sh
PASS allowed-repos-test : 28 cas
<== ok allowed-repos-test.sh
==> lifeos-guard-test.sh
PASS lifeos-guard-test : 23 cas
<== ok lifeos-guard-test.sh
==> quota-test.sh
PASS quota-test : 8 cas
<== ok quota-test.sh
PASS : 3 suite(s) de tests
exit=0
```

### `shellcheck` (version 0.11.0)

```text
$ shellcheck -x opencode/*.sh targets/*.sh
exit=0
```

### `actionlint` (version 1.7.7)

```text
$ actionlint .github/workflows/*.yml   # depuis une copie à la racine du futur dépôt
exit=0
```

## Contrôles complémentaires

- Aucun secret, aucune fausse clé ; aucune référence à `antenly-ci` comme dépôt
  d'exécution (il ne reste que l'option de cible et la liste blanche).
- Aucun fichier modifié hors de `lifeos-ci-seed/`.
- Scripts exécutables (`chmod +x`) et en `set -euo pipefail`.

## Fix1 (2026-11-25)

Correctifs du socle : notification qui remonte le code HTTP (sans avaler l'erreur),
transmission complète de `lifeos_write` dans la chaîne FullRun, et écriture LifeOS
sur une branche dédiée poussée par le workflow puis ouverte en PR brouillon.

### `bash opencode/tests/run-all.sh`

```text
$ bash opencode/tests/run-all.sh
==> allowed-repos-test.sh
PASS allowed-repos-test : 28 cas
<== ok allowed-repos-test.sh
==> lifeos-chain-test.sh
PASS lifeos-chain-test : 23 cas
<== ok lifeos-chain-test.sh
==> lifeos-guard-test.sh
PASS lifeos-guard-test : 23 cas
<== ok lifeos-guard-test.sh
==> notify-test.sh
PASS notify-test : 21 cas
<== ok notify-test.sh
==> quota-test.sh
PASS quota-test : 8 cas
<== ok quota-test.sh
PASS : 5 suite(s) de tests
exit=0
```

### `shellcheck` (version 0.11.0)

```text
$ shellcheck -x opencode/*.sh targets/*.sh opencode/tests/*.sh
exit=0
```

### `actionlint` (version 1.7.7)

```text
$ actionlint .github/workflows/*.yml   # depuis une copie à la racine du futur dépôt
exit=0
```

## Copie (2026-11-25)

Reprise par copie (`cp -p`) de l'existant d'`antenly-ci` (`main`, HEAD `22f672e` du 2026-11-24T10:54:16Z) et de `galass-ci` (HEAD `13dc999` du 2026-11-24T03:30:34Z) vers `lifeos-ci-seed/opencode/`. Aucune réécriture manuelle ; les seules adaptations sont les chemins de `allowed-repos.sh` (déplacé vers `targets/` dans lifeos-ci) et le rétablissement des options du shell après ce source. Les droits d'exécution sont conservés.

### Scripts

| Fichier | Source (dépôt:chemin@sha court) | Décision |
| --- | --- | --- |
| `livelog.sh` | `galass-ci:opencode/livelog.sh@62fe71a` | adapté : repli de `allowed-repos.sh` vers `../targets/` et rétablissement des options du shell après source (`set +e -u -o pipefail`). |
| `leaklog.sh` | `galass-ci:opencode/leaklog.sh@c3f4470` | identique (contenu identique dans les deux dépôts ; version galass retenue car commit plus récent). |
| `redact-log.sh` | `antenly-ci:opencode/redact-log.sh@859ffb0` | identique (version antenly, plus récente, avec masquage des noms de fichiers audio). |
| `progress.sh` | `galass-ci:opencode/progress.sh@940d1bc` | identique (version galass, plus récente, paramétrée par `TARGET_DIR`). |
| `autosave.sh` | `galass-ci:opencode/autosave.sh@760bfb3` | identique (version galass, plus récente). |
| `autosave-deny.txt` | `galass-ci:opencode/autosave-deny.txt@cd86a32` | identique (version galass, plus récente et liste plus complète). |
| `checkpoint.sh` | `galass-ci:opencode/checkpoint.sh@1ef0f48` | identique (version galass, plus récente, `TARGET_DIR` avec repli `ANTENLY_DIR`). |
| `wippush.sh` | `galass-ci:opencode/wippush.sh@cd86a32` | adapté : repli de `allowed-repos.sh` vers `../targets/` et rétablissement des options du shell après source. |
| `done_check.sh` | `antenly-ci:opencode/done_check.sh@22f672e` | identique (version antenly, plus récente). |
| `done-check-call.sh` | `galass-ci:opencode/done-check-call.sh@1ef0f48` | identique (contenu identique ; version galass retenue car commit plus récent). |
| `split-diff.sh` | `antenly-ci:opencode/split-diff.sh@689e30f` | identique (contenu identique ; version antenly retenue car commit plus récent). |
| `run-fullrun.sh` | `antenly-ci:opencode/run-fullrun.sh@22f672e` | identique (version antenly, plus récente : `stop_after_step` et enveloppe mémoire `memcap`). |
| `step-agents.sh` | `antenly-ci:opencode/step-agents.sh@22f672e` | identique (présent uniquement dans antenly-ci). |
| `install-hook-profile.sh` | `galass-ci:opencode/install-hook-profile.sh@940d1bc` | identique (version galass, plus récente, refus sur stderr). |
| `log-recipient.txt` | `galass-ci:opencode/log-recipient.txt@c3f4470` | identique (contenu identique ; version galass retenue car commit plus récent). |
| `preannot.sh` | `antenly-ci:opencode/preannot.sh@859ffb0` | identique (présent uniquement dans antenly-ci). |
| `bench-capped` | `antenly-ci:opencode/bench-capped@2858541` | identique (présent uniquement dans antenly-ci). |
| `config/opencode.json` | `galass-ci:opencode/config/opencode.json@dfee18a` | identique (contenu identique ; version galass retenue car commit plus récent). |
| `extra-repos.sh` | `galass-ci:opencode/extra-repos.sh@760bfb3` | adapté : repli de `allowed-repos.sh` vers `../targets/` et rétablissement des options du shell après source. |
| `merge-signed-carry.sh` | `galass-ci:opencode/merge-signed-carry.sh@13dc999` | identique (présent uniquement dans galass-ci). |
| `emu-e2e.sh` | `galass-ci:opencode/emu-e2e.sh@650c7ac` | identique (présent uniquement dans galass-ci ; cible volontairement les dépôts Galass et `galass-emu-actions-pub`). |
| `ci-preamble.md` | `galass-ci:opencode/ci-preamble.md@13dc999` | identique (fichier support non listé, copié car requis par `prompt-contract-test.sh` et `preannot-test.sh` ; version galass plus récente). |

### Tests

| Fichier | Source (dépôt:chemin@sha court) | Décision |
| --- | --- | --- |
| `chain-step-test.sh` | `antenly-ci:opencode/tests/chain-step-test.sh@689e30f` | identique |
| `checkpoint-watchdog-verdict-test.sh` | `antenly-ci:opencode/tests/checkpoint-watchdog-verdict-test.sh@689e30f` | identique |
| `done-check-test.sh` | `antenly-ci:opencode/tests/done-check-test.sh@22f672e` | identique |
| `first-link-prompt-test.sh` | `antenly-ci:opencode/tests/first-link-prompt-test.sh@22f672e` | identique |
| `internals-test.sh` | `antenly-ci:opencode/tests/internals-test.sh@689e30f` | identique |
| `split-diff-test.sh` | `antenly-ci:opencode/tests/split-diff-test.sh@689e30f` | identique (contenu identique dans les deux dépôts) |
| `stall-resume-test.sh` | `antenly-ci:opencode/tests/stall-resume-test.sh@689e30f` | identique |
| `start-step-test.sh` | `antenly-ci:opencode/tests/start-step-test.sh@689e30f` | identique |
| `turn-end-test.sh` | `antenly-ci:opencode/tests/turn-end-test.sh@689e30f` | identique |
| `ffmpeg-install-test.sh` | `antenly-ci:opencode/tests/ffmpeg-install-test.sh@c45f62b` | identique (antenly uniquement) |
| `memcap-livelog-test.sh` | `antenly-ci:opencode/tests/memcap-livelog-test.sh@689e30f` | identique (antenly uniquement) |
| `memcap-test.sh` | `antenly-ci:opencode/tests/memcap-test.sh@a1905ad` | identique (antenly uniquement) |
| `preannot-test.sh` | `antenly-ci:opencode/tests/preannot-test.sh@859ffb0` | identique (antenly uniquement) |
| `preflight-test.sh` | `antenly-ci:opencode/tests/preflight-test.sh@a72e64f` | identique (antenly uniquement) |
| `redact-test.sh` | `antenly-ci:opencode/tests/redact-test.sh@859ffb0` | identique (antenly uniquement) |
| `stop-after-step-test.sh` | `antenly-ci:opencode/tests/stop-after-step-test.sh@22f672e` | identique (antenly uniquement) |
| `autosave-test.sh` | `galass-ci:opencode/tests/autosave-test.sh@cd86a32` | identique (version galass, plus récente) |
| `hmac-state-test.sh` | `galass-ci:opencode/tests/hmac-state-test.sh@650c7ac` | identique (version galass, plus récente) |
| `leaklog-test.sh` | `galass-ci:opencode/tests/leaklog-test.sh@940d1bc` | identique (version galass, plus récente) |
| `livelog-test.sh` | `galass-ci:opencode/tests/livelog-test.sh@940d1bc` | identique (version galass, plus récente) |
| `prompt-contract-test.sh` | `galass-ci:opencode/tests/prompt-contract-test.sh@940d1bc` | identique (version galass, plus récente) |
| `watchdog-test.sh` | `galass-ci:opencode/tests/watchdog-test.sh@940d1bc` | identique (version galass, plus récente) |
| `wippush-test.sh` | `galass-ci:opencode/tests/wippush-test.sh@a1388e2` | identique (version galass, plus récente) |
| `agent-idle-test.sh` | `galass-ci:opencode/tests/agent-idle-test.sh@dfee18a` | identique (contenu identique dans les deux dépôts) |
| `hook-profile-install-test.sh` | `galass-ci:opencode/tests/hook-profile-install-test.sh@62fe71a` | identique (contenu identique dans les deux dépôts) |
| `lib.sh` | `galass-ci:opencode/tests/lib.sh@c3f4470` | identique (contenu identique dans les deux dépôts) |
| `oc-deadline-test.sh` | `galass-ci:opencode/tests/oc-deadline-test.sh@650c7ac` | identique (contenu identique dans les deux dépôts) |
| `subagent-fail-test.sh` | `galass-ci:opencode/tests/subagent-fail-test.sh@dfee18a` | identique (contenu identique dans les deux dépôts) |
| `verdict-cli.lib` | `galass-ci:opencode/tests/verdict-cli.lib@1ef0f48` | identique (contenu identique dans les deux dépôts) |
| `allowed-repos-cwd-test.sh` | `galass-ci:opencode/tests/allowed-repos-cwd-test.sh@62fe71a` | identique (galass uniquement) |
| `allowed-repos-test.sh` | `galass-ci:opencode/tests/allowed-repos-test.sh@a1388e2` | identique — remplace la réécriture du seed (le test du seed était une réécriture de celui de galass). |
| `extra-repos-test.sh` | `galass-ci:opencode/tests/extra-repos-test.sh@a1388e2` | identique (galass uniquement) |
| `merge-signed-carry-test.sh` | `galass-ci:opencode/tests/merge-signed-carry-test.sh@13dc999` | identique (galass uniquement) |
| `stop-step-target-agent-test.sh` | `galass-ci:opencode/tests/stop-step-target-agent-test.sh@10372a3` | identique (galass uniquement) |
| `unit-contract-test.sh` | `galass-ci:opencode/tests/unit-contract-test.sh@650c7ac` | identique (galass uniquement) |
| `with-emulators-test.sh` | `galass-ci:opencode/tests/with-emulators-test.sh@650c7ac` | identique (galass uniquement) |

Les tests propres au seed (`lifeos-chain-test.sh`, `lifeos-guard-test.sh`, `notify-test.sh`, `quota-test.sh`) et `run-all.sh` sont conservés : ce ne sont pas des réécritures de scripts existants. `run-all.sh` découvre déjà tous les `*-test.sh`, donc les tests copiés y sont inclus sans modification. Deux tests copiés (`allowed-repos-cwd-test.sh`, `allowed-repos-test.sh`) remplacent les versions du seed, qui étaient des réécritures de tests galass-ci.

### Choix entre versions divergentes

- `run-fullrun.sh` : version **antenly-ci** (2026-11-24T10:54:16Z) et non galass-ci (2026-11-23T19:46:52Z) ; elle contient le correctif `stop_after_step` et l'enveloppe mémoire `memcap`.
- `done_check.sh` : version **antenly-ci** (2026-11-24T10:54:16Z), plus récente que galass-ci (2026-11-23T19:46:52Z).
- `redact-log.sh` : version **antenly-ci** (2026-11-16T03:50:56Z), plus récente que galass-ci (2026-11-15T18:26:54Z) et plus complète (masquage du corpus audio).
- `livelog.sh`, `progress.sh`, `install-hook-profile.sh`, `autosave.sh`, `autosave-deny.txt`, `checkpoint.sh`, `wippush.sh` : versions **galass-ci**, plus récentes ; elles portent le support `target_repo`/`TARGET_DIR`.
- `leaklog.sh`, `done-check-call.sh`, `log-recipient.txt`, `config/opencode.json` : contenu **identique** dans les deux dépôts, version galass-ci retenue (commit plus récent). `split-diff.sh` : contenu identique, version antenly-ci retenue (commit plus récent).
- Tests communs : version la plus récente fichier par fichier. Les tests identiques (`agent-idle`, `hook-profile-install`, `lib.sh`, `oc-deadline`, `split-diff`, `subagent-fail`, `verdict-cli.lib`) sont copiés depuis galass-ci, sauf `split-diff-test.sh` pris depuis antenly-ci (commit plus récent).

### Adaptations (liste exhaustive)

1. `opencode/livelog.sh`, `opencode/wippush.sh`, `opencode/extra-repos.sh` : si `allowed-repos.sh` n'est pas à côté du script, source de `../targets/allowed-repos.sh`. Dans lifeos-ci la liste blanche est dans `targets/` (le seed l'a déplacée).
2. Mêmes trois scripts : après le source, `set +e -u -o pipefail`. La version seed de `targets/allowed-repos.sh` active `set -euo pipefail`, contrairement à celle de galass-ci ; sans ce rétablissement, `wippush.sh daemon` sortait sur le `wait` interrompu par SIGTERM sans exécuter son nettoyage/trap.

Aucun renommage `antenly-ci`/`galass-ci` → `lifeos-ci` n'a été fait dans les scripts : cette adaptation n'est pas nécessaire à la copie et casserait des tests copiés qui vérifient les noms d'origine (ex. `emu-e2e.sh` cible volontairement `galass-emu-actions-pub`). Les références restantes sont à traiter dans le run de correction de `REVIEW.md`.

### Résultats des tests

`bash opencode/tests/run-all.sh` : **38 suites, 12 OK, 26 en échec**. Les échecs sont attendus et proviennent de dépendances à l'ancien dépôt ou à l'environnement, non de réécritures : `opencode-fullrun.yml` absent (lifeos-ci utilise `_agent-run.yml` et `fr-plan-vera.yml`), `opencode/allowed-repos.sh` attendu par des tests galass-ci alors que la liste est dans `targets/`, `bun` absent, `age`/`age-keygen` absents, et `lifeos` est volontairement autorisé dans la liste blanche du seed (les tests galass-ci attendent son refus). Les tests ne sont pas réécrits, conformément à la consigne.

### `bash opencode/tests/run-all.sh` (sortie brute)

```text
==> agent-idle-test.sh
OK   défaut : Forge=40 min (2400 s), seule entrée
OK   réglable par agent (Forge=55, Max=30)
OK   variable vide : aucune entrée
OK   valeur invalide refusée (90) : « Forge=abc »
OK   valeur invalide refusée (90) : « Forge=0 »
OK   valeur invalide refusée (90) : « Forge=721 »
OK   valeur invalide refusée (90) : « =5 »
OK   valeur invalide refusée (90) : « Forge »
OK   valeur invalide refusée (90) : « Forge=40,Forge=50 »
OK   valeur invalide refusée (90) : « Fo rge=5 »
OK   valeur invalide refusée (90) : « Forge=40, »
OK   valeur invalide refusée (90) : « 1Forge=5 »
OK   valeur invalide refusée (90) : « Forge=-3 »
OK   valeur invalide refusée (90) : « Forge=40;rm »
OK   Forge en cours : coupé au seuil de Forge (12s), pas au seuil de base
OK   la coupure reste tracée (error=timeout, rc 125) et la reprise conclut
OK   agent sans entrée (Engineer) : seuil de base inchangé (4s)
OK   aucun agent identifiable : seuil de base (4s), jamais d'extension
OK   entrée plus courte que la base : sans effet, le seuil de base est un plancher (7s)
OK   OC_SUBAGENT_IDLE_SEC explicite : le watchdog court reste en place (5s)
awk: fatal: cannot open file `/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml' for reading: No such file or directory
FAIL bloc de garde introuvable
OK   garde workflow : «  » accepté
OK   garde workflow : « Forge=40 » accepté
OK   garde workflow : « Forge=1 » accepté
OK   garde workflow : « Forge=720 » accepté
OK   garde workflow : « Forge=40,Max=30 » accepté
OK   garde workflow : « Forge=040 » accepté
FAIL garde workflow : « Forge=721 » accepté à tort
FAIL garde workflow : « Forge=999 » accepté à tort
FAIL garde workflow : « Forge=0 » accepté à tort
FAIL garde workflow : « Forge=000 » accepté à tort
FAIL garde workflow : « Forge=40,Forge=50 » accepté à tort
FAIL garde workflow : « Forge=abc » accepté à tort
FAIL garde workflow : « Forge » accepté à tort
FAIL garde workflow : « =5 » accepté à tort
FAIL garde workflow : « Forge=1000 » accepté à tort
OK   opencode.json : provider.opencode.options.timeout = 2400000 (40 min)
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/agent-idle-test.sh
==> allowed-repos-cwd-test.sh
FAIL opencode-fullrun.yml absent
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/allowed-repos-cwd-test.sh
==> allowed-repos-test.sh
/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/allowed-repos-test.sh: line 11: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/allowed-repos.sh: No such file or directory
FAIL workflow introuvable : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/../.github/workflows/opencode-fullrun.yml
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/allowed-repos-test.sh
==> autosave-test.sh
OK   aucun git add -A / . / --all : seuls des chemins nommés sont ajoutés
OK   carry + checkpoint commités en wip(carry) ; l'index de l'agent reste tel quel (credentials.json toujours indexé, non commité)
plugin absent : regex de référence
OK   A. les messages wip(carry) et wip(autosave) ne déclenchent pas la porte de clôture
OK   B. 16 fichiers interdits (.env, clés, keystore, google-services, comptes de service, secrets PSP, logs, vendor, apk, lien, gros, binaire) jamais commités ; 4 autorisés sauvés
OK   B2. fichiers nommés :(top)*, :(glob)**, :(top), :^src : traités comme des noms ordinaires, keys.json et .env jamais commités
OK   C. fuite : leak.py ni commité ni poussé (valeur absente partout), clean.py sauvé et poussé
OK   C. un commit contenant une fuite bloque le push (contrôle de plage de wippush)
OK   D. index.lock, autre branche, gitleaks absent (index remis), liste d'exclusion absente : rien commité
OK   E. arbre propre : silence, aucun commit
OK   F. ignoré (pas root ou setpriv absent)
<== ok autosave-test.sh
==> chain-step-test.sh
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
chmod: cannot access '/tmp/tmp.tinvn8akZE/chain.sh': No such file or directory
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
FAIL B1 check-échec : 
OK   B1 : état ISA jamais lu (bun non appelé) quand check a échoué
FAIL B1 : raison absente : 
FAIL B1 push-échec : 
OK   B1 : état ISA jamais lu quand push a échoué
FAIL B1 push-skipped : 
FAIL B1 : bun jamais appelé alors que check/push au vert
FAIL B1 : continue absent : 
FAIL M1 OC_STOP vide : 
OK   M1 : OC_STOP vide ⇒ état ISA jamais lu
FAIL hors-un : 
FAIL hors-un : raison absente : 
FAIL DISPATCH_TOKEN visible par bun : 
FAIL save_state échec : 
OK   save_state en échec ⇒ zéro dispatch (gh workflow run jamais appelé)
FAIL publish_state échec : 
OK   publish_state en échec ⇒ zéro dispatch
FAIL has_state=false à tort bloqué : 
FAIL succès à tort bloqué : 
FAIL restore refusé : 
OK   restore_state refusé ⇒ zéro dispatch
FAIL restore missing à tort bloqué : 
FAIL restore en échec : 
FAIL premier lien à tort bloqué : 
FAIL M3 next absent/faux : 
FAIL B2 prev_run_id absent/faux : 
FAIL phase inattendue : 
FAIL M3 : next=5 imposé à tort à verify : 
FAIL kind=echec : 
FAIL raison absente : 
FAIL kind=termine : 
FAIL kind=termine continue : 
FAIL illisible : 
FAIL résumé sans trace : 
FAIL safe_raw : 
FAIL safe_raw : message absent : bash: /tmp/tmp.tinvn8akZE/chain.sh: No such file or directory
OK   safe_raw : le jeton généré n'apparaît jamais dans le log
FAIL safe_raw : aucun marqueur de masquage : bash: /tmp/tmp.tinvn8akZE/chain.sh: No such file or directory
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
StopIteration
FAIL safe_raw : troncature attendue à 400 caractères (obtenu «  »)
OK   safe_raw : aucune workflow command injectée en début de ligne (newlines repliées)
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
chmod: cannot access '/tmp/tmp.tinvn8akZE/guard.sh': No such file or directory
FAIL garde : 19<20 refusé : bash: /tmp/tmp.tinvn8akZE/guard.sh: No such file or directory
FAIL garde : chain_count==chain_max accepté à tort (rc=127) : bash: /tmp/tmp.tinvn8akZE/guard.sh: No such file or directory
FAIL garde : chain_count=1000 : bash: /tmp/tmp.tinvn8akZE/guard.sh: No such file or directory
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/chain-step-test.sh
==> checkpoint-watchdog-verdict-test.sh
ko bun introuvable (requis par done_check.sh)
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/checkpoint-watchdog-verdict-test.sh
==> done-check-test.sh
ko bun introuvable (requis par done_check.sh)
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/done-check-test.sh
==> extra-repos-test.sh
OK   parse : liste vide
OK   parse : espaces retirés, ordre conservé
OK   parse : target_repo répété refusé
OK   parse : doublon refusé
FAIL dépôt non autorisé accepté : lifeos
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/extra-repos-test.sh
==> ffmpeg-install-test.sh
FAIL opencode-fullrun.yml absent
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/ffmpeg-install-test.sh
==> first-link-prompt-test.sh
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
chmod: cannot access '/tmp/tmp.rEHJ3R14wz/guard.sh': No such file or directory
chmod: cannot access '/tmp/tmp.rEHJ3R14wz/prep.sh': No such file or directory
chmod: cannot access '/tmp/tmp.rEHJ3R14wz/chain.sh': No such file or directory
FAIL garde chaînée : phase=plan, effectif «  » (attendu prompts:p.md) — bash: /tmp/tmp.rEHJ3R14wz/guard.sh: No such file or directory
FAIL garde chaînée : phase=build, effectif «  » (attendu prompts:b.md) — bash: /tmp/tmp.rEHJ3R14wz/guard.sh: No such file or directory
FAIL garde chaînée : phase=verify, effectif «  » (attendu prompts:v.md) — bash: /tmp/tmp.rEHJ3R14wz/guard.sh: No such file or directory
FAIL garde chaînée : phase=close, effectif «  » (attendu prompts:c.md) — bash: /tmp/tmp.rEHJ3R14wz/guard.sh: No such file or directory
FAIL hors chaîne : effectif «  » au lieu de prompts:p.md
FAIL prep chaîné (rc=127) : mauvais prompt ou échec de prep — out= err=bash: /tmp/tmp.rEHJ3R14wz/prep.sh: No such file or directory prompt=
FAIL prep hors chaîne (rc=127) : prompt absent — out= err=bash: /tmp/tmp.rEHJ3R14wz/prep.sh: No such file or directory
grep: /tmp/tmp.rEHJ3R14wz/prep.sh: No such file or directory
FAIL prep : n'utilise pas IN_PROMPT_EFFECTIVE
grep: /tmp/tmp.rEHJ3R14wz/prep.sh: No such file or directory
OK   prep : plus de lecture directe de IN_PROMPT
grep: /tmp/tmp.rEHJ3R14wz/guard.sh: No such file or directory
FAIL garde : ne calcule pas l'effectif
grep: /tmp/tmp.rEHJ3R14wz/chain.sh: No such file or directory
OK   chain : aucun second calcul du prompt (prompt_path transmis inchangé)
grep: /tmp/tmp.rEHJ3R14wz/chain.sh: No such file or directory
FAIL chain : prompt_path modifié au dispatch
OK   run-fullrun.sh : OC_ERROR_IDLE_SEC a un défaut de 240 s
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/first-link-prompt-test.sh
==> hmac-state-test.sh
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
chmod: cannot access '/tmp/tmp.LI23tJn4vh/save.sh': No such file or directory
chmod: cannot access '/tmp/tmp.LI23tJn4vh/restore.sh': No such file or directory
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
FAIL save_state exit=127 : bash: /tmp/tmp.LI23tJn4vh/save.sh: No such file or directory
FAIL has_state absent/faux : 
FAIL state.tar.enc/sig manquants dans 
OK   save_state : state.tar en clair supprimé (jamais publié)
OK   save_state : le clair (contenu du marker) n'est pas lisible dans le chiffré
OK   save_state : la clé n'apparaît jamais dans la sortie du step
cp: cannot stat '/state.tar.enc': No such file or directory
cp: cannot stat '/state.sig': No such file or directory
FAIL restore_state exit=127 : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
FAIL état non restauré malgré une signature correcte : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
FAIL message de restauration absent : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
FAIL status=restored absent : 
FAIL suppression de l'artefact non appelée
OK   restore_state : la clé n'apparaît jamais dans la sortie du step
cp: cannot stat '/tmp/tmp.LI23tJn4vh/fake_artifact/state.tar.enc': No such file or directory
FAIL restore_state exit=127 : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
OK   restore_state : chiffré modifié après signature ⇒ aucune extraction
FAIL message attendu absent : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
FAIL status=refused absent : 
cp: cannot stat '/tmp/tmp.LI23tJn4vh/fake_artifact/state.tar.enc.orig': No such file or directory
OK   restore_state : signature fausse ⇒ aucune extraction
FAIL message attendu absent : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
FAIL status=refused absent : 
cp: cannot stat '/state.sig': No such file or directory
OK   autre clé : signature au bon format (64 hex, indiscernable d'une vraie)
cat: /state.sig: No such file or directory
OK   autre clé : signature bien différente de celle de la vraie clé
FAIL autre clé : exit=127 : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
OK   restore_state : signature valide d'une autre clé ⇒ aucune extraction (HMAC rejette)
FAIL status=refused absent : 
OK   autre clé : aucune clé dans la sortie du step
cp: cannot stat '/state.tar.enc': No such file or directory
cp: cannot stat '/state.sig': No such file or directory
OK   chiffré corrompu re-signé : HMAC valide pour la vraie clé (échec attendu = déchiffrement)
FAIL chiffré corrompu : exit=127 : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
OK   restore_state : déchiffrement en échec ⇒ aucune extraction
FAIL status=refused absent : 
OK   chiffré corrompu : jamais de message de restauration
cp: cannot stat '/state.tar.enc': No such file or directory
cp: cannot stat '/state.sig': No such file or directory
FAIL restore_state exit=127 : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
OK   restore_state : clé absente ⇒ aucune extraction
FAIL message explicite absent : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
OK   restore_state : clé absente ⇒ jamais confondu avec le message « signature invalide »
FAIL status=refused absent : 
FAIL restore_state exit=127 : bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
FAIL status=missing absent : 
OK   B1 : has_state=true + download KO ⇒ le step échoue (exit 127), pas de cold start silencieux
FAIL B1 : status=failed absent : 
OK   B1 : jamais status=missing quand l'état était attendu
OK   B1 : aucun état restauré
FAIL B1 : has_state=false + download KO : rc=127 
cp: cannot stat '/state.tar.enc': No such file or directory
cp: cannot stat '/state.sig': No such file or directory
FAIL B1 : DELETE en échec silencieux : rc=127 log=bash: /tmp/tmp.LI23tJn4vh/restore.sh: No such file or directory
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
FAIL save_state exit=127 (attendu 1) : bash: /tmp/tmp.LI23tJn4vh/save.sh: No such file or directory
FAIL message explicite absent : bash: /tmp/tmp.LI23tJn4vh/save.sh: No such file or directory
OK   save_state : clé absente ⇒ has_state jamais mis à true
FAIL save_state exit=127 : bash: /tmp/tmp.LI23tJn4vh/save.sh: No such file or directory
FAIL has_state=false attendu : 
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/hmac-state-test.sh
==> hook-profile-install-test.sh
FAIL opencode-fullrun.yml absent
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/hook-profile-install-test.sh
==> internals-test.sh
[memcap] mécanisme=cgroupv2 limite=10G
ok 1 journaux internes collectés (ajoutés, canaris présents avant masquage)
ok 2 canaris masqués par redact-log.sh
ok 3 dossier de journaux internes absent -> run normal
<== ok internals-test.sh
==> leaklog-test.sh
OK   gitleaks : 8.30.1
FAIL age absent
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/leaklog-test.sh
==> lifeos-chain-test.sh
PASS lifeos-chain-test : 23 cas
<== ok lifeos-chain-test.sh
==> lifeos-guard-test.sh
PASS lifeos-guard-test : 23 cas
<== ok lifeos-guard-test.sh
==> livelog-test.sh
FAIL age-keygen
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/livelog-test.sh
==> memcap-livelog-test.sh
OK   journal : [memcap] mécanisme=cgroupv2 limite=10G
OK   stderr contient la même ligne [memcap]
OK   MEMCAP_BYTES=2G → limite=2G
PASS memcap-livelog : ligne [memcap] dans le journal et sur stderr
<== ok memcap-livelog-test.sh
==> memcap-test.sh
OK   commande sous le cap : succès
OK   eater tué, ligne [oom] et pic numérique (rc=137)
OK   parent (test) toujours vivant après OOM du fils
OK   bench-capped sans argument : exit 2 (usage)
OK   command -v bench-capped trouve l'outil dans le PATH
OK   prlimit : [oom] et pic numérique (rc=42)
PASS memcap : cap mémoire, OOM, parent survit, [oom] journal, PATH, pic
<== ok memcap-test.sh
==> merge-signed-carry-test.sh
OK   usage : dépôt requis
OK   troncature : fichier signé historique restauré à l'identique (sans clé)
OK   relance : aucune réécriture si rien ne manque
OK   fusion avec clé : steps 1+2+3, signature recréée valable
OK   sans clé et courant plus riche : enregistrements déjà signés conservés
OK   arbre illisible : version signée de la branche restaurée
merge-signed-carry : MEMORY/WORK/s/fullrun-carry.json restauré (2 enregistrement(s) signé(s) repris de la branche)
OK   pre-commit : commit amputé rattrapé, steps 1 et 2 conservés
OK   régression périmée (mêmes ids) : état le plus récent restauré
FAIL opencode-fullrun.yml absent
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/merge-signed-carry-test.sh
==> notify-test.sh
PASS notify-test : 21 cas
<== ok notify-test.sh
==> oc-deadline-test.sh
Traceback (most recent call last):
  File "<stdin>", line 6, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/oc-deadline-test.sh
==> preannot-test.sh
FAIL workflow introuvable : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/.github/workflows/opencode-fullrun.yml
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/preannot-test.sh
==> preflight-test.sh
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
FAIL le step preflight est absent du workflow
résumé : 0 ok, 1 ko
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/preflight-test.sh
==> prompt-contract-test.sh
ok 1 les trois consignes du contrat sont dans le prompt rendu
ok 2 ordre de priorité respecté (52 < 53 < 54)
ok 3 aucune consigne ne finit par un point d'interrogation
ok 4 contrôle négatif : une consigne interrogative est détectée
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL 5 le workflow n'injecte pas le préambule attendu
ok 6 le préambule porte la règle « fin de tour ≠ fin de run »
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/prompt-contract-test.sh
==> quota-test.sh
PASS quota-test : 8 cas
<== ok quota-test.sh
==> redact-test.sh
ok 1 nom audio masqué en [REDACTED:audio-file]
ok 2 aucun nom de fichier audio ne survit au masquage
ok 3 lignes sans nom audio préservées
ok 4 gitleaks : 0 finding sur le journal masqué
<== ok redact-test.sh
==> split-diff-test.sh
ok 1a --out-dir manquant -> 64
ok 1b --max-lines trop petit -> 64
ok 2 diff vide -> un seul morceau vide
ok 3 petit diff -> un seul morceau, fichier intact
ok 4a gros diff -> plusieurs morceaux (3)
ok 4b chaque fichier dans exactement un morceau, jamais coupé en deux
ok 5a un seul fichier > seuil -> reste un seul morceau (jamais tronqué)
ok 5b le morceau garde TOUT le fichier (504 lignes, > seuil 100)
ok 6 manifest.txt présent et nomme les fichiers du morceau
ok 7 --source fichier fonctionne (pas seulement stdin)
ok 7b --source introuvable -> 64
résumé : 11 ok, 0 ko
<== ok split-diff-test.sh
==> stall-resume-test.sh
[memcap] mécanisme=cgroupv2 limite=10G
ok 1 silence puis reprise réussie
[memcap] mécanisme=cgroupv2 limite=10G
ok 2 reprises bornées puis arrêt silence
[memcap] mécanisme=cgroupv2 limite=10G
ok 3 --continue muet -> nouvelle session
[memcap] mécanisme=cgroupv2 limite=10G
ok 4 erreur fournisseur -> fallback
[memcap] mécanisme=cgroupv2 limite=10G
ok 5 429 -> fallback
[memcap] mécanisme=cgroupv2 limite=10G
ok 6 réponses vides épuisées -> rc 126
[memcap] mécanisme=cgroupv2 limite=10G
ok 7 sortie > 1 Mo rc 0 -> succès sans reprise
[memcap] mécanisme=cgroupv2 limite=10G
ok 8 sous-agent muet -> seuil 8 min et subagent_timeout=1
[memcap] mécanisme=cgroupv2 limite=10G
ok 9 chaîne de secours -> rotation + OC_MODEL_MAIN
[memcap] mécanisme=cgroupv2 limite=10G
ok 10 principal filtré + agent/*.md réécrits
modèle de secours refusé : opencode/paid-model
ok 11 modèle non gratuit -> 90
OC_MODEL_CHAIN vide (ou réduite au principal) : aucun secours
ok 12 chaîne réduite au principal -> 90
[memcap] mécanisme=cgroupv2 limite=10G
ok 13 LIFEOS_FULLRUN=1 transmis par le wrapper, absent hors wrapper
[memcap] mécanisme=cgroupv2 limite=10G
ok 14 ok-after-done -> done_check=ok, arret=max_pass, rc 0, un seul appel
[memcap] mécanisme=cgroupv2 limite=10G
ok 15 erreur timeout + silence court -> repli immédiat sur la chaîne (4s)
[memcap] mécanisme=cgroupv2 limite=10G
ok 16 erreur empty + silence court -> repli immédiat (4s)
[memcap] mécanisme=cgroupv2 limite=10G
ok 17 marqueur 429 -> seuil de silence normal conservé (11s), pas de repli anticipé
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL 18 variable non câblée
OC_ERROR_IDLE_SEC invalide
ok 19 OC_ERROR_IDLE_SEC invalide -> 90, opencode jamais lancé
[memcap] mécanisme=cgroupv2 limite=10G
ok 20 erreur puis activité > seuil -> compteur réarmé, aucun repli, un seul appel (7s)
[memcap] mécanisme=cgroupv2 limite=10G
ok 21 marqueur provider + silence -> repli rapide sur la chaîne (4s)
[memcap] mécanisme=cgroupv2 limite=10G
ok 22 reprise error_idle : vraie cause (erreur timeout, 2 s via OC_ERROR_IDLE_SEC)
[memcap] mécanisme=cgroupv2 limite=10G
ok 23 reprise sur silence : message historique conservé
[memcap] mécanisme=cgroupv2 limite=10G
ok 24 OC_ERROR_IDLE_SEC actif avec une chaîne à un seul élément (4s)
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/stall-resume-test.sh: line 427: [: : integer expected
FAIL 25 câblage workflow absent ou conditionné
[memcap] mécanisme=cgroupv2 limite=10G
ok 26 passe muette coupée : une seule ligne error= dans le statut
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/stall-resume-test.sh
==> start-step-test.sh
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL IN_START_STEP absent
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL OC_START_STEP non exporté
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
OK   workflow : deploy n'est pas une valeur acceptée
OK   wrapper : start_step=verify transmis à opencode
OK   wrapper : vide = rien d'exporté (comportement habituel)
OK   wrapper : une variable héritée sans l'input n'est pas reprise
OK   wrapper : OC_START_STEP='deploy' refusé (90), opencode jamais lancé
OK   wrapper : OC_START_STEP='8' refusé (90), opencode jamais lancé
OK   wrapper : OC_START_STEP='../x' refusé (90), opencode jamais lancé
OK   wrapper : OC_START_STEP='verify;x' refusé (90), opencode jamais lancé
OK   wrapper : OC_START_STEP='n'importe' refusé (90), opencode jamais lancé
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/start-step-test.sh
==> stop-after-step-test.sh
FAIL workflow introuvable : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/.github/workflows/opencode-fullrun.yml
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/stop-after-step-test.sh
==> stop-step-target-agent-test.sh
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml'
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL IN_STOP_AFTER_STEP absent
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL IN_TARGET_AGENT absent
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL OC_STOP_AFTER_STEP non exporté
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL OC_TARGET_AGENT non exporté
FAIL verify/Silas non transmis : 
FAIL vide : 
FAIL héritage : 
FAIL 'deploy' accepté (rc=1)
FAIL '8' accepté (rc=1)
FAIL '../x' accepté (rc=1)
FAIL 'verify;x' accepté (rc=1)
FAIL 'n'importe' accepté (rc=1)
FAIL '1Silas' accepté (rc=1)
FAIL 'Silas;x' accepté (rc=1)
FAIL '../x' accepté (rc=1)
FAIL 'n'importe quoi' accepté (rc=1)
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/stop-step-target-agent-test.sh
==> subagent-fail-test.sh
OK   2 sous-agents en échec : passe coupée en 2s, reprise sur opencode/b-free
OK   la reprise passe --model opencode/b-free
OK   le modèle des sous-agents (Max.md) est réécrit
OK   la reprise conclut (PASS vérifié)
OK   l'échec est tracé (agent-error timeout)
OK   1 seul échec de sous-agent : pas de coupure par ce motif
OK   OC_SUBAGENT_FAIL_MAX=0 : désactivé
OK   valeur invalide refusée (90)
<== ok subagent-fail-test.sh
==> turn-end-test.sh
[memcap] mécanisme=cgroupv2 limite=10G
ok 1 fin de tour sans PASS -> rc 127, arret=tour-fini
[memcap] mécanisme=cgroupv2 limite=10G
ok 2 PASS vérifié -> rc 0, arret=max_pass, aucune reprise
[memcap] mécanisme=cgroupv2 limite=10G
ok 3 fin de tour -> reprise -> PASS, rc 0
[memcap] mécanisme=cgroupv2 limite=10G
ok 4 reprises épuisées sur fins de tour -> rc 127
[memcap] mécanisme=cgroupv2 limite=10G
ok 5 réponse vide -> rc 126 (précédence sur 127)
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL 6 contrat du workflow
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../../.github/workflows/opencode-fullrun.yml: No such file or directory
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/turn-end-test.sh
==> unit-contract-test.sh
ko bun introuvable (requis par done_check.sh)
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/unit-contract-test.sh
==> watchdog-test.sh
OK   passage trop long : coupé (2 s), superviseur vivant, arrêt propre
OK   passage tué : relancé, superviseur intact
OK   jeton absent de l'état et des sorties du chien de garde
PASS watchdog : timeout de passage, relance après kill, superviseur stable, jeton caché
<== ok watchdog-test.sh
==> wippush-test.sh
OK   cas propre : wip poussé 4b2fbfc sur feat/test
OK   rien de neuf : silence, aucun push
OK   secret ghp_ : non poussé, fichier cité, valeur absente
OK   clé ISA : non poussée, jamais affichée
OK   contrôle de clé ISA borné : timeout -> aucun push
OK   non fast-forward : refusé, distant intact (aucun force)
OK   remote https : jeton passé à git par son environnement seul (ni argument, ni URL)
OK   démon : deux pushes, arrêt propre sur SIGTERM
OK   branches main/master/refs/fullrun-logs refusées à l'entrée
FAIL lifeos accepté comme TARGET_REPO
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/wippush-test.sh
==> with-emulators-test.sh
/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/with-emulators-test.sh: line 11: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/allowed-repos.sh: No such file or directory
FAIL workflow introuvable : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/../.github/workflows/opencode-fullrun.yml
::error::test échoué : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/with-emulators-test.sh
ECHEC : au moins un test a échoué
```

### `shellcheck` (version 0.11.0)

```text
$ shellcheck -x opencode/*.sh targets/*.sh

In opencode/checkpoint.sh line 33:
JOB=""; STEP=""; LABEL=""; SUMMARY=""; STATUS=done; REPO="${TARGET_DIR:-${ANTENLY_DIR:-$(pwd)}}"; AGENT=""
                                              ^-- SC1010 (warning): Use semicolon or linefeed before 'done' (or quote to make it literal).


In opencode/checkpoint.sh line 187:
    . "$DC_CALL_LIB"
      ^------------^ SC1091 (info): Not following: done-check-call.sh: openBinaryFile: does not exist (No such file or directory)


In opencode/extra-repos.sh line 25:
. "$allowed"
  ^--------^ SC1091 (info): Not following: opencode/allowed-repos.sh: openBinaryFile: does not exist (No such file or directory)


In opencode/livelog.sh line 24:
. "$allowed"
  ^--------^ SC1091 (info): Not following: opencode/allowed-repos.sh: openBinaryFile: does not exist (No such file or directory)


In opencode/preannot.sh line 271:
    eval "$(python3 -c '
                       ^-- SC2016 (info): Expressions don't expand in single quotes, use double quotes for that.


In opencode/preannot.sh line 288:
    job_conclusion="$s_job"
                    ^----^ SC2154 (warning): s_job is referenced but not assigned.


In opencode/run-fullrun.sh line 469:
. "$DC_CALL_LIB"
  ^------------^ SC1091 (info): Not following: done-check-call.sh: openBinaryFile: does not exist (No such file or directory)


In opencode/run-fullrun.sh line 705:
on_cancel() {
^-- SC2329 (info): This function is never invoked. Check usage (or ignored if invoked indirectly).


In opencode/wippush.sh line 26:
. "$allowed"
  ^--------^ SC1091 (info): Not following: opencode/allowed-repos.sh: openBinaryFile: does not exist (No such file or directory)

For more information:
  https://www.shellcheck.net/wiki/SC1010 -- Use semicolon or linefeed before ...
  https://www.shellcheck.net/wiki/SC2154 -- s_job is referenced but not assig...
  https://www.shellcheck.net/wiki/SC1091 -- Not following: done-check-call.sh...
```

Échec attendu, défauts préexistants des scripts copiés (SC1010, SC1091, SC2154, SC2329) : ils ne sont pas corrigés dans ce run de copie. `shellcheck -x opencode/tests/*.sh` est également non nul (avertissements/infos préexistants des tests copiés), hors commande demandée.

### `actionlint` (version 1.7.7)

```text
$ actionlint .github/workflows/*.yml   # depuis une copie de lifeos-ci-seed à la racine
exit=0
```

`actionlint` doit être lancé depuis une copie du dossier à la racine : imbriqué sous `lifeos-ci-seed/`, il résout les `uses: ./.github/workflows/...` par rapport à la racine du dépôt `antenly-ci` et ne trouve pas les workflows locaux.

## Fix2 (2026-11-25)

Correctifs : preuve que tous les tests du socle tournent, restauration du test
`allowed-repos-test.sh` d'origine (galass-ci) et correction des 3 défauts
critiques de `REVIEW.md` (§2.1, §2.2, §2.3). Aucun défaut « élevé » traité.

### Tests exécutés (un par ligne)

```text
allowed-repos-test.sh
allowed-repos-lifeos-test.sh
autosave-test.sh
critical-state-isolation-test.sh
critical-frozen-tools-test.sh
critical-git-isolation-test.sh
internals-test.sh
lifeos-chain-test.sh
lifeos-guard-test.sh
memcap-livelog-test.sh
memcap-test.sh
notify-test.sh
quota-test.sh
redact-test.sh
split-diff-test.sh
subagent-fail-test.sh
watchdog-test.sh
```

`opencode/tests/run-all.sh` ne découvre plus seulement par glob : il porte une
liste explicite `TESTS` **et** vérifie qu'aucun `opencode/tests/*-test.sh`
présent n'est absent de cette liste (échec si un fichier est oublié). Les 25
tests déplacés dans `opencode/tests/upstream-fullrun/` ne sont pas des tests du
socle : ils ciblent `opencode-fullrun.yml` (absent de lifeos-ci), `bun`/`age`
(non installés par `ci.yml`) ou la politique galass-ci qui refuse `lifeos`.

### Corrections de chemins et d'adaptation (A)

| Fichier | Avant → après | Raison |
| --- | --- | --- |
| `opencode/tests/allowed-repos-test.sh:11` | `. "$here/allowed-repos.sh"` → `. "$here/../targets/allowed-repos.sh"` | Dans lifeos-ci, la liste blanche est dans `targets/`. |
| `opencode/tests/allowed-repos-test.sh:13` | `.github/workflows/opencode-fullrun.yml` → `.github/workflows/task.yml` | lifeos-ci n'a pas `opencode-fullrun.yml` ; `task.yml` expose les `options:` de `target_repo`. |
| `opencode/tests/allowed-repos-test.sh:25` | liste des refus `lifeos antenly-ci …` → `Galass_backendx main …` | `lifeos` et `antenly-ci` sont dans la liste étendue de lifeos-ci ; leurs cas positifs sont dans `allowed-repos-lifeos-test.sh`. |
| `opencode/tests/allowed-repos-lifeos-test.sh` | nouveau | Cas propres aux 9 dépôts de lifeos-ci (voir B). |
| `opencode/tests/run-all.sh` | glob `*-test.sh` → liste `TESTS` + contrôle de complétude | Prouver que chaque test du socle est lancé ; détecter tout oubli. |
| `opencode/tests/upstream-fullrun/*` | 25 tests + `verdict-cli.lib` déplacés | Cibles absentes (workflow FullRun, outils FullRun, `bun`/`age`) ou assertions galass-ci incompatibles ; aucune assertion n'a été affaiblie. |
| `opencode/checkpoint.sh:33` | `STATUS=done` → `STATUS="done"` | ShellCheck SC1010, sans changement de logique. |
| `opencode/{checkpoint,run-fullrun}.sh` (source dynamique) | ajout `# shellcheck disable=SC1091` | ShellCheck ne suit pas `. "$DC_CALL_LIB"`. |
| `opencode/{extra-repos,livelog,wippush}.sh` (source dynamique) | ajout `# shellcheck disable=SC1091` | ShellCheck ne suit pas `. "$allowed"` (repli `../targets/`). |
| `opencode/preannot.sh:271,288` | ajout `# shellcheck disable=SC2016,SC2154` | Valeurs produites par `eval`/`python3` ; aucune logique modifiée. |
| `opencode/run-fullrun.sh:705` | `disable=SC2317` → `SC2317,SC2329` | `on_cancel` est appelée par `trap` ; aucune logique modifiée. |

### B — `allowed-repos-test.sh` d'origine et cas lifeos-ci

`opencode/tests/allowed-repos-test.sh` est la version de
`galass-ci/opencode/tests/allowed-repos-test.sh` restaurée par `cp`, adaptée
uniquement aux chemins (liste dans `targets/`, workflow `task.yml`). Les cas de
la liste étendue sont dans `opencode/tests/allowed-repos-lifeos-test.sh`.

Pourquoi chaque cas ajouté est nécessaire :

- `antenly` : cible historique et valeur par défaut des workflows.
- `antenly-ci` : dépôt qui porte la branche et les PR de ce socle.
- `galass-ci` : dépôt source des outils repris ; doit rester ciblable.
- `Galass_Rider`, `Galass_Driver`, `Galass_backend`, `galass-emu-actions-pub` :
  dépôts Galass repris de galass-ci.
- `lifeos` : dépôt de référence ; accepté dans la liste, mais toute écriture
  reste conditionnée par `lifeos_write` et `lifeos-guard.sh`.
- `lifeos-ci` : dépôt qui héberge ces workflows.

Le test lifeos vérifie aussi : `validate`/`normalize_extra_repos` (virgules,
espaces, doublons, casse, chemins injectés), l'alignement des `options:` de
`task.yml` **et** `fr-plan-vera.yml` sur `allowed_repos_list`, et l'absence de
copie jointe par `|` de la liste étendue hors `targets/allowed-repos.sh`.

### C — Protections des 3 défauts critiques

Sources reprises (lecture seule) :

- **C1** : `galass-ci/.github/workflows/opencode-fullrun.yml`, step
  « Outils de contrôle figés (root, avant opencode) », lignes 756-830
  (même modèle dans `antenly-ci/.github/workflows/opencode-fullrun.yml`,
  lignes 866-925) : `sudo chmod go-w /opt`, `sudo install -d -o root -g root`,
  copies root-owned, exécution post-opencode depuis `/opt/fullrun-tools`.
  lifeos-ci reprend ce modèle avec `/opt/lifeos-ci-tools` et
  `/opt/lifeos-ci-state` (`_agent-run.yml`, step « Outils de confiance figés »).
- **C2** : `galass-ci/opencode/extra-repos.sh:82-99` (`run_git` :
  `env -i`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`,
  `GIT_CONFIG_COUNT`, `core.hooksPath=/dev/null`) et `:293-346` (copie nue,
  `push --no-verify`) ; `galass-ci/.github/workflows/opencode-fullrun.yml`
  (env `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM`, `G=(git -c
  core.hooksPath=/dev/null -c core.fsmonitor=false)`) ;
  `antenly-ci/.github/workflows/opencode-task.yml:310-339`
  (`--redact`, merge-base, refus `.github/workflows`, push `--no-verify`).
  lifeos-ci pousse depuis une copie nue avec `env -i` et les mêmes options.
- **C3** : `galass-ci/.github/workflows/opencode-fullrun.yml` : les steps
  post-opencode utilisent `${{ inputs.* }}` et `${{ steps.prep.outputs.base }}`,
  jamais `$GITHUB_ENV` (commentaire « Valeurs du step > $GITHUB_ENV : opencode
  ne peut ni changer la branche, ni la base… »). lifeos-ci applique le même
  principe : output de validation immuable, état de départ root-owned, opencode
  sous `env -i` avec `HOME`/`TMPDIR` dédiés, statut publié par un step séparé.

Tests correspondants (sans réseau, sans secret) :

- C1 : `opencode/tests/critical-frozen-tools-test.sh` — copie root **avant**
  opencode, post-opencode uniquement via `$TOOLS_DIR` (garde-fou, gitleaks,
  notification, quota).
- C2 : `opencode/tests/critical-git-isolation-test.sh` — analyse du workflow
  **et** preuve fonctionnelle : un `pre-push` et un `include.path` locaux ne
  s'exécutent pas avec l'isolation utilisée ; contrôle négatif sans
  `hooksPath=/dev/null`.
- C3 : `opencode/tests/critical-state-isolation-test.sh` — `env -i` (aucun
  `GITHUB_ENV`/`GITHUB_OUTPUT`/`GITHUB_PATH`/`RUNNER_TEMP`), état root relu,
  SHA de base écrits avant opencode, output de validation immuable.

### `bash opencode/tests/run-all.sh` (sortie brute)

```text
$ bash opencode/tests/run-all.sh
==> allowed-repos-test.sh
OK   allowed_repo : liste acceptée, hors liste refusée
OK   options: target_repo du workflow alignées sur allowed_repos_list
OK   aucune copie en dur de la liste hors allowed-repos.sh
<== ok allowed-repos-test.sh
==> allowed-repos-lifeos-test.sh
OK   allowed_repo : les 9 dépôts de la liste étendue sont acceptés
OK   validate : target lifeos + extra antenly-ci,galass-ci
OK   normalize_extra_repos : espaces/virgules normalisés
OK   validate : doublon, casse et chemin refusés
OK   options: target_repo de task.yml et fr-plan-vera.yml alignées
OK   aucune copie de la liste étendue hors allowed-repos.sh
<== ok allowed-repos-lifeos-test.sh
==> autosave-test.sh
OK   aucun git add -A / . / --all : seuls des chemins nommés sont ajoutés
OK   carry + checkpoint commités en wip(carry) ; l'index de l'agent reste tel quel (credentials.json toujours indexé, non commité)
plugin absent : regex de référence
OK   A. les messages wip(carry) et wip(autosave) ne déclenchent pas la porte de clôture
OK   B. 16 fichiers interdits (.env, clés, keystore, google-services, comptes de service, secrets PSP, logs, vendor, apk, lien, gros, binaire) jamais commités ; 4 autorisés sauvés
OK   B2. fichiers nommés :(top)*, :(glob)**, :(top), :^src : traités comme des noms ordinaires, keys.json et .env jamais commités
OK   C. fuite : leak.py ni commité ni poussé (valeur absente partout), clean.py sauvé et poussé
OK   C. un commit contenant une fuite bloque le push (contrôle de plage de wippush)
OK   D. index.lock, autre branche, gitleaks absent (index remis), liste d'exclusion absente : rien commité
OK   E. arbre propre : silence, aucun commit
OK   F. ignoré (pas root ou setpriv absent)
<== ok autosave-test.sh
==> critical-state-isolation-test.sh
OK   opencode isolé ; statut, modèle, SHA et dépôts recalculés hors de sa portée
OK   env -i : GITHUB_ENV/GITHUB_OUTPUT/GITHUB_PATH/RUNNER_TEMP absents de l'enfant
<== ok critical-state-isolation-test.sh
==> critical-frozen-tools-test.sh
OK   freeze root avant opencode, post-opencode via $TOOLS_DIR uniquement
<== ok critical-frozen-tools-test.sh
==> critical-git-isolation-test.sh
OK   workflow : push isolé depuis une copie nue, hooks/config neutralisés
OK   isolation : hook pre-push et include.path locaux neutralisés
OK   contrôle négatif : le hook bloque bien sans hooksPath=/dev/null
<== ok critical-git-isolation-test.sh
==> internals-test.sh
[memcap] mécanisme=cgroupv2 limite=10G
ok 1 journaux internes collectés (ajoutés, canaris présents avant masquage)
ok 2 canaris masqués par redact-log.sh
ok 3 dossier de journaux internes absent -> run normal
<== ok internals-test.sh
==> lifeos-chain-test.sh
PASS lifeos-chain-test : 23 cas
<== ok lifeos-chain-test.sh
==> lifeos-guard-test.sh
PASS lifeos-guard-test : 23 cas
<== ok lifeos-guard-test.sh
==> memcap-livelog-test.sh
OK   journal : [memcap] mécanisme=cgroupv2 limite=10G
OK   stderr contient la même ligne [memcap]
OK   MEMCAP_BYTES=2G → limite=2G
PASS memcap-livelog : ligne [memcap] dans le journal et sur stderr
<== ok memcap-livelog-test.sh
==> memcap-test.sh
OK   commande sous le cap : succès
OK   eater tué, ligne [oom] et pic numérique (rc=137)
OK   parent (test) toujours vivant après OOM du fils
OK   bench-capped sans argument : exit 2 (usage)
OK   command -v bench-capped trouve l'outil dans le PATH
OK   prlimit : [oom] et pic numérique (rc=42)
PASS memcap : cap mémoire, OOM, parent survit, [oom] journal, PATH, pic
<== ok memcap-test.sh
==> notify-test.sh
PASS notify-test : 21 cas
<== ok notify-test.sh
==> quota-test.sh
PASS quota-test : 8 cas
<== ok quota-test.sh
==> redact-test.sh
ok 1 nom audio masqué en [REDACTED:audio-file]
ok 2 aucun nom de fichier audio ne survit au masquage
ok 3 lignes sans nom audio préservées
ok 4 gitleaks : 0 finding sur le journal masqué
<== ok redact-test.sh
==> split-diff-test.sh
ok 1a --out-dir manquant -> 64
ok 1b --max-lines trop petit -> 64
ok 2 diff vide -> un seul morceau vide
ok 3 petit diff -> un seul morceau, fichier intact
ok 4a gros diff -> plusieurs morceaux (3)
ok 4b chaque fichier dans exactement un morceau, jamais coupé en deux
ok 5a un seul fichier > seuil -> reste un seul morceau (jamais tronqué)
ok 5b le morceau garde TOUT le fichier (504 lignes, > seuil 100)
ok 6 manifest.txt présent et nomme les fichiers du morceau
ok 7 --source fichier fonctionne (pas seulement stdin)
ok 7b --source introuvable -> 64
résumé : 11 ok, 0 ko
<== ok split-diff-test.sh
==> subagent-fail-test.sh
OK   2 sous-agents en échec : passe coupée en 2s, reprise sur opencode/b-free
OK   la reprise passe --model opencode/b-free
OK   le modèle des sous-agents (Max.md) est réécrit
OK   la reprise conclut (PASS vérifié)
OK   l'échec est tracé (agent-error timeout)
OK   1 seul échec de sous-agent : pas de coupure par ce motif
OK   OC_SUBAGENT_FAIL_MAX=0 : désactivé
OK   valeur invalide refusée (90)
<== ok subagent-fail-test.sh
==> watchdog-test.sh
OK   passage trop long : coupé (2 s), superviseur vivant, arrêt propre
OK   passage tué : relancé, superviseur intact
OK   jeton absent de l'état et des sorties du chien de garde
PASS watchdog : timeout de passage, relance après kill, superviseur stable, jeton caché
<== ok watchdog-test.sh
PASS : 17 suite(s) de tests
exit=0
```

### `shellcheck` (version 0.11.0)

```text
$ shellcheck -x opencode/*.sh targets/*.sh
ShellCheck - shell script analysis tool
version: 0.11.0
exit=0
```

### `actionlint` (version 1.7.7)

```text
$ actionlint --version
1.7.7
installed by downloading from release page
built with go1.23.4 compiler for linux/amd64
$ actionlint .github/workflows/*.yml   # depuis une copie de lifeos-ci-seed à la racine
exit=0
```

Actionlint est lancé depuis une copie du dossier à la racine du futur dépôt :
imbriqué sous `lifeos-ci-seed/`, il résout `uses: ./.github/workflows/...` par
rapport à la racine d'`antenly-ci` et ne trouve pas les workflows locaux.

### Commit Fix2

- `515d2d3` — `fix(lifeos-ci): figer les outils, isoler git et l'état, preuves de tests (Fix2)`
- Auteur : `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`
- Portée : `lifeos-ci-seed/` uniquement.

## Fix2a (2026-11-25)

Vérification seule, sans aucune correction. Portée : `lifeos-ci-seed/` uniquement.

Outils : `shellcheck 0.11.0` (déjà présent), `actionlint 1.7.7` (binaire officiel de la release rhysd/actionlint v1.7.7, installé dans `/tmp/opencode/bin`).

### Tests exécutés

`bash opencode/tests/run-all.sh` lance les 17 scripts `*-test.sh` listés dans `TESTS` (tous présents, tous PASS, exit=0).

Il ne lance pas les 25 scripts `*-test.sh` de `opencode/tests/upstream-fullrun/` : le glob de complétude ne couvre que `$here/*-test.sh`, pas les sous-dossiers. Ces 25 scripts ont donc été exécutés un par un avec `bash <fichier>` :

| # | Script | Exit |
|---|--------|------|
| 1 | `agent-idle-test.sh` | 1 |
| 2 | `allowed-repos-cwd-test.sh` | 0 |
| 3 | `chain-step-test.sh` | 1 |
| 4 | `checkpoint-watchdog-verdict-test.sh` | 1 |
| 5 | `done-check-test.sh` | 1 |
| 6 | `extra-repos-test.sh` | 0 |
| 7 | `ffmpeg-install-test.sh` | 0 |
| 8 | `first-link-prompt-test.sh` | 1 |
| 9 | `hmac-state-test.sh` | 1 |
| 10 | `hook-profile-install-test.sh` | 0 |
| 11 | `leaklog-test.sh` | 0 |
| 12 | `livelog-test.sh` | 1 |
| 13 | `merge-signed-carry-test.sh` | 0 |
| 14 | `oc-deadline-test.sh` | 1 |
| 15 | `preannot-test.sh` | 127 |
| 16 | `preflight-test.sh` | 1 |
| 17 | `prompt-contract-test.sh` | 1 |
| 18 | `stall-resume-test.sh` | 1 |
| 19 | `start-step-test.sh` | 1 |
| 20 | `stop-after-step-test.sh` | 1 |
| 21 | `stop-step-target-agent-test.sh` | 1 |
| 22 | `turn-end-test.sh` | 1 |
| 23 | `unit-contract-test.sh` | 1 |
| 24 | `wippush-test.sh` | 0 |
| 25 | `with-emulators-test.sh` | 127 |

Total : 42 scripts exécutés (17 via `run-all.sh` + 25 manquants en direct).

### Sortie brute — `bash opencode/tests/run-all.sh`

```text
==> allowed-repos-test.sh
OK   allowed_repo : liste acceptée, hors liste refusée
OK   options: target_repo du workflow alignées sur allowed_repos_list
OK   aucune copie en dur de la liste hors allowed-repos.sh
<== ok allowed-repos-test.sh
==> allowed-repos-lifeos-test.sh
OK   allowed_repo : les 9 dépôts de la liste étendue sont acceptés
OK   validate : target lifeos + extra antenly-ci,galass-ci
OK   normalize_extra_repos : espaces/virgules normalisés
OK   validate : doublon, casse et chemin refusés
OK   options: target_repo de task.yml et fr-plan-vera.yml alignées
OK   aucune copie de la liste étendue hors allowed-repos.sh
<== ok allowed-repos-lifeos-test.sh
==> autosave-test.sh
OK   aucun git add -A / . / --all : seuls des chemins nommés sont ajoutés
OK   carry + checkpoint commités en wip(carry) ; l'index de l'agent reste tel quel (credentials.json toujours indexé, non commité)
plugin absent : regex de référence
OK   A. les messages wip(carry) et wip(autosave) ne déclenchent pas la porte de clôture
OK   B. 16 fichiers interdits (.env, clés, keystore, google-services, comptes de service, secrets PSP, logs, vendor, apk, lien, gros, binaire) jamais commités ; 4 autorisés sauvés
OK   B2. fichiers nommés :(top)*, :(glob)**, :(top), :^src : traités comme des noms ordinaires, keys.json et .env jamais commités
OK   C. fuite : leak.py ni commité ni poussé (valeur absente partout), clean.py sauvé et poussé
OK   C. un commit contenant une fuite bloque le push (contrôle de plage de wippush)
OK   D. index.lock, autre branche, gitleaks absent (index remis), liste d'exclusion absente : rien commité
OK   E. arbre propre : silence, aucun commit
OK   F. ignoré (pas root ou setpriv absent)
<== ok autosave-test.sh
==> critical-state-isolation-test.sh
OK   opencode isolé ; statut, modèle, SHA et dépôts recalculés hors de sa portée
OK   env -i : GITHUB_ENV/GITHUB_OUTPUT/GITHUB_PATH/RUNNER_TEMP absents de l'enfant
<== ok critical-state-isolation-test.sh
==> critical-frozen-tools-test.sh
OK   freeze root avant opencode, post-opencode via $TOOLS_DIR uniquement
<== ok critical-frozen-tools-test.sh
==> critical-git-isolation-test.sh
OK   workflow : push isolé depuis une copie nue, hooks/config neutralisés
OK   isolation : hook pre-push et include.path locaux neutralisés
OK   contrôle négatif : le hook bloque bien sans hooksPath=/dev/null
<== ok critical-git-isolation-test.sh
==> internals-test.sh
[memcap] mécanisme=cgroupv2 limite=10G
ok 1 journaux internes collectés (ajoutés, canaris présents avant masquage)
ok 2 canaris masqués par redact-log.sh
ok 3 dossier de journaux internes absent -> run normal
<== ok internals-test.sh
==> lifeos-chain-test.sh
PASS lifeos-chain-test : 23 cas
<== ok lifeos-chain-test.sh
==> lifeos-guard-test.sh
PASS lifeos-guard-test : 23 cas
<== ok lifeos-guard-test.sh
==> memcap-livelog-test.sh
OK   journal : [memcap] mécanisme=cgroupv2 limite=10G
OK   stderr contient la même ligne [memcap]
OK   MEMCAP_BYTES=2G → limite=2G
PASS memcap-livelog : ligne [memcap] dans le journal et sur stderr
<== ok memcap-livelog-test.sh
==> memcap-test.sh
OK   commande sous le cap : succès
OK   eater tué, ligne [oom] et pic numérique (rc=137)
OK   parent (test) toujours vivant après OOM du fils
OK   bench-capped sans argument : exit 2 (usage)
OK   command -v bench-capped trouve l'outil dans le PATH
OK   prlimit : [oom] et pic numérique (rc=42)
PASS memcap : cap mémoire, OOM, parent survit, [oom] journal, PATH, pic
<== ok memcap-test.sh
==> notify-test.sh
PASS notify-test : 21 cas
<== ok notify-test.sh
==> quota-test.sh
PASS quota-test : 8 cas
<== ok quota-test.sh
==> redact-test.sh
ok 1 nom audio masqué en [REDACTED:audio-file]
ok 2 aucun nom de fichier audio ne survit au masquage
ok 3 lignes sans nom audio préservées
ok 4 gitleaks : 0 finding sur le journal masqué
<== ok redact-test.sh
==> split-diff-test.sh
ok 1a --out-dir manquant -> 64
ok 1b --max-lines trop petit -> 64
ok 2 diff vide -> un seul morceau vide
ok 3 petit diff -> un seul morceau, fichier intact
ok 4a gros diff -> plusieurs morceaux (3)
ok 4b chaque fichier dans exactement un morceau, jamais coupé en deux
ok 5a un seul fichier > seuil -> reste un seul morceau (jamais tronqué)
ok 5b le morceau garde TOUT le fichier (504 lignes, > seuil 100)
ok 6 manifest.txt présent et nomme les fichiers du morceau
ok 7 --source fichier fonctionne (pas seulement stdin)
ok 7b --source introuvable -> 64
résumé : 11 ok, 0 ko
<== ok split-diff-test.sh
==> subagent-fail-test.sh
OK   2 sous-agents en échec : passe coupée en 2s, reprise sur opencode/b-free
OK   la reprise passe --model opencode/b-free
OK   le modèle des sous-agents (Max.md) est réécrit
OK   la reprise conclut (PASS vérifié)
OK   l'échec est tracé (agent-error timeout)
OK   1 seul échec de sous-agent : pas de coupure par ce motif
OK   OC_SUBAGENT_FAIL_MAX=0 : désactivé
OK   valeur invalide refusée (90)
<== ok subagent-fail-test.sh
==> watchdog-test.sh
OK   passage trop long : coupé (2 s), superviseur vivant, arrêt propre
OK   passage tué : relancé, superviseur intact
OK   jeton absent de l'état et des sorties du chien de garde
PASS watchdog : timeout de passage, relance après kill, superviseur stable, jeton caché
<== ok watchdog-test.sh
PASS : 17 suite(s) de tests
EXIT_CODE=0
```

### Sortie brute — scripts `upstream-fullrun/` manquants

#### `bash opencode/tests/upstream-fullrun/agent-idle-test.sh`

```text
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
grep: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
agent-idle-test.sh: line 52: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
FAIL défaut : 
grep: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
agent-idle-test.sh: line 52: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
FAIL réglage : 
grep: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
OK   variable vide : aucune entrée
FAIL « Forge=abc » accepté (rc=127)
FAIL « Forge=0 » accepté (rc=127)
FAIL « Forge=721 » accepté (rc=127)
FAIL « =5 » accepté (rc=127)
FAIL « Forge » accepté (rc=127)
FAIL « Forge=40,Forge=50 » accepté (rc=127)
FAIL « Fo rge=5 » accepté (rc=127)
FAIL « Forge=40, » accepté (rc=127)
FAIL « 1Forge=5 » accepté (rc=127)
FAIL « Forge=-3 » accepté (rc=127)
FAIL « Forge=40;rm » accepté (rc=127)
agent-idle-test.sh: line 52: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
FAIL Forge : -1s 
grep: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
agent-idle-test.sh: line 52: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
FAIL trace : 
agent-idle-test.sh: line 52: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
FAIL Engineer : -1s 
agent-idle-test.sh: line 52: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
FAIL inconnu : -1s 
agent-idle-test.sh: line 52: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
FAIL plancher : -1s 
agent-idle-test.sh: line 52: /tmp/tmp.cTG5W1UA1R/log.status: No such file or directory
FAIL plafond : -1s 
awk: fatal: cannot open file `/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml' for reading: No such file or directory
FAIL bloc de garde introuvable
OK   garde workflow : «  » accepté
OK   garde workflow : « Forge=40 » accepté
OK   garde workflow : « Forge=1 » accepté
OK   garde workflow : « Forge=720 » accepté
OK   garde workflow : « Forge=40,Max=30 » accepté
OK   garde workflow : « Forge=040 » accepté
FAIL garde workflow : « Forge=721 » accepté à tort
FAIL garde workflow : « Forge=999 » accepté à tort
FAIL garde workflow : « Forge=0 » accepté à tort
FAIL garde workflow : « Forge=000 » accepté à tort
FAIL garde workflow : « Forge=40,Forge=50 » accepté à tort
FAIL garde workflow : « Forge=abc » accepté à tort
FAIL garde workflow : « Forge » accepté à tort
FAIL garde workflow : « =5 » accepté à tort
FAIL garde workflow : « Forge=1000 » accepté à tort
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../config/opencode.json'
FAIL opencode.json : timeout fournisseur != 2400000
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/allowed-repos-cwd-test.sh`

```text
allowed-repos-cwd-test.sh: line 10: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/tests/lib.sh: No such file or directory
allowed-repos-cwd-test.sh: line 13: ko: command not found
allowed-repos-cwd-test.sh: line 14: ko: command not found
allowed-repos-cwd-test.sh: line 15: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
allowed-repos-cwd-test.sh: line 18: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
allowed-repos-cwd-test.sh: line 20: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
allowed-repos-cwd-test.sh: line 27: [: : integer expected
allowed-repos-cwd-test.sh: line 27: ko: command not found
allowed-repos-cwd-test.sh: line 30: ok: command not found
cp: cannot stat '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/allowed-repos.sh': No such file or directory
cp: cannot stat '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/extra-repos.sh': No such file or directory
chmod: cannot access '/tmp/tmp.T9E0qiOFvX/fullrun-tools/extra-repos.sh': No such file or directory
chmod: cannot access '/tmp/tmp.T9E0qiOFvX/fullrun-tools/allowed-repos.sh': No such file or directory
allowed-repos-cwd-test.sh: line 44: ko: command not found
allowed-repos-cwd-test.sh: line 45: ko: command not found
allowed-repos-cwd-test.sh: line 47: ok: command not found
cp: cannot stat '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/extra-repos.sh': No such file or directory
chmod: cannot access '/tmp/tmp.T9E0qiOFvX/orphan/extra-repos.sh': No such file or directory
allowed-repos-cwd-test.sh: line 57: ko: command not found
allowed-repos-cwd-test.sh: line 58: ok: command not found
allowed-repos-cwd-test.sh: line 68: fake_ghp: command not found
allowed-repos-cwd-test.sh: line 91: ko: command not found
allowed-repos-cwd-test.sh: line 92: ko: command not found
allowed-repos-cwd-test.sh: line 93: ko: command not found
allowed-repos-cwd-test.sh: line 94: ok: command not found
fatal: cannot change to '/tmp/tmp.T9E0qiOFvX/root/Galass_Driver': No such file or directory
fatal: cannot change to '/tmp/tmp.T9E0qiOFvX/root/Galass_Driver': No such file or directory
allowed-repos-cwd-test.sh: line 99: /tmp/tmp.T9E0qiOFvX/root/Galass_Driver/y: No such file or directory
fatal: cannot change to '/tmp/tmp.T9E0qiOFvX/root/Galass_Driver': No such file or directory
fatal: cannot change to '/tmp/tmp.T9E0qiOFvX/root/Galass_Driver': No such file or directory
allowed-repos-cwd-test.sh: line 114: ko: command not found
allowed-repos-cwd-test.sh: line 115: ko: command not found
allowed-repos-cwd-test.sh: line 116: ko: command not found
allowed-repos-cwd-test.sh: line 117: ok: command not found
allowed-repos-cwd-test.sh: line 134: ko: command not found
allowed-repos-cwd-test.sh: line 135: ko: command not found
allowed-repos-cwd-test.sh: line 137: ok: command not found
allowed-repos-cwd-test.sh: line 143: /tmp/tmp.T9E0qiOFvX/fullrun-tools/allowed-repos.sh: No such file or directory
allowed-repos-cwd-test.sh: line 144: allowed_repo: command not found
allowed-repos-cwd-test.sh: line 144: ko: command not found
allowed-repos-cwd-test.sh: line 145: allowed_repo: command not found
allowed-repos-cwd-test.sh: line 146: ok: command not found
PASS allowed-repos-cwd : push et PR fonctionnent hors du checkout
EXIT_CODE=0
```

#### `bash opencode/tests/upstream-fullrun/chain-step-test.sh`

```text
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
chmod: cannot access '/tmp/tmp.JsiBpjtD4L/chain.sh': No such file or directory
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
FAIL B1 check-échec : 
OK   B1 : état ISA jamais lu (bun non appelé) quand check a échoué
FAIL B1 : raison absente : 
FAIL B1 push-échec : 
OK   B1 : état ISA jamais lu quand push a échoué
FAIL B1 push-skipped : 
FAIL B1 : bun jamais appelé alors que check/push au vert
FAIL B1 : continue absent : 
FAIL M1 OC_STOP vide : 
OK   M1 : OC_STOP vide ⇒ état ISA jamais lu
FAIL hors-un : 
FAIL hors-un : raison absente : 
FAIL DISPATCH_TOKEN visible par bun : 
FAIL save_state échec : 
OK   save_state en échec ⇒ zéro dispatch (gh workflow run jamais appelé)
FAIL publish_state échec : 
OK   publish_state en échec ⇒ zéro dispatch
FAIL has_state=false à tort bloqué : 
FAIL succès à tort bloqué : 
FAIL restore refusé : 
OK   restore_state refusé ⇒ zéro dispatch
FAIL restore missing à tort bloqué : 
FAIL restore en échec : 
FAIL premier lien à tort bloqué : 
FAIL M3 next absent/faux : 
FAIL B2 prev_run_id absent/faux : 
FAIL phase inattendue : 
FAIL M3 : next=5 imposé à tort à verify : 
FAIL kind=echec : 
FAIL raison absente : 
FAIL kind=termine : 
FAIL kind=termine continue : 
FAIL illisible : 
FAIL résumé sans trace : 
FAIL safe_raw : 
FAIL safe_raw : message absent : bash: /tmp/tmp.JsiBpjtD4L/chain.sh: No such file or directory
OK   safe_raw : le jeton généré n'apparaît jamais dans le log
FAIL safe_raw : aucun marqueur de masquage : bash: /tmp/tmp.JsiBpjtD4L/chain.sh: No such file or directory
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
StopIteration
FAIL safe_raw : troncature attendue à 400 caractères (obtenu «  »)
OK   safe_raw : aucune workflow command injectée en début de ligne (newlines repliées)
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
chmod: cannot access '/tmp/tmp.JsiBpjtD4L/guard.sh': No such file or directory
FAIL garde : 19<20 refusé : bash: /tmp/tmp.JsiBpjtD4L/guard.sh: No such file or directory
FAIL garde : chain_count==chain_max accepté à tort (rc=127) : bash: /tmp/tmp.JsiBpjtD4L/guard.sh: No such file or directory
FAIL garde : chain_count=1000 : bash: /tmp/tmp.JsiBpjtD4L/guard.sh: No such file or directory
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/checkpoint-watchdog-verdict-test.sh`

```text
ko bun introuvable (requis par done_check.sh)
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/done-check-test.sh`

```text
ko bun introuvable (requis par done_check.sh)
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/extra-repos-test.sh`

```text
extra-repos-test.sh: line 11: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/tests/lib.sh: No such file or directory
extra-repos-test.sh: line 14: find_gitleaks: command not found
extra-repos-test.sh: line 14: ko: command not found
extra-repos-test.sh: line 20: rand_alnum: command not found
extra-repos-test.sh: line 48: ko: command not found
extra-repos-test.sh: line 49: ok: command not found
extra-repos-test.sh: line 51: ko: command not found
extra-repos-test.sh: line 52: ko: command not found
extra-repos-test.sh: line 53: ok: command not found
extra-repos-test.sh: line 56: ko: command not found
extra-repos-test.sh: line 57: ok: command not found
extra-repos-test.sh: line 60: ko: command not found
extra-repos-test.sh: line 61: ok: command not found
extra-repos-test.sh: line 68: ok: command not found
extra-repos-test.sh: line 70: ko: command not found
extra-repos-test.sh: line 71: ko: command not found
extra-repos-test.sh: line 72: ok: command not found
extra-repos-test.sh: line 84: ko: command not found
extra-repos-test.sh: line 85: ko: command not found
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
extra-repos-test.sh: line 86: ko: command not found
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Rider': No such file or directory
extra-repos-test.sh: line 87: ko: command not found
extra-repos-test.sh: line 88: ko: command not found
extra-repos-test.sh: line 90: ko: command not found
extra-repos-test.sh: line 92: ko: command not found
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
extra-repos-test.sh: line 93: ko: command not found
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
extra-repos-test.sh: line 95: ko: command not found
extra-repos-test.sh: line 96: ok: command not found
extra-repos-test.sh: line 99: /tmp/tmp.0oUePO2NNJ/extra/Galass_Driver/a.txt: No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
extra-repos-test.sh: line 102: ko: command not found
extra-repos-test.sh: line 103: ko: command not found
extra-repos-test.sh: line 104: ko: command not found
cat: /tmp/tmp.0oUePO2NNJ/state/Galass_Driver.modified: No such file or directory
extra-repos-test.sh: line 105: ko: command not found
cat: /tmp/tmp.0oUePO2NNJ/state/Galass_Rider.modified: No such file or directory
extra-repos-test.sh: line 106: ko: command not found
extra-repos-test.sh: line 107: ko: command not found
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
extra-repos-test.sh: line 109: ko: command not found
extra-repos-test.sh: line 111: ko: command not found
extra-repos-test.sh: line 112: ok: command not found
extra-repos-test.sh: line 116: fake_ghp: command not found
extra-repos-test.sh: line 117: /tmp/tmp.0oUePO2NNJ/extra/Galass_Driver/secret.txt: No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
extra-repos-test.sh: line 121: ko: command not found
extra-repos-test.sh: line 122: ko: command not found
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
extra-repos-test.sh: line 128: /tmp/tmp.0oUePO2NNJ/state/Galass_Driver.head: No such file or directory
extra-repos-test.sh: line 129: /tmp/tmp.0oUePO2NNJ/state/Galass_Driver.modified: No such file or directory
extra-repos-test.sh: line 130: /tmp/tmp.0oUePO2NNJ/state/Galass_Driver.check: No such file or directory
extra-repos-test.sh: line 131: ok: command not found
extra-repos-test.sh: line 134: rand_alnum: command not found
extra-repos-test.sh: line 136: /tmp/tmp.0oUePO2NNJ/extra/Galass_Driver/isa.txt: No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
extra-repos-test.sh: line 140: ko: command not found
extra-repos-test.sh: line 141: ko: command not found
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Driver': No such file or directory
extra-repos-test.sh: line 143: /tmp/tmp.0oUePO2NNJ/state/Galass_Driver.head: No such file or directory
extra-repos-test.sh: line 144: /tmp/tmp.0oUePO2NNJ/state/Galass_Driver.check: No such file or directory
extra-repos-test.sh: line 145: ok: command not found
fatal: not a git repository (or any of the parent directories): .git
fatal: not a git repository (or any of the parent directories): .git
extra-repos-test.sh: line 153: ko: command not found
fatal: not a git repository (or any of the parent directories): .git
extra-repos-test.sh: line 155: /tmp/tmp.0oUePO2NNJ/state/Galass_Driver.head: No such file or directory
extra-repos-test.sh: line 156: /tmp/tmp.0oUePO2NNJ/state/Galass_Driver.check: No such file or directory
extra-repos-test.sh: line 157: ok: command not found
fatal: not a git repository (or any of the parent directories): .git
fatal: not a git repository (or any of the parent directories): .git
extra-repos-test.sh: line 163: ko: command not found
extra-repos-test.sh: line 173: ko: command not found
extra-repos-test.sh: line 175: ok: command not found
extra-repos-test.sh: line 183: ok: command not found
extra-repos-test.sh: line 186: /tmp/tmp.0oUePO2NNJ/extra/Galass_Rider/d.txt: No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Rider': No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/Galass_Rider': No such file or directory
extra-repos-test.sh: line 189: ko: command not found
extra-repos-test.sh: line 208: ko: command not found
extra-repos-test.sh: line 209: ko: command not found
grep: /tmp/tmp.0oUePO2NNJ/push.argv: No such file or directory
grep: /tmp/tmp.0oUePO2NNJ/push.argv: No such file or directory
cat: /tmp/tmp.0oUePO2NNJ/push.argv: No such file or directory
extra-repos-test.sh: line 211: ko: command not found
grep: /tmp/tmp.0oUePO2NNJ/push.argv: No such file or directory
cat: /tmp/tmp.0oUePO2NNJ/push.hdr: No such file or directory
cat: /tmp/tmp.0oUePO2NNJ/push.hdr: No such file or directory
extra-repos-test.sh: line 214: ko: command not found
extra-repos-test.sh: line 218: ok: command not found
extra-repos-test.sh: line 238: /tmp/tmp.0oUePO2NNJ/state/Galass_Rider.pushed: No such file or directory
extra-repos-test.sh: line 242: ko: command not found
extra-repos-test.sh: line 243: ko: command not found
grep: /tmp/tmp.0oUePO2NNJ/gh.create: No such file or directory
extra-repos-test.sh: line 244: ko: command not found
grep: /tmp/tmp.0oUePO2NNJ/gh.create: No such file or directory
grep: /tmp/tmp.0oUePO2NNJ/gh.argv: No such file or directory
grep: /tmp/tmp.0oUePO2NNJ/gh.create: No such file or directory
grep: /tmp/tmp.0oUePO2NNJ/gh.argv: No such file or directory
extra-repos-test.sh: line 251: ko: command not found
extra-repos-test.sh: line 252: ko: command not found
extra-repos-test.sh: line 253: ok: command not found
extra-repos-test.sh: line 259: ok: command not found
extra-repos-test.sh: line 268: ok: command not found
extra-repos-test.sh: line 340: ko: command not found
extra-repos-test.sh: line 341: ko: command not found
extra-repos-test.sh: line 342: ko: command not found
extra-repos-test.sh: line 343: ko: command not found
extra-repos-test.sh: line 355: ko: command not found
extra-repos-test.sh: line 357: ok: command not found
extra-repos-test.sh: line 366: ko: command not found
extra-repos-test.sh: line 367: /tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub/wip.txt: No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub': No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub': No such file or directory
extra-repos-test.sh: line 375: ko: command not found
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub': No such file or directory
fatal: ambiguous argument 'refs/heads/feat/ms': unknown revision or path not in the working tree.
Use '--' to separate paths from revisions, like this:
'git <command> [<revision>...] -- [<file>...]'
extra-repos-test.sh: line 378: ko: command not found
grep: /tmp/tmp.0oUePO2NNJ/extra-wip/galass-emu-actions-pub/status: No such file or directory
extra-repos-test.sh: line 380: ko: command not found
extra-repos-test.sh: line 381: ok: command not found
extra-repos-test.sh: line 384: fake_ghp: command not found
fatal: ambiguous argument 'refs/heads/feat/ms': unknown revision or path not in the working tree.
Use '--' to separate paths from revisions, like this:
'git <command> [<revision>...] -- [<file>...]'
extra-repos-test.sh: line 386: /tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub/sec.txt: No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub': No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub': No such file or directory
extra-repos-test.sh: line 393: ko: command not found
grep: /tmp/tmp.0oUePO2NNJ/extra-wip/galass-emu-actions-pub/status: No such file or directory
extra-repos-test.sh: line 395: ko: command not found
fatal: ambiguous argument 'refs/heads/feat/ms': unknown revision or path not in the working tree.
Use '--' to separate paths from revisions, like this:
'git <command> [<revision>...] -- [<file>...]'
extra-repos-test.sh: line 398: ko: command not found
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub': No such file or directory
extra-repos-test.sh: line 400: ok: command not found
extra-repos-test.sh: line 407: ko: command not found
extra-repos-test.sh: line 420: /tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub/wip.txt: No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub': No such file or directory
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub': No such file or directory
extra-repos-test.sh: line 429: ko: command not found
fatal: cannot change to '/tmp/tmp.0oUePO2NNJ/extra/galass-emu-actions-pub': No such file or directory
fatal: ambiguous argument 'refs/heads/feat/ms': unknown revision or path not in the working tree.
Use '--' to separate paths from revisions, like this:
'git <command> [<revision>...] -- [<file>...]'
extra-repos-test.sh: line 433: ko: command not found
extra-repos-test.sh: line 434: ok: command not found
PASS extra-repos : parse, checkout, push propre, secret, clé ISA, workflows, non-ff, main, PR brouillon, jeton caché, fetch authentifié, wip périodique
EXIT_CODE=0
```

#### `bash opencode/tests/upstream-fullrun/ffmpeg-install-test.sh`

```text
ffmpeg-install-test.sh: line 9: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/opencode/tests/lib.sh: No such file or directory
ffmpeg-install-test.sh: line 13: ko: command not found
ffmpeg-install-test.sh: line 14: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/ci.yml: No such file or directory
ffmpeg-install-test.sh: line 17: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
ffmpeg-install-test.sh: line 18: ko: command not found
ffmpeg-install-test.sh: line 19: ok: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
ffmpeg-install-test.sh: line 21: ko: command not found
ffmpeg-install-test.sh: line 22: ok: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
ffmpeg-install-test.sh: line 24: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
ffmpeg-install-test.sh: line 25: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
ffmpeg-install-test.sh: line 26: ko: command not found
ffmpeg-install-test.sh: line 27: ok: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
ffmpeg-install-test.sh: line 35: ko: command not found
ffmpeg-install-test.sh: line 36: [: : integer expected
ffmpeg-install-test.sh: line 36: ko: command not found
ffmpeg-install-test.sh: line 37: [: : integer expected
ffmpeg-install-test.sh: line 37: ko: command not found
ffmpeg-install-test.sh: line 38: [: : integer expected
ffmpeg-install-test.sh: line 38: ko: command not found
ffmpeg-install-test.sh: line 39: ok: command not found
PASS ffmpeg-install : pin, secours apt, contrôle avant opencode
EXIT_CODE=0
```

#### `bash opencode/tests/upstream-fullrun/first-link-prompt-test.sh`

```text
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
chmod: cannot access '/tmp/tmp.PrJGAIVn6G/guard.sh': No such file or directory
chmod: cannot access '/tmp/tmp.PrJGAIVn6G/prep.sh': No such file or directory
chmod: cannot access '/tmp/tmp.PrJGAIVn6G/chain.sh': No such file or directory
FAIL garde chaînée : phase=plan, effectif «  » (attendu prompts:p.md) — bash: /tmp/tmp.PrJGAIVn6G/guard.sh: No such file or directory
FAIL garde chaînée : phase=build, effectif «  » (attendu prompts:b.md) — bash: /tmp/tmp.PrJGAIVn6G/guard.sh: No such file or directory
FAIL garde chaînée : phase=verify, effectif «  » (attendu prompts:v.md) — bash: /tmp/tmp.PrJGAIVn6G/guard.sh: No such file or directory
FAIL garde chaînée : phase=close, effectif «  » (attendu prompts:c.md) — bash: /tmp/tmp.PrJGAIVn6G/guard.sh: No such file or directory
FAIL hors chaîne : effectif «  » au lieu de prompts:p.md
cp: cannot stat '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../ci-preamble.md': No such file or directory
FAIL prep chaîné (rc=127) : mauvais prompt ou échec de prep — out= err=bash: /tmp/tmp.PrJGAIVn6G/prep.sh: No such file or directory prompt=
FAIL prep hors chaîne (rc=127) : prompt absent — out= err=bash: /tmp/tmp.PrJGAIVn6G/prep.sh: No such file or directory
grep: /tmp/tmp.PrJGAIVn6G/prep.sh: No such file or directory
FAIL prep : n'utilise pas IN_PROMPT_EFFECTIVE
grep: /tmp/tmp.PrJGAIVn6G/prep.sh: No such file or directory
OK   prep : plus de lecture directe de IN_PROMPT
grep: /tmp/tmp.PrJGAIVn6G/guard.sh: No such file or directory
FAIL garde : ne calcule pas l'effectif
grep: /tmp/tmp.PrJGAIVn6G/chain.sh: No such file or directory
OK   chain : aucun second calcul du prompt (prompt_path transmis inchangé)
grep: /tmp/tmp.PrJGAIVn6G/chain.sh: No such file or directory
FAIL chain : prompt_path modifié au dispatch
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL run-fullrun.sh : OC_ERROR_IDLE_SEC absent ou sans défaut
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/hmac-state-test.sh`

```text
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
chmod: cannot access '/tmp/tmp.GpmNqhuOqk/save.sh': No such file or directory
chmod: cannot access '/tmp/tmp.GpmNqhuOqk/restore.sh': No such file or directory
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
FAIL save_state exit=127 : bash: /tmp/tmp.GpmNqhuOqk/save.sh: No such file or directory
FAIL has_state absent/faux : 
FAIL state.tar.enc/sig manquants dans 
OK   save_state : state.tar en clair supprimé (jamais publié)
OK   save_state : le clair (contenu du marker) n'est pas lisible dans le chiffré
OK   save_state : la clé n'apparaît jamais dans la sortie du step
cp: cannot stat '/state.tar.enc': No such file or directory
cp: cannot stat '/state.sig': No such file or directory
FAIL restore_state exit=127 : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
FAIL état non restauré malgré une signature correcte : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
FAIL message de restauration absent : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
FAIL status=restored absent : 
FAIL suppression de l'artefact non appelée
OK   restore_state : la clé n'apparaît jamais dans la sortie du step
cp: cannot stat '/tmp/tmp.GpmNqhuOqk/fake_artifact/state.tar.enc': No such file or directory
FAIL restore_state exit=127 : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
OK   restore_state : chiffré modifié après signature ⇒ aucune extraction
FAIL message attendu absent : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
FAIL status=refused absent : 
cp: cannot stat '/tmp/tmp.GpmNqhuOqk/fake_artifact/state.tar.enc.orig': No such file or directory
OK   restore_state : signature fausse ⇒ aucune extraction
FAIL message attendu absent : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
FAIL status=refused absent : 
cp: cannot stat '/state.sig': No such file or directory
OK   autre clé : signature au bon format (64 hex, indiscernable d'une vraie)
cat: /state.sig: No such file or directory
OK   autre clé : signature bien différente de celle de la vraie clé
FAIL autre clé : exit=127 : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
OK   restore_state : signature valide d'une autre clé ⇒ aucune extraction (HMAC rejette)
FAIL status=refused absent : 
OK   autre clé : aucune clé dans la sortie du step
cp: cannot stat '/state.tar.enc': No such file or directory
cp: cannot stat '/state.sig': No such file or directory
OK   chiffré corrompu re-signé : HMAC valide pour la vraie clé (échec attendu = déchiffrement)
FAIL chiffré corrompu : exit=127 : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
OK   restore_state : déchiffrement en échec ⇒ aucune extraction
FAIL status=refused absent : 
OK   chiffré corrompu : jamais de message de restauration
cp: cannot stat '/state.tar.enc': No such file or directory
cp: cannot stat '/state.sig': No such file or directory
FAIL restore_state exit=127 : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
OK   restore_state : clé absente ⇒ aucune extraction
FAIL message explicite absent : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
OK   restore_state : clé absente ⇒ jamais confondu avec le message « signature invalide »
FAIL status=refused absent : 
FAIL restore_state exit=127 : bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
FAIL status=missing absent : 
OK   B1 : has_state=true + download KO ⇒ le step échoue (exit 127), pas de cold start silencieux
FAIL B1 : status=failed absent : 
OK   B1 : jamais status=missing quand l'état était attendu
OK   B1 : aucun état restauré
FAIL B1 : has_state=false + download KO : rc=127 
cp: cannot stat '/state.tar.enc': No such file or directory
cp: cannot stat '/state.sig': No such file or directory
FAIL B1 : DELETE en échec silencieux : rc=127 log=bash: /tmp/tmp.GpmNqhuOqk/restore.sh: No such file or directory
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
FAIL save_state exit=127 (attendu 1) : bash: /tmp/tmp.GpmNqhuOqk/save.sh: No such file or directory
FAIL message explicite absent : bash: /tmp/tmp.GpmNqhuOqk/save.sh: No such file or directory
OK   save_state : clé absente ⇒ has_state jamais mis à true
FAIL save_state exit=127 : bash: /tmp/tmp.GpmNqhuOqk/save.sh: No such file or directory
FAIL has_state=false attendu : 
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/hook-profile-install-test.sh`

```text
hook-profile-install-test.sh: line 10: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/tests/lib.sh: No such file or directory
hook-profile-install-test.sh: line 14: ko: command not found
hook-profile-install-test.sh: line 15: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
hook-profile-install-test.sh: line 17: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
hook-profile-install-test.sh: line 21: ko: command not found
hook-profile-install-test.sh: line 22: ok: command not found
hook-profile-install-test.sh: line 46: ko: command not found
hook-profile-install-test.sh: line 47: ko: command not found
hook-profile-install-test.sh: line 48: ko: command not found
hook-profile-install-test.sh: line 49: ok: command not found
hook-profile-install-test.sh: line 58: ko: command not found
hook-profile-install-test.sh: line 60: ok: command not found
hook-profile-install-test.sh: line 68: ko: command not found
hook-profile-install-test.sh: line 69: ok: command not found
hook-profile-install-test.sh: line 78: ko: command not found
hook-profile-install-test.sh: line 79: ok: command not found
hook-profile-install-test.sh: line 87: ok: command not found
hook-profile-install-test.sh: line 95: ko: command not found
hook-profile-install-test.sh: line 96: ok: command not found
PASS hook-profile-install : copie LifeOS, chemin plugin, refus des garde-fous
EXIT_CODE=0
```

#### `bash opencode/tests/upstream-fullrun/leaklog-test.sh`

```text
leaklog-test.sh: line 11: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/tests/lib.sh: No such file or directory
leaklog-test.sh: line 17: find_gitleaks: command not found
leaklog-test.sh: line 17: ko: command not found
leaklog-test.sh: line 18: ok: command not found
leaklog-test.sh: line 19: ko: command not found
leaklog-test.sh: line 20: fake_ghp: command not found
leaklog-test.sh: line 30: ko: command not found
leaklog-test.sh: line 31: ok: command not found
jq: error: Could not open file /tmp/tmp.QG1K7WFYL6/gitleaks.json: No such file or directory
leaklog-test.sh: line 32: ko: command not found
grep: /tmp/tmp.QG1K7WFYL6/gitleaks.json: No such file or directory
leaklog-test.sh: line 34: ok: command not found
leaklog-test.sh: line 40: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/redact-log.sh: No such file or directory
leaklog-test.sh: line 40: ko: command not found
grep: /tmp/tmp.QG1K7WFYL6/log.redacted: No such file or directory
leaklog-test.sh: line 42: ok: command not found
leaklog-test.sh: line 46: rand_alnum: command not found
leaklog-test.sh: line 46: rand_alnum: command not found
leaklog-test.sh: line 46: rand_alnum: command not found
leaklog-test.sh: line 50: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/redact-log.sh: No such file or directory
leaklog-test.sh: line 50: ko: command not found
leaklog-test.sh: line 51: /tmp/tmp.QG1K7WFYL6/big.redacted: No such file or directory
leaklog-test.sh: line 51: [: : integer expected
leaklog-test.sh: line 51: /tmp/tmp.QG1K7WFYL6/big.redacted: No such file or directory
leaklog-test.sh: line 51: ko: command not found
grep: /tmp/tmp.QG1K7WFYL6/big.redacted: No such file or directory
grep: /tmp/tmp.QG1K7WFYL6/big.redacted: No such file or directory
leaklog-test.sh: line 53: ko: command not found
grep: /tmp/tmp.QG1K7WFYL6/big.redacted: No such file or directory
leaklog-test.sh: line 54: ko: command not found
grep: /tmp/tmp.QG1K7WFYL6/big.redacted: No such file or directory
leaklog-test.sh: line 55: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/redact-log.sh: No such file or directory
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/redact-log.sh: No such file or directory
leaklog-test.sh: line 58: ko: command not found
leaklog-test.sh: line 59: ok: command not found
leaklog-test.sh: line 61: ko: command not found
leaklog-test.sh: line 63: age-keygen: command not found
leaklog-test.sh: line 64: ok: command not found
env: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/leaklog.sh': No such file or directory
env: use -[v]S to pass options in shebang lines
leaklog-test.sh: line 68: ko: command not found
leaklog-test.sh: line 69: ko: command not found
ls: cannot access '/tmp/tmp.QG1K7WFYL6/artifact': No such file or directory
leaklog-test.sh: line 70: ko: command not found
head: cannot open '' for reading: No such file or directory
leaklog-test.sh: line 71: ko: command not found
grep: : No such file or directory
leaklog-test.sh: line 73: : No such file or directory
leaklog-test.sh: line 73: ok: command not found
leaklog-test.sh: line 76: ko: command not found
leaklog-test.sh: line 78: age: command not found

gzip: stdin: unexpected end of file
tar: Child returned status 1
tar: Error is not recoverable: exiting now
leaklog-test.sh: line 78: ko: command not found
leaklog-test.sh: line 79: ko: command not found
leaklog-test.sh: line 79: ko: command not found
leaklog-test.sh: line 79: ko: command not found
grep: /tmp/tmp.QG1K7WFYL6/x/opencode.log: No such file or directory
leaklog-test.sh: line 80: ko: command not found
jq: error: Could not open file /tmp/tmp.QG1K7WFYL6/x/gitleaks.json: No such file or directory
leaklog-test.sh: line 83: ko: command not found
leaklog-test.sh: line 84: ok: command not found
leaklog-test.sh: line 90: ok: command not found
PASS leaklog : gitleaks bloque, archive .age produite et déchiffrable, aucun secret en clair
EXIT_CODE=0
```

#### `bash opencode/tests/upstream-fullrun/livelog-test.sh`

```text
livelog-test.sh: line 11: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/tests/lib.sh: No such file or directory
FAIL age-keygen
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/merge-signed-carry-test.sh`

```text
merge-signed-carry-test.sh: line 8: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/tests/lib.sh: No such file or directory
merge-signed-carry-test.sh: line 10: ko: command not found
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/merge-signed-carry.sh: No such file or directory
merge-signed-carry-test.sh: line 11: ko: command not found
merge-signed-carry-test.sh: line 65: ko: command not found
merge-signed-carry-test.sh: line 67: ok: command not found
env: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/merge-signed-carry.sh': No such file or directory
env: use -[v]S to pass options in shebang lines
merge-signed-carry-test.sh: line 84: ko: command not found
merge-signed-carry-test.sh: line 85: ko: command not found
merge-signed-carry-test.sh: line 87: ko: command not found
merge-signed-carry-test.sh: line 88: ko: command not found
merge-signed-carry-test.sh: line 89: ok: command not found
env: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/merge-signed-carry.sh': No such file or directory
env: use -[v]S to pass options in shebang lines
merge-signed-carry-test.sh: line 94: ko: command not found
merge-signed-carry-test.sh: line 96: ok: command not found
merge-signed-carry-test.sh: line 108: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/merge-signed-carry.sh: No such file or directory
merge-signed-carry-test.sh: line 108: ko: command not found
merge-signed-carry-test.sh: line 109: ko: command not found
merge-signed-carry-test.sh: line 121: ok: command not found
env: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/merge-signed-carry.sh': No such file or directory
env: use -[v]S to pass options in shebang lines
merge-signed-carry-test.sh: line 135: ko: command not found
merge-signed-carry-test.sh: line 136: ko: command not found
merge-signed-carry-test.sh: line 138: ko: command not found
merge-signed-carry-test.sh: line 139: ok: command not found
env: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/merge-signed-carry.sh': No such file or directory
env: use -[v]S to pass options in shebang lines
merge-signed-carry-test.sh: line 151: ko: command not found
merge-signed-carry-test.sh: line 153: ko: command not found
merge-signed-carry-test.sh: line 154: ok: command not found
merge-signed-carry-test.sh: line 163: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/merge-signed-carry.sh: No such file or directory
merge-signed-carry-test.sh: line 163: ko: command not found
merge-signed-carry-test.sh: line 164: ko: command not found
merge-signed-carry-test.sh: line 165: ko: command not found
merge-signed-carry-test.sh: line 169: ko: command not found
merge-signed-carry-test.sh: line 170: ok: command not found
env: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/merge-signed-carry.sh': No such file or directory
env: use -[v]S to pass options in shebang lines
merge-signed-carry-test.sh: line 197: ko: command not found
merge-signed-carry-test.sh: line 198: ko: command not found
merge-signed-carry-test.sh: line 200: ko: command not found
merge-signed-carry-test.sh: line 201: ko: command not found
merge-signed-carry-test.sh: line 202: ok: command not found
merge-signed-carry-test.sh: line 206: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../.github/workflows/opencode-fullrun.yml: No such file or directory
merge-signed-carry-test.sh: line 207: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../.github/workflows/opencode-fullrun.yml: No such file or directory
merge-signed-carry-test.sh: line 209: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../.github/workflows/opencode-fullrun.yml: No such file or directory
merge-signed-carry-test.sh: line 211: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/../.github/workflows/opencode-fullrun.yml: No such file or directory
merge-signed-carry-test.sh: line 213: ko: command not found
merge-signed-carry-test.sh: line 214: ok: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/autosave.sh: No such file or directory
merge-signed-carry-test.sh: line 217: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/extra-repos.sh: No such file or directory
merge-signed-carry-test.sh: line 218: ko: command not found
merge-signed-carry-test.sh: line 219: ok: command not found
OK   merge-signed-carry-test.sh
EXIT_CODE=0
```

#### `bash opencode/tests/upstream-fullrun/oc-deadline-test.sh`

```text
Traceback (most recent call last):
  File "<stdin>", line 6, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/preannot-test.sh`

```text
preannot-test.sh: line 10: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/opencode/tests/lib.sh: No such file or directory
preannot-test.sh: line 15: ko: command not found
preannot-test.sh: line 16: ko: command not found
preannot-test.sh: line 17: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 23: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 24: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 25: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 26: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 27: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 28: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 30: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
awk: fatal: cannot open file `/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml' for reading: No such file or directory
preannot-test.sh: line 35: ko: command not found
awk: fatal: cannot open file `/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml' for reading: No such file or directory
preannot-test.sh: line 39: ko: command not found
preannot-test.sh: line 40: ko: command not found
preannot-test.sh: line 41: ok: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 45: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 45: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 45: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 45: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml: No such file or directory
preannot-test.sh: line 45: ko: command not found
preannot-test.sh: line 47: ok: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/opencode/ci-preamble.md: No such file or directory
preannot-test.sh: line 50: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/opencode/ci-preamble.md: No such file or directory
preannot-test.sh: line 51: ko: command not found
preannot-test.sh: line 52: ok: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/opencode/preannot.sh: No such file or directory
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/opencode/preannot.sh: No such file or directory
preannot-test.sh: line 56: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/opencode/preannot.sh: No such file or directory
preannot-test.sh: line 57: ko: command not found
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/opencode/preannot.sh: No such file or directory
preannot-test.sh: line 59: ok: command not found
preannot-test.sh: line 62: rand_alnum: command not found
preannot-test.sh: line 141: ko: command not found
EXIT_CODE=127
```

#### `bash opencode/tests/upstream-fullrun/preflight-test.sh`

```text
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
FAIL le step preflight est absent du workflow
résumé : 0 ok, 1 ko
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/prompt-contract-test.sh`

```text
FAIL préambule introuvable : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../ci-preamble.md
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/stall-resume-test.sh`

```text
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 1 rc=127
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log' for reading: No such file or directory
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
cat: /tmp/tmp.VkyXYhiTjR/n: No such file or directory
FAIL 2 rc=127 n=
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 3 rc=127
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log' for reading: No such file or directory
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 4 rc=127
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 5 rc=127
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
cat: /tmp/tmp.VkyXYhiTjR/n: No such file or directory
FAIL 6 rc=127 n=
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
cat: /tmp/tmp.VkyXYhiTjR/n: No such file or directory
FAIL 7 rc=127 n=
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
cat: /tmp/tmp.VkyXYhiTjR/n: No such file or directory
FAIL 8 rc=127 n=
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 9 rc=127
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 10 rc=127
model: opencode/old-free
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 11 rc=127
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 12 rc=127
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 13 rc=127
call 1: run hors-wrapper
env 1: OC_MODEL_MAIN=opencode/deepseek-v4.1-flash-free
envfullrun 1: 
envprofile 1: 
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
cat: /tmp/tmp.VkyXYhiTjR/n: No such file or directory
FAIL 14 rc=127 n=
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 15 rc=127 dt=0s
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log' for reading: No such file or directory
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 16 rc=127 dt=0s
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log' for reading: No such file or directory
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
cat: /tmp/tmp.VkyXYhiTjR/n: No such file or directory
FAIL 17 rc=127 dt=0s n=
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL 18 variable non câblée
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 19 rc=127
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
cat: /tmp/tmp.VkyXYhiTjR/n: No such file or directory
FAIL 20 rc=127 dt=0s n=
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log' for reading: No such file or directory
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 21 rc=127 dt=0s
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log' for reading: No such file or directory
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 22 rc=127
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 23 rc=127
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 24 rc=127 dt=0s
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
stall-resume-test.sh: line 427: [: : integer expected
FAIL 25 câblage workflow absent ou conditionné
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
grep: /tmp/tmp.VkyXYhiTjR/log.status: No such file or directory
FAIL 26 rc=127 errors=
tail: cannot open '/tmp/tmp.VkyXYhiTjR/log.status' for reading: No such file or directory
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/start-step-test.sh`

```text
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL IN_START_STEP absent
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL OC_START_STEP non exporté
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
OK   workflow : deploy n'est pas une valeur acceptée
FAIL verify non transmis : 
FAIL vide : 
FAIL héritage : 
FAIL 'deploy' accepté (rc=127)
FAIL '8' accepté (rc=127)
FAIL '../x' accepté (rc=127)
FAIL 'verify;x' accepté (rc=127)
FAIL 'n'importe' accepté (rc=127)
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/stop-after-step-test.sh`

```text
FAIL workflow introuvable : /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/.github/workflows/opencode-fullrun.yml
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/stop-step-target-agent-test.sh`

```text
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml'
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL IN_STOP_AFTER_STEP absent
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL IN_TARGET_AGENT absent
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL OC_STOP_AFTER_STEP non exporté
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL OC_TARGET_AGENT non exporté
FAIL verify/Silas non transmis : 
FAIL vide : 
FAIL héritage : 
FAIL 'deploy' accepté (rc=127)
FAIL '8' accepté (rc=127)
FAIL '../x' accepté (rc=127)
FAIL 'verify;x' accepté (rc=127)
FAIL 'n'importe' accepté (rc=127)
FAIL '1Silas' accepté (rc=127)
FAIL 'Silas;x' accepté (rc=127)
FAIL '../x' accepté (rc=127)
FAIL 'n'importe quoi' accepté (rc=127)
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/turn-end-test.sh`

```text
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
grep: /tmp/tmp.aohZH2k74z/log.status: No such file or directory
FAIL 1 rc=127
tail: cannot open '/tmp/tmp.aohZH2k74z/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
cat: /tmp/tmp.aohZH2k74z/n: No such file or directory
FAIL 2 rc=127 n=
tail: cannot open '/tmp/tmp.aohZH2k74z/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
cat: /tmp/tmp.aohZH2k74z/n: No such file or directory
FAIL 3 rc=127 n=
tail: cannot open '/tmp/tmp.aohZH2k74z/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
cat: /tmp/tmp.aohZH2k74z/n: No such file or directory
turn-end-test.sh: line 95: [: : integer expected
cat: /tmp/tmp.aohZH2k74z/n: No such file or directory
FAIL 4 rc=127 n=
tail: cannot open '/tmp/tmp.aohZH2k74z/log.status' for reading: No such file or directory
bash: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../run-fullrun.sh: No such file or directory
FAIL 5 rc=127
tail: cannot open '/tmp/tmp.aohZH2k74z/log.status' for reading: No such file or directory
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
FAIL 6 contrat du workflow
grep: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/upstream-fullrun/../../.github/workflows/opencode-fullrun.yml: No such file or directory
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/unit-contract-test.sh`

```text
ko bun introuvable (requis par done_check.sh)
EXIT_CODE=1
```

#### `bash opencode/tests/upstream-fullrun/wippush-test.sh`

```text
wippush-test.sh: line 11: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/tests/lib.sh: No such file or directory
wippush-test.sh: line 14: find_gitleaks: command not found
wippush-test.sh: line 14: ko: command not found
wippush-test.sh: line 25: rand_alnum: command not found
wippush-test.sh: line 35: ko: command not found
wippush-test.sh: line 36: ko: command not found
wippush-test.sh: line 29: /tmp/tmp.GhFM5kZQ13/state/pushed: No such file or directory
wippush-test.sh: line 37: ko: command not found
wippush-test.sh: line 38: ok: command not found
wippush-test.sh: line 43: ko: command not found
wippush-test.sh: line 44: ok: command not found
wippush-test.sh: line 47: fake_ghp: command not found
wippush-test.sh: line 51: ko: command not found
wippush-test.sh: line 52: ko: command not found
wippush-test.sh: line 53: ko: command not found
wippush-test.sh: line 29: /tmp/tmp.GhFM5kZQ13/state/pushed: No such file or directory
wippush-test.sh: line 54: ko: command not found
wippush-test.sh: line 55: ok: command not found
wippush-test.sh: line 59: rand_alnum: command not found
wippush-test.sh: line 64: ko: command not found
wippush-test.sh: line 65: ko: command not found
wippush-test.sh: line 66: ko: command not found
wippush-test.sh: line 68: ok: command not found
wippush-test.sh: line 85: ko: command not found
wippush-test.sh: line 87: ok: command not found
wippush-test.sh: line 100: ko: command not found
wippush-test.sh: line 101: ok: command not found
wippush-test.sh: line 120: ko: command not found
grep: /tmp/tmp.GhFM5kZQ13/push.argv: No such file or directory
grep: /tmp/tmp.GhFM5kZQ13/push.argv: No such file or directory
wippush-test.sh: line 122: ko: command not found
grep: /tmp/tmp.GhFM5kZQ13/push.argv: No such file or directory
cat: /tmp/tmp.GhFM5kZQ13/push.hdr: No such file or directory
wippush-test.sh: line 125: ko: command not found
wippush-test.sh: line 126: ok: command not found
wippush-test.sh: line 145: ko: command not found
wippush-test.sh: line 146: ko: command not found
wippush-test.sh: line 147: kill: (10149) - No such process
wippush-test.sh: line 150: ko: command not found
wippush-test.sh: line 151: ok: command not found
wippush-test.sh: line 157: ok: command not found
wippush-test.sh: line 162: ko: command not found
wippush-test.sh: line 167: ko: command not found
grep: /tmp/tmp.GhFM5kZQ13/push.argv: No such file or directory
wippush-test.sh: line 168: ko: command not found
wippush-test.sh: line 169: ok: command not found
grep: /tmp/tmp.GhFM5kZQ13/state: No such file or directory
grep: /tmp/tmp.GhFM5kZQ13/state-h: No such file or directory
grep: /tmp/tmp.GhFM5kZQ13/state2: No such file or directory
wippush-test.sh: line 174: ok: command not found
PASS wippush : propre, silence, secret bloqué, clé ISA, non-fast-forward, jeton caché, démon, main refusée
EXIT_CODE=0
```

#### `bash opencode/tests/upstream-fullrun/with-emulators-test.sh`

```text
with-emulators-test.sh: line 9: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/tests/lib.sh: No such file or directory
with-emulators-test.sh: line 11: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/allowed-repos.sh: No such file or directory
with-emulators-test.sh: line 15: ko: command not found
with-emulators-test.sh: line 16: ko: command not found
with-emulators-test.sh: line 22: allowed_repo: command not found
with-emulators-test.sh: line 22: ko: command not found
with-emulators-test.sh: line 23: allowed_repo: command not found
with-emulators-test.sh: line 23: ko: command not found
with-emulators-test.sh: line 24: allowed_repo: command not found
with-emulators-test.sh: line 24: ko: command not found
with-emulators-test.sh: line 25: ok: command not found
with-emulators-test.sh: line 28: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/emu-e2e.sh: No such file or directory
with-emulators-test.sh: line 29: ko: command not found
with-emulators-test.sh: line 30: ko: command not found
with-emulators-test.sh: line 31: ko: command not found
with-emulators-test.sh: line 32: ko: command not found
with-emulators-test.sh: line 33: ko: command not found
with-emulators-test.sh: line 34: ko: command not found
with-emulators-test.sh: line 39: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/emu-e2e.sh: No such file or directory
with-emulators-test.sh: line 40: ko: command not found
with-emulators-test.sh: line 41: ok: command not found
with-emulators-test.sh: line 44: rand_alnum: command not found
with-emulators-test.sh: line 119: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/emu-e2e.sh: No such file or directory
with-emulators-test.sh: line 120: ko: command not found
with-emulators-test.sh: line 121: ko: command not found
with-emulators-test.sh: line 122: ko: command not found
with-emulators-test.sh: line 124: ok: command not found
with-emulators-test.sh: line 130: /home/runner/work/antenly-ci/antenly-ci/target/lifeos-ci-seed/opencode/tests/emu-e2e.sh: No such file or directory
with-emulators-test.sh: line 132: ko: command not found
with-emulators-test.sh: line 133: ok: command not found
with-emulators-test.sh: line 139: ko: command not found
with-emulators-test.sh: line 144: ko: command not found
with-emulators-test.sh: line 152: ko: command not found
EXIT_CODE=127
```

### Sortie brute — `shellcheck opencode/*.sh targets/*.sh`

```text
EXIT_CODE=0
```

Aucun finding (exit=0) ; la sortie ne contient que la ligne de code de sortie ci-dessus.

### Sortie brute — `actionlint`

```text
1.7.7
installed by downloading from release page
built with go1.23.4 compiler for linux/amd64
--- actionlint run ---
.github/workflows/fr-plan-vera.yml:83:11: could not read reusable workflow file for "./.github/workflows/_next.yml": open /home/runner/work/antenly-ci/antenly-ci/target/.github/workflows/_next.yml: no such file or directory [workflow-call]
   |
83 |     uses: ./.github/workflows/_next.yml
   |           ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~
.github/workflows/task.yml:66:11: could not read reusable workflow file for "./.github/workflows/_agent-run.yml": open /home/runner/work/antenly-ci/antenly-ci/target/.github/workflows/_agent-run.yml: no such file or directory [workflow-call]
   |
66 |     uses: ./.github/workflows/_agent-run.yml
   |           ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
EXIT_CODE=1
```

Contrôle complémentaire, depuis une copie de `lifeos-ci-seed/` placée à la racine (hors dépôt git), pour distinguer un vrai défaut de workflow de l'artefact de résolution de chemins déjà documenté en Fix2 :

```text
1.7.7
installed by downloading from release page
built with go1.23.4 compiler for linux/amd64
--- actionlint run (copie à la racine, hors dépôt git) ---
EXIT_CODE=0
```

### Liste des échecs (fichier, message)

Échecs avec code de sortie non nul :

| Fichier | Exit | Message principal |
|---|---:|---|
| `opencode/tests/upstream-fullrun/agent-idle-test.sh` | 1 | `run-fullrun.sh` introuvable ; `log.status` absent ; `FAIL défaut` / `FAIL réglage` ; gardes `Forge=abc/0/721/=5/Forge=40,Forge=50/Fo rge=5/Forge=40,/1Forge=5/Forge=-3/Forge=40;rm` acceptées à tort ; `opencode.json` introuvable |
| `opencode/tests/upstream-fullrun/chain-step-test.sh` | 1 | `../../.github/workflows/opencode-fullrun.yml` introuvable ; `chain.sh` et `guard.sh` absents ; `FAIL phase inattendue`, `FAIL M3`, `FAIL kind=echec`, `FAIL kind=termine`, `FAIL safe_raw`, `FAIL garde` |
| `opencode/tests/upstream-fullrun/checkpoint-watchdog-verdict-test.sh` | 1 | `ko bun introuvable (requis par done_check.sh)` |
| `opencode/tests/upstream-fullrun/done-check-test.sh` | 1 | `ko bun introuvable (requis par done_check.sh)` |
| `opencode/tests/upstream-fullrun/first-link-prompt-test.sh` | 1 | `guard.sh`, `prep.sh`, `chain.sh` absents ; `guard.sh`/`prep.sh`/`chain.sh` non générés ; `ci-preamble.md` introuvable ; `FAIL prep`, `FAIL garde`, `FAIL chain`, `FAIL run-fullrun.sh` |
| `opencode/tests/upstream-fullrun/hmac-state-test.sh` | 1 | `save.sh` et `restore.sh` absents ; `opencode-fullrun.yml` introuvable ; `FAIL save_state`, `FAIL restore_state`, `FAIL status=refused/missing/failed/restored`, fichiers `/state.tar.enc` et `/state.sig` introuvables |
| `opencode/tests/upstream-fullrun/livelog-test.sh` | 1 | `opencode/tests/tests/lib.sh` introuvable ; `FAIL age-keygen` |
| `opencode/tests/upstream-fullrun/oc-deadline-test.sh` | 1 | `FileNotFoundError` sur `../../.github/workflows/opencode-fullrun.yml` |
| `opencode/tests/upstream-fullrun/preannot-test.sh` | 127 | `opencode/opencode/tests/lib.sh` introuvable ; `ko` non trouvé ; `rand_alnum` non trouvé ; workflow et `preannot.sh` introuvables |
| `opencode/tests/upstream-fullrun/preflight-test.sh` | 1 | `opencode-fullrun.yml` introuvable ; `FAIL le step preflight est absent du workflow` |
| `opencode/tests/upstream-fullrun/prompt-contract-test.sh` | 1 | `FAIL préambule introuvable` (`../ci-preamble.md`) |
| `opencode/tests/upstream-fullrun/stall-resume-test.sh` | 1 | `../run-fullrun.sh` introuvable (rc=127 sur les cas 1 à 26) ; `log`/`log.status` absents ; `FAIL câblage workflow absent ou conditionné` |
| `opencode/tests/upstream-fullrun/start-step-test.sh` | 1 | `opencode-fullrun.yml` introuvable ; `FAIL IN_START_STEP absent`, `FAIL OC_START_STEP non exporté`, `FAIL verify non transmis`, `FAIL vide`, `FAIL héritage`, valeurs invalides `deploy/8/../x/verify;x/n'importe` acceptées (rc=127) |
| `opencode/tests/upstream-fullrun/stop-after-step-test.sh` | 1 | `FAIL workflow introuvable` (`opencode/.github/workflows/opencode-fullrun.yml`) |
| `opencode/tests/upstream-fullrun/stop-step-target-agent-test.sh` | 1 | `opencode-fullrun.yml` introuvable ; `FAIL IN_STOP_AFTER_STEP absent`, `FAIL IN_TARGET_AGENT absent`, `FAIL OC_STOP_AFTER_STEP non exporté`, `FAIL OC_TARGET_AGENT non exporté`, validations invalides acceptées (rc=127) |
| `opencode/tests/upstream-fullrun/turn-end-test.sh` | 1 | `../run-fullrun.sh` introuvable (rc=127 sur les cas 1 à 5) ; `log.status` absent ; `FAIL contrat du workflow` |
| `opencode/tests/upstream-fullrun/unit-contract-test.sh` | 1 | `ko bun introuvable (requis par done_check.sh)` |
| `opencode/tests/upstream-fullrun/with-emulators-test.sh` | 127 | `opencode/tests/tests/lib.sh`, `opencode/tests/allowed-repos.sh` et `opencode/tests/emu-e2e.sh` introuvables ; `ko`, `ok`, `allowed_repo`, `rand_alnum` non trouvés |

Succès (exit=0) mais sortie d'erreurs (dépendances/chemins manquants, non bloquants pour le code de sortie) :

| Fichier | Exit | Bruit observé |
|---|---:|---|
| `opencode/tests/upstream-fullrun/allowed-repos-cwd-test.sh` | 0 | `ok`/`ko`/`fake_ghp: command not found` ; dépôt `Galass_Driver` et `allowed-repos.sh` absents |
| `opencode/tests/upstream-fullrun/extra-repos-test.sh` | 0 | `ok`/`ko: command not found` ; dépôt `galass-emu-actions-pub` et branche `feat/ms` absents |
| `opencode/tests/upstream-fullrun/ffmpeg-install-test.sh` | 0 | `ok`/`ko: command not found` ; `opencode/.github/workflows/opencode-fullrun.yml` introuvable |
| `opencode/tests/upstream-fullrun/hook-profile-install-test.sh` | 0 | `opencode/tests/tests/lib.sh` introuvable ; `ok`/`ko` non trouvés ; workflow introuvable |
| `opencode/tests/upstream-fullrun/leaklog-test.sh` | 0 | `ko: command not found` ; artefact absent ; `age: command not found` |
| `opencode/tests/upstream-fullrun/merge-signed-carry-test.sh` | 0 | `ok`/`ko: command not found` ; `merge-signed-carry.sh` introuvable ; workflow introuvable |
| `opencode/tests/upstream-fullrun/wippush-test.sh` | 0 | `ko: command not found` ; `push.argv`/`push.hdr` absents |

Bilan vérification seule :

- `bash opencode/tests/run-all.sh` : **PASS**, 17/17, exit=0.
- 25 scripts `upstream-fullrun/` non lancés par `run-all.sh` : **18 échecs** (16 exit=1, 2 exit=127) et **7 succès avec bruit** (exit=0).
- `shellcheck opencode/*.sh targets/*.sh` : **PASS**, exit=0, aucun finding.
- `actionlint .github/workflows/*.yml` depuis `lifeos-ci-seed/` : **ÉCHEC**, exit=1, 2 erreurs `workflow-call` (`fr-plan-vera.yml:83` → `_next.yml`, `task.yml:66` → `_agent-run.yml`) dues à la résolution des chemins `./.github/workflows/` depuis la racine du dépôt parent.
- Même `actionlint` depuis une copie de `lifeos-ci-seed/` à la racine : **PASS**, exit=0.

Aucune correction n'a été apportée.

## Fix2b (2026-11-25)

### Tests nécessitant bun

Bun n'est pas installé dans ce run (`command -v bun` → absent), conformément à la consigne
« n'installe pas bun ». Les tests suivants s'arrêtent dès le chargement de
`opencode/tests/upstream-fullrun/verdict-cli.lib` sur
`ko bun introuvable (requis par done_check.sh)`, avant toute assertion :

- `opencode/tests/upstream-fullrun/checkpoint-watchdog-verdict-test.sh` — **besoin de bun**
- `opencode/tests/upstream-fullrun/done-check-test.sh` — **besoin de bun**
- `opencode/tests/upstream-fullrun/unit-contract-test.sh` — **besoin de bun**

`preflight-test.sh` n'a pas besoin de bun : il fabrique un faux `bun` pour la logique du step et
ne lance la section « vrai CLI lifeos » que si `bun` et `FullRunPreflight.ts` sont présents.
Bun sera ajouté à `ci.yml` au run suivant.
