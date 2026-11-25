# Nettoyage antenly-ci — garder uniquement la CI produit

Périmètre : ce dépôt ne doit garder que ce qui construit, teste, vérifie ou déploie
le PRODUIT (`LordThiouk/antenly`) : workflows de tests produit, émulateurs, contrôles
produit, CI déclenchée par les PR produit.

La machinerie générique opencode / FullRun / agents / prompts / garde-fous vit
désormais dans `LordThiouk/lifeos-ci` ; elle est retirée d'ici.

| Fichier | Verdict | Raison |
| --- | --- | --- |
| `.github/workflows/ci-scripts.yml` | REMOVE | Teste les scripts opencode génériques (`opencode/tests/*-test.sh`), dupliqué dans lifeos-ci. |
| `.github/workflows/ci.yml` | KEEP | CI produit : rust, python, security-stack, preannot-ina, licences, secrets sur `antenly`. |
| `.github/workflows/inventory-pass2.yml` | KEEP | Passe 2 de la sonde d'inventaire produit `antenly` (rapport, gates, PR). |
| `.github/workflows/inventory-probe.yml` | KEEP | Passe 1 de la sonde d'inventaire produit `antenly`. |
| `.github/workflows/isa-human-tick.yml` | REMOVE | Outillage de gouvernance ISA LifeOS (coche une claim), pas de la CI produit. |
| `.github/workflows/language.yml` | KEEP | Passe de langue produit sur le corpus `full-v1` d'`antenly`. |
| `.github/workflows/opencode-fullrun.yml` | REMOVE | Machinerie opencode FullRun générique, vit dans lifeos-ci. |
| `.github/workflows/opencode-task.yml` | REMOVE | Machinerie opencode Task générique, vit dans lifeos-ci (`task.yml`). |
| `.github/workflows/pr-dispatch.yml` | KEEP | Déclenche la CI produit `ci.yml` pour les PR ouvertes d'`antenly`. |
| `README.md` | KEEP | Documentation du dépôt, réécrite pour décrire la CI produit. |
| `CLEANUP.md` | KEEP | Ce tableau d'audit du nettoyage. |
| `docs/patches/diag-arret-etape-2026-11-24.patch` | REMOVE | Patch de correctif FullRun générique. |
| `docs/patches/fix-pr51-2026-11-24.patch` | REMOVE | Patch de correctif opencode-task générique. |
| `docs/patches/fix-pr52-2026-11-24.patch` | REMOVE | Patch de correctif FullRun générique. |
| `docs/patches/fix-pr52-r2-2026-11-24.patch` | REMOVE | Patch de correctif FullRun générique. |
| `docs/patches/fix-pr52-r3-2026-11-24.patch` | REMOVE | Patch de correctif FullRun générique. |
| `docs/patches/opencode-task-hf-ffmpeg-2026-11-24.patch` | REMOVE | Patch de correctif opencode-task générique. |
| `docs/patches/opencode-task-read-acr-2026-11-24.patch` | REMOVE | Patch de correctif opencode-task générique. |
| `docs/reports/diag-arret-etape-2026-11-24.md` | REMOVE | Rapport sur la machinerie FullRun générique. |
| `docs/reports/opencode-task-hf-ffmpeg-2026-11-24.md` | REMOVE | Rapport sur la machinerie opencode-task générique. |
| `docs/reports/opencode-task-read-acr-2026-11-24.md` | REMOVE | Rapport sur la machinerie opencode-task générique. |
| `docs/reports/revue-diag-arret-etape-2026-11-24.md` | REMOVE | Revue de correctifs FullRun génériques. |
| `docs/reports/revue-pr51-2026-11-24.md` | REMOVE | Revue de correctifs opencode-task génériques. |
| `opencode/autosave-deny.txt` | REMOVE | Liste de garde-fous opencode générique, dupliquée dans lifeos-ci. |
| `opencode/autosave.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/bench-capped` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/checkpoint.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/ci-preamble.md` | REMOVE | Préambule de prompt FullRun générique. |
| `opencode/config/opencode.json` | REMOVE | Configuration opencode générique, dupliquée dans lifeos-ci. |
| `opencode/done-check-call.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/done_check.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/install-hook-profile.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/leaklog.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/livelog.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/log-recipient.txt` | REMOVE | Destinataire de journal opencode générique. |
| `opencode/preannot.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/progress.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/redact-log.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/run-fullrun.sh` | REMOVE | Orchestrateur FullRun générique, dupliqué dans lifeos-ci. |
| `opencode/split-diff.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/step-agents.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/wippush.sh` | REMOVE | Script opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/agent-idle-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/autosave-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/chain-step-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/checkpoint-watchdog-verdict-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/done-check-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/ffmpeg-install-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/first-link-prompt-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/hmac-state-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/hook-profile-install-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/internals-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/leaklog-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/lib.sh` | REMOVE | Bibliothèque partagée des tests opencode génériques. |
| `opencode/tests/livelog-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/memcap-livelog-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/memcap-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/oc-deadline-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/preannot-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/preflight-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/prompt-contract-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/redact-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/split-diff-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/stall-resume-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/start-step-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/stop-after-step-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/subagent-fail-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/turn-end-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/verdict-cli.lib` | REMOVE | Bibliothèque partagée des tests opencode génériques. |
| `opencode/tests/watchdog-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `opencode/tests/wippush-test.sh` | REMOVE | Test de la machinerie opencode générique, dupliqué dans lifeos-ci. |
| `prompts/clean-product-ci.md` | REMOVE | Prompt de nettoyage générique, dupliqué dans lifeos-ci. |
