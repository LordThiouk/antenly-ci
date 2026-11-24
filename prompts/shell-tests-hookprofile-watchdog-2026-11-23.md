# Tâche : corriger les tests shell hook-profile-install et watchdog (antenly-ci, hors FullRun)

## Contexte

Branche de travail (déjà créée et poussée, à utiliser telle quelle) : `fix/shell-tests-hookprofile-watchdog-2026-11-23` (depuis `main`).

Dans le run https://github.com/LordThiouk/antenly-ci/actions/runs/45292062034 (CI antenly@7366d34, après installation d'`age` par #46) :

- `livelog-test.sh` passe.
- `leaklog-test.sh` n'est plus en « age absent » (archive `.age` créée, rien en clair). Le rouge restant « clé privée absente : déchiffrement non vérifiable » est hors périmètre.
- Échecs à corriger uniquement :
  - `opencode/tests/hook-profile-install-test.sh` : `FAIL le refus d'un garde-fou n'est pas signalé`
  - `opencode/tests/watchdog-test.sh` : `FAIL passage tué non relancé`

## Objectifs

1. Diagnostiquer la cause réelle de chaque échec (lire les tests et le code qu'ils exercent). Ne pas affaiblir, relâcher, sauter ni supprimer les tests.
2. Corriger le code (ou le câblage CI nécessaire) pour que le comportement attendu par les tests soit respecté.
3. Exécuter localement les tests shell, au minimum `opencode/tests/hook-profile-install-test.sh` et `opencode/tests/watchdog-test.sh`, et de préférence la suite `opencode/tests/*-test.sh`. Les deux tests ciblés doivent passer. Si un autre test casse, le corriger seulement si c'est un effet de ta modification. Ne pas élargir le périmètre (leaklog « clé privée absente » reste hors scope).
4. Committer sur la branche courante. Ne jamais pousser (`git push` est géré par le workflow après gitleaks), jamais toucher `main`, jamais de force-push, aucun secret en dur.
5. Ouvrir une PR vers `main` sur `LordThiouk/antenly-ci` (pas de merge). Si `gh` n'est pas utilisable, rédiger titre et corps prêts dans `/tmp/task_done.md`.
6. Avant de terminer, écrire un résumé factuel (cause de chaque échec, fichiers modifiés, SHA, résultats des tests) dans `/tmp/task_done.md`.
