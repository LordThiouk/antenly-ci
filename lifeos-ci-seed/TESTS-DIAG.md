# Diagnostic Fix2d4 — 7 tests upstream-fullrun restants

Branche `seed/lifeos-ci-2026-11-24` (HEAD `18eaa33`). Aucun code modifié : diagnostic seul.
Références comparées : `antenly-ci` `main` `22f672e` (racine du dépôt) et `galass-ci` `main`
`13dc999` (clone lecture seule). Outils locaux : `ripgrep 14.1.1` et `bun 1.4.5` installés dans
`/tmp/bin` et `/tmp/bun/bin` ; `PyYAML` disponible.

Limite d'environnement : le dépôt `LordThiouk/lifeos` est privé et n'est pas cloné ici. Les tests
qui sourcent `verdict-cli.lib` (donc exigent `LIFEOS/TOOLS/FullRunVerdict.ts`) ne sont pas
exécutables dans ce bac à sable : `checkpoint-watchdog-verdict`, `done-check`, `unit-contract`
échouent tous avec `ko FullRunVerdict.ts introuvable`. Ce n'est pas un orphelin : le même message
est obtenu depuis `antenly-ci` et `galass-ci`, dont les CI clonent lifeos.

Les fichiers de test copiés sont identiques à leur original à 2–4 lignes près (chemin
`HERE/../../..`). Les échecs viennent donc des fichiers **lus** (workflow, scripts, README), pas
des tests.

| Test | Passe où (exécuté / source) | Fichiers à recopier (écart avec l'original) | Orphelin |
| --- | --- | --- | --- |
| `checkpoint-watchdog-verdict` | `antenly-ci` main (source du test ; non rejouable ici sans lifeos privé) | Aucun écart comportemental : `opencode/run-fullrun.sh` = 3 lignes (commentaires `shellcheck`), `opencode/checkpoint.sh` = 3 lignes (guillemets `STATUS`, repli `TARGET_DIR` ; le test passe `ANTENLY_DIR`), `opencode/done_check.sh` identique. Le blocage du seed est le checkout lifeos absent, pas la version. | non |
| `done-check` | `antenly-ci` main (source du test ; non rejouable ici sans lifeos privé) | `README.md` (400 lignes ; la phrase « Le verdict est lu par le CLI lifeos » manque) ; `.github/workflows/ci.yml` (pin lifeos `4fac2d5`, `OC_REQUIRE_PROD_TESTS: "1"`, marqueur `etc/fullrun-done-test-mode` absents) ; `.github/workflows/ci-scripts.yml` (absent du seed). `done_check.sh` identique, workflow fullrun identique à 9 lignes près (ajouts `allowed-repos`). | non |
| `hmac-state` | `galass-ci` main (rc 0) ; `antenly-ci` root rc 0 mais avec une version plus ancienne du test | `.github/workflows/opencode-fullrun.yml`, step `restore_state` (18 lignes : `status=failed` quand `has_state=true` + `gh run download` échoue, `status=missing` réservé à l'absence légitime, `if` sur `chain_state.prev`, DELETE non silencieux). `save_state` et permissions du job identiques. | non |
| `preflight` | `antenly-ci` root (24 ok, 0 ko) | `README.md` uniquement : 4 contrôles en échec dans le seed (« Préflight du lien », cause de la redescente, règle du périmètre, table des codes 0/2/3/4/5/64/70). Le step `preflight` du workflow est déjà conforme (20 ok, placement/`--isa`/codes OK). | non |
| `stop-step-target-agent` | `galass-ci` main (rc 0) | `opencode/run-fullrun.sh` : le seed a la version **antenly** (exige `ANTENLY_DIR`, le test ne fournit que `TARGET_DIR`) ; recopier la version **galass** (accepte `TARGET_DIR`, exporte `FULLRUN_STOP_AFTER_STEP`/`FULLRUN_TARGET_AGENT` et refuse `deploy`/valeurs invalides avec rc 90). Les 5 contrôles workflow passent déjà. | non |
| `unit-contract` | `galass-ci` main (source du test ; non rejouable ici sans lifeos privé) | `.github/workflows/opencode-fullrun.yml`, step `chain` (93 lignes d'écart : version antenly `stop_after_step`/`ANTENLY_DIR` au lieu de la version galass attendue) ; `LIFEOS/TOOLS/FullRunPipeline.ts` (outil lifeos externe, non copiable dans le dépôt). | non |
| `with-emulators` | `galass-ci` main (rc 0) | `.github/workflows/opencode-fullrun.yml` : le seed n'a ni input `with_emulators`, ni installation/gel de `emu-e2e.sh`, ni ligne sudoers `.../emu-e2e.sh status *` (échec immédiat « sudoers : status absent », puis les contrôles workflow suivants échoueraient aussi). `opencode/emu-e2e.sh`, `opencode/allowed-repos.sh` et `opencode/tests/lib.sh` sont identiques. | non |

## Preuves d'exécution

- `hmac-state` : seed rc 1 (`FAIL B1 : has_state=true + download KO accepté`, `status=failed absent`, `status=missing publié à tort`, `DELETE en échec silencieux`) ; antenly root rc 0 ; galass rc 0.
- `preflight` : seed rc 1 (`20 ok, 4 ko`, uniquement README) ; antenly root rc 0 (`24 ok, 0 ko`) ; test absent de galass.
- `stop-step-target-agent` : seed rc 1 (`verify/Silas non transmis`, `deploy`/`8`/`../x` acceptés) ; galass rc 0 ; test absent d'antenly.
- `with-emulators` : seed rc 1 au premier `ko` (`FAIL sudoers : status absent de la liste autorisée`) ; galass rc 0 ; test absent d'antenly.
- `checkpoint-watchdog-verdict`, `done-check`, `unit-contract` : `ko FullRunVerdict.ts introuvable` sur les trois arbres (seed, antenly, galass) faute du checkout privé lifeos.

## Conséquence

Le seed mélange deux origines : tests `antenly-ci` (`checkpoint`, `done-check`, `preflight`) et
tests `galass-ci` (`hmac-state`, `stop-step-target-agent`, `unit-contract`, `with-emulators`),
alors que ses scripts/workflow sont majoritairement la version `antenly-ci`. Recopier les fichiers
ci-dessus par test est donc nécessaire mais insuffisant : `done-check` et `unit-contract` lisent
en plus des éléments propres à `antenly-ci` (CI pinnée, `ci-scripts.yml`) ou à lifeos, et le
`.github/workflows/ci.yml` du seed ne clone pas lifeos (contrairement à `ci-scripts.yml` antenly et
`ci.yml` galass). Aucun des sept tests n'est orphelin.
