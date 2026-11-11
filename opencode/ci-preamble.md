# Contexte CI (antenly-ci, GitHub Actions) — à lire avant le prompt FullRun

Tu tournes sur un runner GitHub Actions public, pas sur la box.

- Dépôt de travail : le répertoire courant (`$ANTENLY_DIR`), checkout de `LordThiouk/antenly`
  sur la branche `$OC_BRANCH`. Les chemins `/home/box/...` et `/workspace/...` du prompt
  désignent ici `$HOME/...` et ce checkout (`/home/box` est un lien vers `$HOME`).
- **Tu ne pousses rien.** Pas de `git push`, pas de `gh`, pas de PR, pas de commentaire : tu n'as
  aucun jeton d'écriture. Fais des commits locaux sur `$OC_BRANCH` uniquement (jamais de
  `git reset --hard`, `rebase`, `commit --amend` sur des commits déjà présents au départ :
  l'historique doit rester une suite du SHA de départ). Le workflow pousse lui-même tes
  commits sur `$OC_BRANCH` à la fin, sans force.
- Ne change pas de branche, ne crée pas d'autre branche, ne touche pas à `.github/workflows/`.
- **Logs publics, mais ta sortie n'y est jamais affichée.** N'écris quand même aucun secret
  nulle part (fichiers, commits, rapport).
- Rapport final : écris-le dans `$OC_REPORT` (hors dépôt). Le workflow le versionne dans
  `.fullrun/$OC_JOB_DONE.md` sur la branche. Mets-y : étapes faites, commits, compte des
  tests, verdicts avec SHA, ISC cochés/total, ce qui reste et l'étape de reprise.
- **Reprise.** Ce run peut être une relance. Avant d'agir, lis `.fullrun/$OC_JOB_DONE.md`
  s'il existe et l'état de l'ISA sur la branche, puis reprends à la première étape non
  terminée au lieu de tout refaire.
- Modèles : principal et Forge `$OC_MODEL_MAIN`, Max `$OC_MODEL_MAX` (gratuits opencode).
- Pas de VPS, pas de FreeLLM, pas d'ACRCloud, pas de Mac. Pas de merge, pas de déploiement.

---

