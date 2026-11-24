# opencode-task : lecture seule de acr-senegal

Date : 2026-11-24
Branche : `feat/opencode-task-read-acr-2026-11-24`
Patch : `docs/patches/opencode-task-read-acr-2026-11-24.patch`

## Objectif

Permettre aux tâches opencode ciblant `antenly` de **lire** le dépôt privé
`LordThiouk/acr-senegal` (comparaison des moteurs d'empreinte), sans donner à la
tâche de droit d'écriture ni de push sur ce dépôt.

## Ce qui change

Le patch modifie uniquement `.github/workflows/opencode-task.yml` et ajoute,
pour `inputs.target_repo == 'antenly'` seulement :

1. **Checkout en lecture seule** de `LordThiouk/acr-senegal` avec
   `actions/checkout@v4`, `token: ${{ secrets.ANTENLY_TOKEN }}`,
   `persist-credentials: false`, `fetch-depth: 0`, dans `ro/acr-senegal`
   (relatif au workspace, donc **hors de `target/`**).
   L'étape est `continue-on-error: true`.
2. **Récupération de toutes les branches distantes** avec
   `git fetch --prune origin '+refs/heads/*:refs/remotes/origin/*'`.
   Le jeton est fourni par un `GIT_ASKPASS` temporaire (supprimé ensuite) :
   il n'est jamais écrit dans `.git/config` ni dans l'URL du remote.
3. **Lecture seule** : `chmod -R a-w` sur la copie après le fetch.
4. **Variable d'environnement** `ACR_SENEGAL_RO` exportée via `GITHUB_ENV`
   et rappelée dans le prompt opencode :
   - succès : chemin disponible + consigne de lecture seule ;
   - échec du checkout : le job continue et le résumé signale la copie
     indisponible, sans exposer `ACR_SENEGAL_RO`.
5. **Garde-fou** : le chemin de la copie est vérifié comme jamais situé sous
   `target/`.

Rien d'autre ne change : jeton de la cible, porte gitleaks, refus de modifier
`.github/workflows` sur `antenly`, push fast-forward et notification restent
identiques.

## Pourquoi c'est sûr

- La copie est un checkout séparé, frère de `target/`, donc la porte
  `git -C target ...` et `gitleaks --source target` ne la voient jamais.
- Aucun jeton n'est persisté : `persist-credentials: false` et askpass
  temporaire.
- La tâche opencode ne peut pas modifier la copie (`chmod -R a-w`).
- En cas d'échec du checkout secondaire, la tâche opencode continue sans la
  copie.

## Utilisation dans un prompt

Le workflow injecte automatiquement dans le prompt :

```
## Dépôt de référence en lecture seule
- Une copie de `LordThiouk/acr-senegal` (toutes les branches distantes) est disponible en lecture seule ici : `$ACR_SENEGAL_RO`.
- Sers-t'en pour comparer les moteurs d'empreinte ; ne tente jamais de la modifier (dossier en lecture seule, hors dépôt cible).
```

Un prompt ciblant `antenly` peut donc s'appuyer sur `$ACR_SENEGAL_RO` (sans le
coder en dur) pour lire les sources de `acr-senegal` et les comparer au dépôt
cible.

## Vérifications

- `git apply --check docs/patches/opencode-task-read-acr-2026-11-24.patch` :
  OK sur arbre propre.
- `actionlint` : OK sur les scripts ajoutés ; seule reste l'avertissement
  `SC2015` déjà présent avant le patch dans l'étape d'installation.
- `yamllint` : aucune erreur (uniquement des avertissements `line-length`
  préexistants).
- `bash -n` : OK sur tous les blocs `run` du workflow.
- `gitleaks` : aucune valeur de secret dans le patch ou ce rapport.

## Application

Depuis la racine du dépôt, sur `main` :

```sh
git apply docs/patches/opencode-task-read-acr-2026-11-24.patch
```
