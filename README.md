# antenly-ci

CI publique (minutes GitHub Actions gratuites) pour le dépôt privé `LordThiouk/antenly`.
Ce dépôt ne contient que la CI **produit** : le code reste dans `antenly`, récupéré au
run avec le secret `ANTENLY_TOKEN` (jeton fine-grained limité à `antenly`).

Ce dépôt ne porte que la CI produit ; les runs opencode / FullRun (machinerie,
scripts, prompts, agents et garde-fous) vivent dans `LordThiouk/lifeos-ci`. Voir
`CLEANUP.md` pour l'inventaire du nettoyage.

## Workflows produit

- `ci.yml` : statut `antenly-ci` pending, puis rust, python (ISC-1 à ISC-21 et ISC-27,
  `tests/security` + audit interne), security-stack (ISC-22 à ISC-24, RLS
  Postgres/ClickHouse/SeaweedFS sur la vraie pile de dev `docker compose`, 0 skip sous
  `ANTENLY_DEV_STACK=1`), preannot-ina (vrai inaSpeechSegmenter + TensorFlow CPU),
  licences, secrets (gitleaks), puis success/failure sur le commit d'`antenly` testé.
- `pr-dispatch.yml` : cron toutes les 15 min (ou à la main), lance `ci.yml` pour chaque
  SHA de tête de PR ouverte d'`antenly` sans statut `antenly-ci`. GitHub suspend les
  crons d'un dépôt public après 60 jours sans activité : le réactiver dans l'onglet Actions.
- `inventory-probe.yml` : passe 1 de la sonde d'inventaire produit (cron lundi 04:00 UTC,
  ou à la main).
- `inventory-pass2.yml` : passe 2 1 h plus tard (cron lundi 05:00 UTC), rapport, gates,
  PR `inventory/auto-update` sur `antenly`.
- `language.yml` : passe de langue produit sur le corpus `full-v1` d'`antenly`.

Les logs et artifacts de ce dépôt sont publics. Aucun push direct sur une branche de
base d'`antenly` ; le merge reste manuel.

## Passe de langue (`language.yml`)

Détection de langue des segments `parole` du corpus `full-v1` (`facebook/mms-lid-256`
par défaut), pour l'artefact `data/annotation/language/full-v1.json` attendu par
`antenly` (ISC-6). La détection tourne ici, le code et le corpus restent dans `antenly`
et sur le dataset privé `LordThiouk/antenly-corpus`.

**Prérequis antenly.** Le SHA pointé par `ref` doit inclure les flags CLI `--offset` et
`--limit` dans `scripts/corpus/language_pass.py`.

**Lancer.** Onglet Actions → `Language pass` → `Run workflow` :

- `ref` : branche ou commit d'`antenly` à analyser (défaut `main`).
- `model` : détecteur Hugging Face ; il doit lister `wol` (`mms-lid-256` le fait).
- `limit` : `0` = run complet découpé en tranches ; `>0` = smoke test.
- `chunk_size` : nombre max de segments `parole` par job `detect` quand `limit=0`.
- `stations` : filtre CSV optionnel, séparé par des virgules (vide = toutes).

Le job `prepare` résout un SHA unique, calcule une matrice de tranches
`{station, offset, limit}` sans trou ni chevauchement, publie le sha256 de
`segments.csv`, et échoue au-delà du plafond de 256 jobs matrice. Chaque job `detect`
télécharge uniquement les fichiers audio de sa station, puis publie un fragment. Le job
`merge` échoue si une tranche manque, est `partial: true`, ou laisse un segment `parole`
sans langue.

**Secret requis.** `HF_TOKEN` (lecture du dataset privé `LordThiouk/antenly-corpus`).
S'il est absent, `prepare` échoue explicitement — jamais un faux vert. `ANTENLY_TOKEN`
reste nécessaire pour lire `antenly`.

**Récupérer et committer l'artefact.** Télécharger l'artifact `language-full-v1` du run,
puis dans `antenly` :

```bash
mkdir -p data/annotation/language
cp full-v1.json data/annotation/language/full-v1.json
cd api && ANTENLY_REQUIRE_LANGUAGE=1 uv run pytest tests/annotation/test_language.py -q
```

La dernière commande échoue si l'artefact est absent, d'une autre entrée
(`source_segments_sha256`) ou s'il laisse un segment `parole` sans langue. Committer
ensuite le fichier dans `antenly`. Ce dépôt n'écrit jamais dans `antenly` : aucun push,
aucun PAT d'écriture, `main` intact.
