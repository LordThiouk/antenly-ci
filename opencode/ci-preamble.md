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
  `.fullrun/${OC_JOB}_DONE.md` sur la branche. Mets-y : étapes faites, commits, compte des
  tests, verdicts avec SHA, ISC cochés/total, ce qui reste et l'étape de reprise.
- **Reprise.** Ce run peut être une relance. Avant d'agir, lis `.fullrun/${OC_JOB}_DONE.md`
  s'il existe et l'état de l'ISA sur la branche, puis reprends à la première étape non
  terminée au lieu de tout refaire.
- Modèles : principal et Forge `$OC_MODEL_MAIN`, Max `$OC_MODEL_MAX` (gratuits opencode).
- Pas de VPS, pas de FreeLLM, pas d'ACRCloud, pas de Mac. Pas de merge, pas de déploiement.

## Enveloppe mémoire et bench-capped

Tout le processus opencode tourne dans une enveloppe mémoire de 10 Go (systemd-run / cgroup v2 /
prlimit selon le runner). **Tout calcul lourd ou benchmark** (compilation, inférence, traitement
de corpus volumineux) doit passer par `bench-capped` :

```bash
bench-capped python3 mon_script.py       # cap 8 Go par défaut
bench-capped --limit 4294967296 cargo bench  # cap personnalisé (4 Go)
```

Si la commande dépasse le cap, elle est tuée par le noyau (OOM cgroup) mais opencode survit.
La ligne `[oom] <commande> <peak>` est écrite dans le journal. Un exit non nul signale l'échec.

**Règle commits wip :** faire un `wip:` commit **avant** et **après** chaque bench ou calcul lourd.
Cela garantit que le travail est sauvegardé même en cas d'OOM, et que le pipeline de push
périodique peut transmettre l'état.

## Preannot (seulement si le run en a besoin)

Le preannot (`ci.yml`, job `preannot-ina` : vrai inaSpeechSegmenter + TensorFlow CPU) tourne
sur GitHub, pas sur ce runner. Si ta tâche a besoin de ce verdict, appelle seulement :

    /opt/fullrun-tools/preannot.sh run

L'outil déclenche `ci.yml` sur `$OC_BRANCH` (toute la CI ; le job `preannot-ina` en fait partie),
attend un délai borné, télécharge les artefacts éventuels dans le dossier du job et n'affiche
qu'un verdict + un court extrait. Tu n'as aucun jeton : pas de `gh` toi-même, pas de copie du
script.

---

