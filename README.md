# antenly-ci

CI publique (minutes GitHub Actions gratuites) pour le dépôt privé `LordThiouk/antenly`.
Ce dépôt ne contient que des workflows : le code reste dans `antenly`, récupéré au run
avec le secret `ANTENLY_TOKEN` (jeton fine-grained limité à `antenly`).

- `ci.yml` : statut `antenly-ci` pending, puis rust, python, preannot-ina (vrai inaSpeechSegmenter + TensorFlow CPU), licences, secrets (gitleaks), puis success/failure sur le commit d'`antenly` testé.
- `pr-dispatch.yml` : cron toutes les 15 min (ou à la main), lance `ci.yml` pour chaque SHA de tête de PR ouverte d'`antenly` sans statut `antenly-ci`. GitHub suspend les crons d'un dépôt public après 60 jours sans activité : le réactiver dans l'onglet Actions.
- `inventory-probe.yml` : passe 1 (cron lundi 04:00 UTC, ou à la main).
- `inventory-pass2.yml` : passe 2 1 h plus tard (cron lundi 05:00 UTC), rapport, gates, PR `inventory/auto-update` sur `antenly`.

Les logs et artifacts de ce dépôt sont publics. Aucun push direct sur une branche de base d'`antenly` ; le merge reste manuel.

## Passe de langue (`language.yml`)

Détection de langue des segments `parole` du corpus `full-v1` (`facebook/mms-lid-256`
par défaut), pour l'artefact `data/annotation/language/full-v1.json` attendu par
`antenly` (ISC-6). La détection tourne ici, le code et le corpus restent dans
`antenly` et sur le dataset privé `LordThiouk/antenly-corpus`.

**Prérequis antenly.** Le SHA pointé par `ref` doit inclure les flags CLI
`--offset` et `--limit` dans `scripts/corpus/language_pass.py` (par ex. la branche
`fullrun/annotation-tool-f2` ou un descendant). Un commit plus ancien (ex. `d58da6d`
seul) ne les expose pas : le workflow échouera sur `detect`.

**Lancer.** Onglet Actions → `Language pass` → `Run workflow` :

- `ref` : branche ou commit d'`antenly` à analyser (défaut `main`).
- `model` : détecteur Hugging Face ; il doit lister `wol` (`mms-lid-256` le fait,
  `faster-whisper` non).
- `limit` : `0` = run complet découpé en tranches ; `>0` = smoke test (une tranche
  par station, artefact explicitement `partial: true`, jamais accepté tel quel par
  `merge` sur un run de production).
- `chunk_size` : nombre max de segments `parole` par job `detect` quand `limit=0`
  (défaut `250`, réglable sans modifier le YAML — Love FM ~289 segments / ~30 min
  sert de repère pour rester sous le plafond 350 min par job).
- `stations` : filtre CSV optionnel, séparé par des virgules (vide = toutes).

Le job `prepare` résout un SHA unique, calcule une matrice JSON de tranches
`{station, offset, limit}` couvrant tous les segments `parole` (sans trou ni
chevauchement), publie le sha256 de `segments.csv`, et **échoue** si le nombre de
jobs dépasserait 256 (plafond matrice GitHub) en demandant d'augmenter `chunk_size`.
Chaque job matrice `detect` appelle `language_pass.py` avec `--stations`,
`--offset`, `--limit`, télécharge **seulement** les fichiers audio de sa station via
`huggingface_hub.hf_hub_download(repo_type="dataset")`, puis publie un fragment
`<station>-o<offset>-language`. Le job `merge` télécharge toutes les tranches et
concatène via `--merge-dir` ; il **échoue** si une tranche manque, est marquée
`partial: true`, ou s'il reste un segment `parole` sans langue.

**Secret requis.** `HF_TOKEN` (lecture du dataset privé `LordThiouk/antenly-corpus`).
Si le secret est absent, le job `prepare` échoue explicitement avec
`HF_TOKEN absent de antenly-ci (acte Papa requis)` — jamais un faux vert.
`ANTENLY_TOKEN` reste nécessaire pour lire le dépôt privé `antenly`.

**Récupérer et committer l'artefact.** Télécharger l'artifact
`language-full-v1` du run, puis dans `antenly` :

```bash
mkdir -p data/annotation/language
cp full-v1.json data/annotation/language/full-v1.json
cd api && ANTENLY_REQUIRE_LANGUAGE=1 uv run pytest tests/annotation/test_language.py -q
```

La dernière commande est la face corpus d'ISC-6 : elle échoue si l'artefact est
absent, d'une autre entrée (`source_segments_sha256`) ou s'il laisse un segment
`parole` sans langue. Committer ensuite le fichier dans `antenly`. Ce dépôt
n'écrit jamais dans `antenly` : aucun push, aucun PAT d'écriture, `main` intact.

**Coût/temps.** Un run complet détecte les 5 066 segments `parole` des 6
stations (fenêtre plafonnée à 30 s par segment). Chaque job est plafonné à
350 min ; les grosses stations (ex. `sudfm`, ~1 142 segments) sont découpées en
plusieurs jobs selon `chunk_size`. Utiliser `limit` pour un smoke test avant un
run complet. Les dépendances sont épinglées dans
`scripts/corpus/language-requirements.txt` (torch CPU 2.5.1, installé à part
depuis `download.pytorch.org/whl/cpu` dans un venv Python 3.12 : cette roue
n'existe pas pour Python 3.14, défaut actuel de `ubuntu-latest`).
