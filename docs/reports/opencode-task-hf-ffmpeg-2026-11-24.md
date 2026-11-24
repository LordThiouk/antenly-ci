# opencode-task : corpus Hugging Face + ffmpeg pour la cible antenly

Date : 2026-11-24
Branche : `feat/opencode-task-hf-ffmpeg-2026-11-24`
Patch : `docs/patches/opencode-task-hf-ffmpeg-2026-11-24.patch`

## Objectif

Permettre au vrai test radio des moteurs d'empreinte de la cible `antenly` de
lire le corpus privé Hugging Face `LordThiouk/antenly-corpus` (~2,4 Go, `.opus`)
et de décoder l'Opus avec `ffmpeg`/`ffprobe`.

## Ce qui change

Le patch modifie uniquement `.github/workflows/opencode-task.yml`, et seulement
pour `inputs.target_repo == 'antenly'` :

1. **ffmpeg/ffprobe** : ajout des trois étapes au même schéma que
   `opencode-fullrun.yml` :
   - `FedericoCarboni/setup-ffmpeg` épinglé par SHA
     (`37062fbf7149fc5578d6c57e08aed62458b375d6`, v3.1), `continue-on-error`,
     `timeout-minutes: 10` ;
   - secours `apt-get install -y ffmpeg` si le binaire statique échoue ;
   - vérification franche de la présence de `ffmpeg` **et** `ffprobe` dans le
     `PATH`.
2. **CLI Hugging Face** : nouvelle étape qui installe
   `huggingface_hub[cli]` via `uv tool install` (déjà installé à l'étape
   précédente), avec repli `python3 -m pip install --user
   --break-system-packages`. Un `::warning` est émis si ni `hf` ni
   `huggingface-cli` n'est disponible.
3. **Inputs `with_hf_corpus` (booléen, défaut `false`) et `hf_corpus` (chaîne, vide par
   défaut)** : quand `with_hf_corpus` vaut `true`, une étape lit la liste `hf_corpus` sur la
   branche cible, l'assainit (une entrée par ligne, pas d'absolu ni de `..`, doublons retirés,
   plafond 400 fichiers) puis télécharge uniquement ces fichiers avec
   `hf download LordThiouk/antenly-corpus` (repli `huggingface-cli download`) dans
   `$RUNNER_TEMP/corpus/antenly-corpus`.
   - **Hors de `target/`** : le corpus vit sous `$RUNNER_TEMP`, donc la porte
     `gitleaks --source target` et le push fast-forward ne le voient jamais ;
     un garde-fou explicite refuse tout chemin situé sous `target/`.
   - **Lecture seule** après téléchargement : `chmod -R a-w`.
   - **Variable** `ANTENLY_CORPUS_DIR` exposée via `GITHUB_ENV`.
   - **Prompt** : une section « Corpus radio Hugging Face (lecture seule) » est
     ajoutée à la fin de `$RUNNER_TEMP/oc/prompt.md` pour signaler le chemin à
     opencode et rappeler de ne pas modifier le corpus.
   - **Échec non bloquant** : `continue-on-error: true` et gestion explicite du
     code retour ; un `::warning::` et un `### Corpus HF (optionnel)` dans
     `$GITHUB_STEP_SUMMARY` indiquent l'absence de `HF_TOKEN`, de liste, ou
     l'échec du téléchargement.
4. **`HF_TOKEN`** : le secret n'est exposé qu'à l'étape de téléchargement du
   corpus, via `env`. Il n'est jamais transmis à l'environnement d'opencode,
   jamais affiché (`set +x`, sorties de téléchargement redirigées), jamais écrit
   dans le prompt et jamais commité.

Rien d'autre ne change : entrées existantes, jeton de la cible, porte gitleaks,
refus de modifier `.github/workflows` sur `antenly`, push fast-forward et
notification restent identiques.

## Pourquoi c'est sûr

- Le corpus et `HF_TOKEN` ne sortent pas du runner : corpus dans `$RUNNER_TEMP`,
  secret seulement en variable d'environnement de l'étape de téléchargement.
- Aucun fichier du corpus n'est sous `target/`, donc jamais inclus dans les
  commits vérifiés par gitleaks ni poussés.
- Le téléchargement est optionnel et non bloquant ; sans `HF_TOKEN` ou en cas
  d'échec réseau, la tâche opencode continue et le résumé CI le documente.
- `ffmpeg`/`ffprobe` sont installés selon le schéma déjà éprouvé de
  `opencode-fullrun.yml`.

## Vérifications effectuées

- `git apply --check docs/patches/opencode-task-hf-ffmpeg-2026-11-24.patch` :
  OK sur un arbre propre à l'état de `main`.
- Validation YAML du workflow patché avec `python3` + `PyYAML` : OK ; les inputs
  `with_hf_corpus` (booléen, défaut `false`) et `hf_corpus` (liste) ainsi que
  les nouvelles étapes sont présents ; `HF_TOKEN` figure uniquement dans
  l'`env` de l'étape de téléchargement.
- `bash -n` sur tous les blocs `run` du workflow patché : OK.
- `shellcheck -S error` : aucune erreur dans les étapes ajoutées ; seules
  restent des faux positifs `SC2296` sur les expressions `${{ ... }}` déjà
  présentes avant le patch.
- `yamllint` (line-length/truthy désactivés) : aucune erreur.
- `gitleaks` sur le patch et ce rapport : aucune valeur de secret.

## Application

Depuis la racine du dépôt, sur `main` :

```sh
git apply docs/patches/opencode-task-hf-ffmpeg-2026-11-24.patch
```

## Utilisation

- Sans corpus : lancer la tâche comme avant (`with_hf_corpus` reste `false`).
- Avec corpus : cocher `with_hf_corpus`, renseigner `hf_corpus` (chemin de la
  liste sur la branche cible, 400 fichiers max) et s'assurer que le secret
  `HF_TOKEN` existe dans le dépôt `LordThiouk/antenly-ci` et donne accès en
  lecture au dataset privé `LordThiouk/antenly-corpus`.
- Les corrections de revue (C1, C2, A1-A3, S2) sont détaillées dans
  `docs/reports/revue-pr51-2026-11-24.md` et appliquées par
  `docs/patches/fix-pr51-2026-11-24.patch`.
- Un prompt ciblant `antenly` peut s'appuyer sur `$ANTENLY_CORPUS_DIR` (sans le
  coder en dur) uniquement lorsque le téléchargement a réussi.
