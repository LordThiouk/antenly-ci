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
3. **Input optionnel `with_hf_corpus`** (`type: boolean`, défaut `false`) :
   quand il vaut `true`, une étape télécharge le dataset avec
   `hf download LordThiouk/antenly-corpus --repo-type dataset` (repli
   `huggingface-cli download`) dans `$RUNNER_TEMP/corpus/antenly-corpus`.
   - **Hors de `target/`** : le corpus vit sous `$RUNNER_TEMP`, donc la porte
     `gitleaks --source target` et le push fast-forward ne le voient jamais ;
     un garde-fou explicite refuse tout chemin situé sous `target/`.
   - **Lecture seule** après téléchargement : `chmod -R a-w`.
   - **Variable** `ANTENLY_CORPUS_DIR` exposée via `GITHUB_ENV`.
   - **Prompt** : une section « Corpus radio Hugging Face (lecture seule) » est
     ajoutée à la fin de `$RUNNER_TEMP/oc/prompt.md` pour signaler le chemin à
     opencode et rappeler de ne pas modifier le corpus.
   - **Échec non bloquant** : `continue-on-error: true` et gestion explicite du
     code retour ; un `### Corpus HF (optionnel)` dans `$GITHUB_STEP_SUMMARY`
     indique le succès, l'absence de `HF_TOKEN` ou l'échec du téléchargement.
4. **`HF_TOKEN`** : le secret existant est exposé à l'étape
   « Exécuter la tâche opencode » via `env` uniquement, avec
   `HF_TOKEN: ${{ inputs.target_repo == 'antenly' && secrets.HF_TOKEN || '' }}`.
   Il n'est jamais affiché (`set +x`, sorties de téléchargement redirigées),
   jamais écrit dans le prompt et jamais commité.

Rien d'autre ne change : entrées existantes, jeton de la cible, porte gitleaks,
refus de modifier `.github/workflows` sur `antenly`, push fast-forward et
notification restent identiques.

## Pourquoi c'est sûr

- Le corpus et `HF_TOKEN` ne sortent pas du runner : corpus dans `$RUNNER_TEMP`,
  secret seulement en variable d'environnement de l'étape opencode.
- Aucun fichier du corpus n'est sous `target/`, donc jamais inclus dans les
  commits vérifiés par gitleaks ni poussés.
- Le téléchargement est optionnel et non bloquant ; sans `HF_TOKEN` ou en cas
  d'échec réseau, la tâche opencode continue et le résumé CI le documente.
- `ffmpeg`/`ffprobe` sont installés selon le schéma déjà éprouvé de
  `opencode-fullrun.yml`.

## Vérifications effectuées

- `git apply --check docs/patches/opencode-task-hf-ffmpeg-2026-11-24.patch` :
  OK sur un arbre propre à l'état de `main`.
- Validation YAML du workflow patché avec `python3` + `PyYAML` : OK ; l'input
  `with_hf_corpus` (booléen, défaut `false`) et les nouvelles étapes sont
  présents ; `HF_TOKEN` figure dans l'`env` de l'étape opencode.
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
- Avec corpus : cocher `with_hf_corpus` et s'assurer que le secret `HF_TOKEN`
  existe dans le dépôt `LordThiouk/antenly-ci` et donne accès en lecture au
  dataset privé `LordThiouk/antenly-corpus`.
- Un prompt ciblant `antenly` peut s'appuyer sur `$ANTENLY_CORPUS_DIR` (sans le
  coder en dur) uniquement lorsque le téléchargement a réussi.
