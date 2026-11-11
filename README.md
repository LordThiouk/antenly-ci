# antenly-ci

CI publique (minutes GitHub Actions gratuites) pour le dépôt privé `LordThiouk/antenly`.
Ce dépôt ne contient que des workflows : le code reste dans `antenly`, récupéré au run
avec le secret `ANTENLY_TOKEN` (jeton fine-grained limité à `antenly`).

- `ci.yml` : statut `antenly-ci` pending, puis rust, python, preannot-ina (vrai inaSpeechSegmenter + TensorFlow CPU), licences, secrets (gitleaks), puis success/failure sur le commit d'`antenly` testé.
- `pr-dispatch.yml` : cron toutes les 15 min (ou à la main), lance `ci.yml` pour chaque SHA de tête de PR ouverte d'`antenly` sans statut `antenly-ci`. GitHub suspend les crons d'un dépôt public après 60 jours sans activité : le réactiver dans l'onglet Actions.
- `inventory-probe.yml` : passe 1 (cron lundi 04:00 UTC, ou à la main).
- `inventory-pass2.yml` : passe 2 1 h plus tard (cron lundi 05:00 UTC), rapport, gates, PR `inventory/auto-update` sur `antenly`.
- `opencode-fullrun.yml` : longs jobs opencode (FullRun LifeOS) sur une branche de fonctionnalité d'`antenly`, à la main uniquement (voir plus bas).

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

## FullRun opencode (`opencode-fullrun.yml`)

Fait tourner un long job opencode (FullRun LifeOS) pour `antenly` sur un runner GitHub
standard, à la place de la box (qui se met en pause). Dépôt public : les minutes des
runners standards sont **gratuites** et ne touchent pas au quota mensuel. Limite : 6 h par
job (le workflow s'arrête à 350 min, opencode à 310 min pour laisser le temps de pousser).

**Ce qui est versionné ici (public).** Le workflow, `opencode/config/opencode.json`
(config de la box assainie : sans provider FreeLLM ni VPS, sans MCP `github`/`rea`/
`playwright`, chemins en `{env:HOME}`, modèle `{env:OC_MODEL_MAIN}`, `git push`/`gh`
interdits à l'IA), `opencode/ci-preamble.md` (contexte CI ajouté avant le prompt) et
`opencode/run-fullrun.sh`. Les agents (Nix, Vera, Serena, Forge, Max…), commandes, plugin
LifeOS et prompt Nix restent **privés** dans `LordThiouk/lifeos`, dossier `opencode/`
(entrée `lifeos_ref`, défaut `main` : merger `lifeos` PR #3 avant le premier run, ou passer
`lifeos_ref=ci/opencode-config-2026-11-11` en attendant).

**Secrets à créer (Settings → Secrets → Actions)** — noms seulement, jamais dans un fichier :

| Secret | Contenu | Portée |
|---|---|---|
| `ANTENLY_TOKEN` | déjà présent : lecture d'`antenly` | Contents: read |
| `ANTENLY_PUSH_TOKEN` | jeton fine-grained, **seulement** `LordThiouk/antenly` | Contents: read & write (pas Workflows, pas Administration) |
| `LIFEOS_READ_TOKEN` | jeton fine-grained, **seulement** `LordThiouk/lifeos` | Contents: read |
| `ISA_STAMP_KEY` | contenu de `~/.claude/LIFEOS/MEMORY/STATE/.isa-stamp-key` de la box (64 hex) | — |

Aucune clé de modèle : les modèles `opencode/*-free` n'en demandent pas. Le workflow
refuse tout modèle qui n'est pas `opencode/…-free`.

**Protection de `main`.** Un jeton fine-grained ne peut pas être limité à une branche, et
la protection de branche / les rulesets ne sont pas disponibles sur un dépôt privé en plan
gratuit. Garde-fous en place : l'IA ne reçoit **aucun** jeton d'écriture (checkout sans
identifiants, hook `pre-push` bloquant, `git push` refusé dans la config) ; seul le dernier
step pousse, vers `refs/heads/<branche>` exacte, sans `--force`, après avoir vérifié que la
branche n'est ni `main` ni `master`, que l'historique part bien du SHA de départ, que
`.github/workflows/` n'est pas touché et que gitleaks ne trouve rien dans les commits du
run. Si un jour `antenly` passe en Pro/public : ajouter une règle « interdire les push
directs sur `main` ».

**Lancer.** Pré-requis : la branche de fonctionnalité existe déjà sur `antenly` et contient
l'ISA. Onglet Actions → `opencode FullRun` → `Run workflow` (seul `LordThiouk` peut lancer) :

- `branch` : branche d'`antenly` (ex. `fullrun/annotation-tool-f2`), jamais `main`/`master` ;
- `prompt_path` : `antenly:<chemin>` ou `ci:<chemin>` (ex. `ci:opencode/prompts/F3.md`) ;
- `job_name` : nom court, donne `.fullrun/<job>_DONE.md` ;
- `model_main` (défaut `opencode/deepseek-v4.1-flash-free`, aussi Forge), `model_max`
  (défaut `opencode/mimo-v2.6-flash-free`), `model_fallback` (défaut
  `opencode/glm-5.3-flash-free`, utilisé seulement si la passe principale échoue sur un 429).

Ou en CLI : `gh workflow run opencode-fullrun.yml -R LordThiouk/antenly-ci -f branch=… -f prompt_path=… -f job_name=…`.

**Résultat.** Les commits d'opencode et le rapport `.fullrun/<job>_DONE.md` sont poussés sur
la branche (si une PR est ouverte dessus, `pr-dispatch.yml` lance ensuite la CI habituelle sur le nouveau SHA). Le log du
run ne montre que des lignes de statut génériques.

**Reprise.** Relancer avec la même branche, le même prompt et le même `job_name` : le
préambule demande à l'agent de lire `.fullrun/<job>_DONE.md` et l'état de l'ISA, puis de
reprendre à la première étape non terminée. La session opencode elle-même n'est pas
conservée entre deux runs. Un run par branche à la fois (`concurrency`).

**Risques connus.**
- Tout ce qui s'affiche dans le log est public : ne jamais ajouter `cat`/`tee` du log
  opencode ni `actions/upload-artifact` à ce workflow.
- Le prompt FullRun est lu depuis `antenly` (privé) ou ce dépôt (public) : un prompt mis
  ici est public.
- `ANTENLY_PUSH_TOKEN` peut techniquement écrire sur toute branche d'`antenly` ; il n'est
  exposé qu'au step de push, jamais à opencode.
- Hooks LifeOS : le service local `localhost:31337`, `rtk` et `cc-diff` n'existent pas sur
  le runner ; le plugin replie les hooks http sur leur équivalent local, les autres
  devraient échouer sans bloquer (à vérifier au premier run) (journalisés dans `~/.local/state/opencode-lifeos`).
- Pas de FreeLLM, de VPS, d'ACRCloud, de Playwright ni de MCP GitHub sur le runner.
