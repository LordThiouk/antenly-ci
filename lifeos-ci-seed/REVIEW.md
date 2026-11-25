# Revue du socle lifeos-ci

Branche revue : `seed/lifeos-ci-2026-11-24` (dossier `lifeos-ci-seed/`).
Périmètre : scripts `opencode/*.sh`, `targets/*.sh`, `opencode/tests/*` et
workflows `.github/workflows/*.yml` du dossier `lifeos-ci-seed/`.
Revue statique, sans modification du code. Références de comparaison :
`antenly-ci` `main` et `galass-ci` (`git clone --depth 1`).

Contrôles exécutés pendant la revue :

- `bash lifeos-ci-seed/opencode/tests/run-all.sh` : 5 suites, 0 échec.
- `shellcheck -x lifeos-ci-seed/opencode/*.sh lifeos-ci-seed/targets/*.sh lifeos-ci-seed/opencode/tests/*.sh` : code 0.
- `actionlint` non relancé (binaire absent du runner) ; le `REPORT.md` le revendique.

Ces tests sont utiles mais ne détectent aucun des défauts de sécurité ci-dessous :
`lifeos-chain-test.sh` est un test statique (`grep`) qui n'exécute ni la chaîne
ni le dispatch.

## 1. Provenance

### Scripts

| Fichier de `lifeos-ci-seed/` | Source | Décision / diff résumé |
| --- | --- | --- |
| `opencode/lifeos-guard.sh` | — (nouveau) | Réécrit intégralement. Aucun garde-fou `lifeos_write` équivalent dans `antenly-ci` ou `galass-ci` ; les gardes existantes sont dans les workflows. |
| `opencode/notify.sh` | `antenly-ci/.github/workflows/opencode-task.yml` (step « Notification de fin », l. 540-566) et `antenly-ci/.github/workflows/opencode-fullrun.yml` (l. 2059-2160) | Réécrit en script autonome. Ajout utile du code HTTP, mais régression : clé passée en argument de `curl` et script lancé depuis le checkout `ci/` modifiable (voir §2). |
| `opencode/quota.sh` | `antenly-ci/.github/workflows/opencode-task.yml` (inputs `model_main` / `model_chain`, l. 37-48) et `antenly-ci/opencode/run-fullrun.sh` (détection 429, l. 682-687) | Réécrit et étendu (journal interne + sortie, codes 10/20, `models.txt`). La détection est plus large que l’existant et introduit des faux positifs (voir §2). |
| `opencode/tests/allowed-repos-test.sh` | `galass-ci/opencode/tests/allowed-repos-test.sh` | Adapté : liste LordThiouk, tests `validate`, injections, doublons, alignement des options. A perdu le test galass qui vérifiait l’absence de copie en dur dans les scripts. |
| `opencode/tests/lifeos-chain-test.sh` | — (nouveau) | Test statique de la chaîne et de l’écriture LifeOS. Ne teste pas le dispatch réel ni le typage de `lifeos_write`. |
| `opencode/tests/lifeos-guard-test.sh` | — (nouveau) | Tests du garde-fou. Ne couvre pas les URL avec identifiants, `www.github.com`, `.git/` final, query/fragment (voir §2). |
| `opencode/tests/notify-test.sh` | — (nouveau) | Test du code HTTP et de la non-divulgation de la clé dans la sortie. |
| `opencode/tests/quota-test.sh` | — (nouveau) | Tests quota. Ne couvre pas les lignes de contexte d’un diff ni le code indenté hors bloc clôturé (voir §2). |
| `opencode/tests/run-all.sh` | — (nouveau) | Lance les `*-test.sh`. `galass-ci` itère directement dans `ci.yml` ; ce script est une factorisation propre. |
| `targets/allowed-repos.sh` | `galass-ci/opencode/allowed-repos.sh` (l. 10-27), liste reprise des options `target_repo` de `antenly-ci/.github/workflows/opencode-task.yml` | **Réécrit et déplacé**. Le changement de liste est justifié, mais le fichier existant faisait déjà le travail : le cœur `allowed_repos_list` / `allowed_repo` est identique, et le passage de `opencode/` à `targets/` n’est pas nécessaire. L’ajout de `validate` est utile. |

### Workflows

| Fichier de `lifeos-ci-seed/` | Source | Décision / diff résumé |
| --- | --- | --- |
| `.github/workflows/_agent-run.yml` | `antenly-ci/.github/workflows/opencode-task.yml` (validation, checkout, installation, quota, gitleaks, push, notification), `galass-ci/opencode/extra-repos.sh` (checkout/push/PR des extras), `galass-ci/.github/workflows/opencode-fullrun.yml` (modèles, quotas, outils figés) | **Réécrit/factorisé** en workflow réutilisable. Le regroupement est légitime, mais plusieurs protections existantes ne sont pas reprises (voir §2) : outils non figés, hooks non neutralisés, `--redact`, contrôle `.github/workflows`, merge-base, branche. |
| `.github/workflows/_next.yml` | `galass-ci/.github/workflows/opencode-fullrun.yml` (chaînage `chain_enabled` / `chain_state`, l. 129-207 et dispatch l. 2140-2160) | **Réécrit** en table d’agents simplifiée. Le chaînage nominal est correct, mais le dispatch passe `lifeos_write` en `-f` (chaîne) et ne transmet pas `--ref` (voir §2). |
| `.github/workflows/ci.yml` | `galass-ci/.github/workflows/ci.yml` + `antenly-ci/.github/workflows/ci-scripts.yml` | Adapté : tests + `shellcheck` + `actionlint`. `ci-scripts` exécutait déjà les tests ; la factorisation est correcte. `actionlint` n’est pas vérifié par SHA et les tests ne sont pas passés à `shellcheck`. |
| `.github/workflows/fr-plan-vera.yml` | `galass-ci/.github/workflows/opencode-fullrun.yml` (premier lien FullRun) et `galass-ci/.github/workflows/opencode-task.yml` (inputs) | Réécrit : wrapper `workflow_dispatch` vers `_agent-run.yml` puis `_next.yml`. Seul le premier agent (`vera`) existe ; les autres `fr-*.yml` annoncés par `_next.yml` sont absents. |
| `.github/workflows/task.yml` | `galass-ci/.github/workflows/opencode-task.yml` + `antenly-ci/.github/workflows/opencode-task.yml` | Adapté en wrapper sans enchaînement. `lifeos_write` a bien `default: false`. |

### Réutilisations existantes non exploitées

- **`extra-repos.sh`** : `galass-ci/opencode/extra-repos.sh` existait déjà pour
  le checkout, les contrôles, le push et la PR des dépôts supplémentaires. Le
  socle le réimplémente dans `_agent-run.yml` en perdant des protections
  essentielles : git isolé sans hooks (`extra-repos.sh:82-98`), hook `pre-push`
  de blocage (`extra-repos.sh:188-189`), contrôle d’ancêtre et de branche
  (`extra-repos.sh:202-249`), configuration/ignore gitleaks et clé ISA
  (`extra-repos.sh:250-286`), push depuis une copie nue (`extra-repos.sh:293-346`).
  C’est un défaut bloquant (§2.1, §2.2, §2.8).
- **Porte gitleaks** : `antenly-ci/.github/workflows/opencode-task.yml:490-538`
  et `galass-ci/.github/workflows/opencode-task.yml:299-339` font déjà le
  contrôle avec `--redact`, contrôle de branche, merge-base, `.github/workflows`
  et git sans hooks. `_agent-run.yml:437` et `:474` le réécrivent en plus faible.
- **Notification** : `antenly-ci/.github/workflows/opencode-task.yml:540-566`
  et `galass-ci/.github/workflows/opencode-fullrun.yml:2145-2166` la faisaient
  déjà. Le nouveau `opencode/notify.sh` est acceptable comme factorisation, mais
  il est exécuté depuis un dossier modifiable et passe la clé en argument, alors
  que le FullRun existant la passe à `curl` par stdin (`-K -`).
- **`redact-log.sh` / `livelog.sh` / `leaklog.sh` / `wippush.sh`** :
  `antenly-ci/opencode/` contient déjà ces scripts. Le socle ne les reprend pas :
  il écrit la sortie brute d’opencode dans `$RUNNER_TEMP/oc/run-*.log` sans
  masquage (`_agent-run.yml:352-357`). Aucune publication de ce journal n’est
  faite aujourd’hui, donc ce n’est pas une fuite immédiate ; toute publication
  ou tout artefact ajouté plus tard exposera des secrets. Réutiliser
  `opencode/redact-log.sh` avant toute conservation/publication.
- **`allowed-repos.sh`** : `galass-ci/opencode/allowed-repos.sh` faisait déjà
  le travail. Le changement de liste justifie une adaptation, pas une réécriture
  complète ni un changement de chemin. Garder une seule source et éviter la
  duplication avec les options `choice` des workflows.

## 2. Défauts bloquants

### 2.1. Critique — Outils du `ci/` modifiables et exécutés après opencode

`_agent-run.yml:110-115` checkout `ci` en écriture ; `_agent-run.yml:303-325`
autorise opencode à éditer `*` et à accéder aux répertoires externes ; puis
`_agent-run.yml:361` exécute `ci/opencode/quota.sh` après opencode, et
`_agent-run.yml:436` / `:473` exécutent `ci/opencode/lifeos-guard.sh`, tandis
que `_agent-run.yml:515-517` exécute `ci/opencode/notify.sh` avec
`OC_NOTIFY_KEY` (`:504-505`) et que l’étape push a `CI_TOKEN` (`:414`).

Une injection de prompt peut donc réécrire le garde-fou, le quota ou la
notification avant leur exécution. Le garde-fou devient un no-op, et
`notify.sh` peut exfiltrer `OC_NOTIFY_KEY` ; un script exécuté dans l’étape push
peut exfiltrer `CI_TOKEN`. C’est le contournement direct du garde-fou et une
fuite de secrets.

Correction suggérée : figer tous les outils avant opencode dans un répertoire
root-owned (modèle `galass-ci/.github/workflows/opencode-fullrun.yml:778-783`),
les invoquer par chemin absolu, et ne jamais exécuter un script du checkout
`ci/` après le début d’opencode. À défaut, rendre `ci/` non inscriptible et
vérifier son intégrité (SHA) avant chaque exécution.

### 2.2. Critique — Hooks et filtres git des dépôts de l’agent exécutés avec `CI_TOKEN`

`_agent-run.yml:426-440` pousse avec un `git -C "$dir" push` sans
`--no-verify`, sans `-c core.hooksPath=/dev/null` et sans
`core.fsmonitor=false` ; l’étape a `CI_TOKEN` dans son environnement
(`_agent-run.yml:414`). Or `target/` et `extra/*` sont écrivables par opencode,
qui peut y installer `.git/hooks/pre-push`, modifier `.git/config` (hooks,
filtres, fsmonitor) ou `.gitattributes`.

De même, `_agent-run.yml:463-466` fait `git add -A` puis `git commit` dans
`lifeos` et `:475-477` pousse, sans isolation. Un hook `pre-push`, `pre-commit`
ou un filtre `clean` s’exécute alors avec `CI_TOKEN` et peut le lire ou
l’exfiltrer pendant l’étape censée sécuriser le push.

Correction suggérée : reprendre le modèle galass : copie nue pour pousser,
`env -i`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`,
`-c core.hooksPath=/dev/null`, `-c core.fsmonitor=false`, `--no-verify`
(`galass-ci/opencode/extra-repos.sh:82-98` et `:293-346`,
`galass-ci/.github/workflows/opencode-task.yml:310-339`). Ne jamais laisser
opencode écrire dans `.git/hooks`, `.git/config` ou `.gitattributes`.

### 2.3. Critique — État mutable (`GITHUB_ENV`, `GITHUB_OUTPUT`, `$RUNNER_TEMP`) confié à opencode

`_agent-run.yml:97-108` place `IN_BRANCH`, `LIFEOS_WRITE`, `TARGET_REPO` et
`EXTRA_REPOS_NORM` dans l’environnement du job. `_agent-run.yml:426-456` et
`:460-494` les réutilisent après opencode sans revalidation. Or opencode hérite
de `GITHUB_ENV`, `GITHUB_OUTPUT`, `GITHUB_PATH` et `RUNNER_TEMP` : il peut
ajouter `IN_BRANCH=main`, `LIFEOS_WRITE=true`, modifier
`agent-repos.txt` / `lifeos-base.txt` ou préfixer le `PATH`.

Combiné à 2.1 (garde-fou réécrit), cela permet un push vers `main`, un push
vers `lifeos` alors que `lifeos_write=false`, ou un statut `ok` falsifié qui
déclenche `_next.yml` malgré un quota. Le push n’est pas protégé par le fait
que la validation initiale a eu lieu : cette validation est antérieure à
opencode.

Correction suggérée : séparer l’exécution d’opencode du push/notify dans deux
jobs distincts ; le job de push relit uniquement les `inputs` immuables et des
fichiers root-owned, revalide `main`/`master`, `lifeos_write` et la liste
blanche, et ne lit jamais un fichier de `$RUNNER_TEMP` écrit par l’agent. Ne pas
utiliser `GITHUB_ENV` après opencode.

### 2.4. Élevée — Aucun refus des modifications de `.github/workflows` avant push

`_agent-run.yml:426-441` pousse `target/` et `extra/*` sans vérifier les
fichiers modifiés ; `_agent-run.yml:460-478` fait de même pour `lifeos`. Un
dépôt cible public peut donc recevoir un workflow piégé qui, au prochain run,
exécutera du code avec les secrets du dépôt. L’existant le refuse déjà :
`galass-ci/opencode/extra-repos.sh:245-249`,
`galass-ci/.github/workflows/opencode-task.yml:326-328`,
`antenly-ci/.github/workflows/opencode-task.yml:510-512`.

Correction suggérée : avant chaque push, refuser
`git diff --name-only "$base" "$h" -- .github/workflows` non vide. N’autoriser
cette exception que pour un dépôt explicitement prévu (`lifeos-ci` si c’est le
but), avec un contrôle séparé et documenté.

### 2.5. Élevée — Contournement du garde-fou par normalisation d’URL

`opencode/lifeos-guard.sh:19-32` ne retire que des préfixes exacts. Les formes
suivantes ne sont pas reconnues comme lifeos :
`https://x-access-token@github.com/LordThiouk/lifeos.git`,
`https://www.github.com/LordThiouk/lifeos`,
`https://github.com/LordThiouk/lifeos.git/`,
`https://github.com/LordThiouk/lifeos.git?x=1`.
Or l’interface documentée (`:3-5`) et les tests acceptent des URL
(`opencode/tests/lifeos-guard-test.sh:29-41`). Avec `lifeos_write=false`,
`destination` accepte alors une destination lifeos (lignes `:101-118`).

Correction suggérée : parser l’URL (hôte + chemin), supprimer identifiants,
port, query, fragment et slash final avant de comparer `owner/repo` ; refuser
explicitement toute URL contenant un `@` non reconnu. Ajouter les cas au test.

### 2.6. Élevée — Lecture seule de lifeos non réellement garantie quand `lifeos_write=false`

`_agent-run.yml:210-212` fait `chmod -R a-w lifeos` puis appelle
`opencode/lifeos-guard.sh readonly` (`:121-130`), qui ne vérifie que les bits
d’écriture à l’instant T. opencode est propriétaire des fichiers et peut faire
`chmod -R u+w lifeos` (le bit d’écriture n’est pas requis pour `chmod` quand on
est propriétaire). Il peut aussi modifier le dépôt par un autre moyen si les
outils/scripts sont modifiables (2.1).

Correction suggérée : ne pas considérer `chmod` comme une barrière de sécurité.
Faire la copie lifeos en lecture seule avec un propriétaire distinct (root ou
utilisateur dédié), la rendre immuable, ou exécuter opencode dans un bac à
sable sans accès à `lifeos/`. Revalider l’intégrité juste avant toute décision
de push ; ne jamais pousser lifeos quand `lifeos_write=false`.

### 2.7. Élevée — `lifeos` en `extra_repos` / `target_repo` contourne la branche dédiée

`targets/allowed-repos.sh:11` autorise `lifeos` dans la liste blanche.
Avec `lifeos_write=true` :

- `target_repo=lifeos` : `_agent-run.yml:154-162` clone lifeos dans `target/`, et
  `_agent-run.yml:426-441` le pousse vers `$IN_BRANCH` (branche arbitraire),
  pas vers `lifeos-ci/<job_name>` ni via la PR brouillon dédiée.
- `extra_repos=lifeos` : `_agent-run.yml:164-189` clone `extra/lifeos`, et
  `_agent-run.yml:426-441` le pousse aussi vers `$IN_BRANCH`. Le flux dédié
  `_agent-run.yml:460-494` ne concerne que le clone `lifeos/`, pas `extra/lifeos`.

Le garde-fou `writes` autorise lifeos avec `write=true`
(`opencode/lifeos-guard.sh:82-96`), donc il ne bloque pas ce cas. De plus
`targets/allowed-repos.sh:44-58` ne refuse pas `target_repo` répété dans
`extra_repos`.

Correction suggérée : retirer `lifeos` des `target_repo` et des `extra_repos`
(ou les refuser explicitement), et réserver lifeos au clone `lifeos/` et à la
branche `lifeos-ci/<job_name>`. Ajouter un test.

### 2.8. Élevée — Porte gitleaks incomplète

`_agent-run.yml:437` et `:474` appellent `gitleaks detect` sans `--redact`,
sans configuration/ignore du dépôt au SHA de base, sans copie nue, sans contrôle
de branche/merge-base et sans isolation git. Les versions existantes font mieux :
`antenly-ci/.github/workflows/opencode-task.yml:490-538`,
`galass-ci/opencode/extra-repos.sh:250-286`.

Aujourd’hui `gitleaks detect` n’affiche pas le secret par défaut (vérifié avec
une fausse clé), mais l’absence de `--redact` et de configuration figée rend la
porte dépendante du binaire et du dépôt. Le contrôle peut aussi être contourné
par un `.gitleaks.toml`/`.gitleaksignore` placé par l’agent si le mode de
chargement change, ou par le `PATH` modifiable (2.1).

Correction suggérée : réutiliser la porte existante, avec `--redact`, une
configuration et un ignore lus au SHA de base, un scan en dépôt nu, un binaire
root-owned en chemin absolu, et un échec fermé (aucun push si le scan échoue
ou est interrompu).

### 2.9. Élevée — `_next.yml` transmet un booléen avec `-f` (valeur non typée) et sans `--ref`

`_next.yml:130` fait `-f lifeos_write="$LIFEOS_WRITE"` alors que l’input déclaré
dans `fr-plan-vera.yml:28-32` et `task.yml:28-32` est `type: boolean`.
`gh workflow run` distingue `-f` (chaîne brute) et `-F` (valeur typée) : envoyer
`"false"`/`"true"` comme chaîne peut être rejeté ou donner le défaut `false` au
maillon suivant. Le test `opencode/tests/lifeos-chain-test.sh:47-52` ne vérifie
que la présence textuelle de la ligne, pas le dispatch réel.

De plus, `_next.yml:127-136` ne passe pas `--ref` : le prochain workflow est
dispatché sur la branche par défaut, pas sur la branche de la chaîne courante.

Correction suggérée : utiliser `-F lifeos_write="$LIFEOS_WRITE"`, ajouter
`--ref "${GITHUB_REF_NAME}"`, et tester le dispatch avec un `gh` factice qui
vérifie le type et la valeur.

### 2.10. Élevée — Chaînage non conditionné au succès réel du job précédent

`fr-plan-vera.yml:80-82` ne teste que
`needs.vera.outputs.status == 'ok'`, pas `needs.vera.result == 'success'`.
Le statut est une sortie d’étape (`_agent-run.yml:406-407`) et peut être
falsifié par l’agent (2.3) ou rester `ok` alors que le push/gitleaks a échoué
(le job `vera` échoue après avoir écrit `status=ok`). `_next.yml:93-100` ne
voit que ce statut. Il faut aussi noter que `_next.yml` ne vérifie pas que le
push a réellement eu lieu.

Correction suggérée : ajouter `needs.vera.result == 'success'` et, dans
`_next.yml`, vérifier un statut de push/PR fiable et non modifiable par
l’agent. Le statut `quota` doit rester un arrêt de chaîne (comportement actuel
correct sur le chemin nominal).

### 2.11. Moyenne — Faux positifs quota sur diffs, code indenté et prose

`opencode/quota.sh:81-99` ignore uniquement les lignes commençant par `+`, `-`
ou `@@`, et bascule sur les blocs ```/~~~. Une ligne de contexte de diff
commence par un espace (` 429 Too Many Requests`, ` error: quota exceeded`) et
n’est pas ignorée ; du code indenté sans fence, ou une phrase du modèle
contenant « erreur » + « quota », déclenche aussi la bascule. Le test
`opencode/tests/quota-test.sh:63-81` ne couvre que les lignes `+`/`-` et un bloc
fencé.

Correction suggérée : ignorer toutes les lignes de diff (espaces de contexte,
`diff --git`, `index`, en-têtes), tout code indenté, et n’accepter que des
motifs fournisseur stricts (ligne de log horodatée, `ERROR`, `AI_APICallError`,
`FreeUsageLimitError`, `429` en fin de statut HTTP) dans le journal interne et
la sortie bornée. Ajouter les cas de test.

### 2.12. Moyenne — Condition `github.actor` incomplète

`_agent-run.yml:85` et `_next.yml:70` ne vérifient que `github.actor`.
L’existant vérifie aussi `github.triggering_actor` :
`galass-ci/.github/workflows/opencode-task.yml:161`,
`galass-ci/.github/workflows/opencode-fullrun.yml:161`. Un acteur différent
(un collaborateur qui relance) peut ainsi relancer un run attribué à
`LordThiouk`.

Correction suggérée : ajouter
`&& github.triggering_actor == 'LordThiouk'` aux deux conditions et couvrir le
cas de re-run.

### 2.13. Moyenne — Notification : clé en argument de `curl` et script modifiable

`opencode/notify.sh:44-48` passe `OC_NOTIFY_KEY` dans `-H "Authorization:
Bearer $key"` et `-H "X-Automation-Key: $key"`. La clé est visible dans la
ligne de commande (`ps`) et l’absence de `set +x` (`:6`) aggrave le risque si
le shell passe en mode trace. Le script est en plus exécuté depuis `ci/`
modifiable (`_agent-run.yml:515-517`) avec la clé en environnement.

Correction suggérée : passer l’URL et la clé à `curl` via stdin (`-K -`) comme
`galass-ci/.github/workflows/opencode-fullrun.yml:2145-2166`, ajouter `set +x`,
et exécuter une copie root-owned ou le code inline de l’étape.

### 2.14. Moyenne — Permission `actions: write` inutilement large dans `_next.yml`

`_next.yml:73-75` demande `actions: write` alors que le dispatch utilise
`GH_TOKEN: CI_TOKEN` (`:79`), pas `GITHUB_TOKEN`. La permission est donc large
sans être nécessaire, et le caller `fr-plan-vera.yml:61-62` ne la déclare pas.
Le PAT `CI_TOKEN` doit lui-même être limité au strict nécessaire (scope
`actions:write` sur le seul dépôt lifeos-ci) ; ce point est hors dépôt mais
doit être vérifié.

Correction suggérée : retirer `actions: write` si `CI_TOKEN` est utilisé, ou
utiliser `GITHUB_TOKEN` avec cette permission si le dispatch doit rester sur le
jeton du workflow.

## 3. Défauts non bloquants / recommandations

1. `_agent-run.yml:426-441` ne vérifie pas que `git -C "$dir" rev-parse
   --abbrev-ref HEAD` vaut `$IN_BRANCH`, ni que `base` est un ancêtre de `HEAD`
   (`git merge-base --is-ancestor`). Le push non forcé rejette déjà une
   réécriture, mais un changement de branche peut pousser des commits
   inattendus. Reprendre `galass-ci/.github/workflows/opencode-task.yml:310-323`.
2. `_agent-run.yml:352-357` conserve la sortie brute d’opencode sans
   `redact-log.sh`. Aucune publication n’a lieu aujourd’hui, mais toute
   conservation/artefact ultérieur doit être masqué (voir `antenly-ci/opencode/redact-log.sh`).
3. `_agent-run.yml:384-404` accepte la simple existence de `/tmp/task_done.md`
   comme preuve de succès ; sur un runner auto-hébergé, un fichier périmé peut
   donner `ok` sans travail. Le supprimer au début du run ou le borner aux
   nouveaux fichiers.
4. `targets/allowed-repos.sh:44-58` ne refuse pas `target_repo` dans
   `extra_repos` : le même dépôt peut être cloné/poussé deux fois. Ajouter le
   contrôle (en plus de lifeos, §2.7).
5. `.github/workflows/ci.yml:38-53` télécharge `actionlint` sans SHA256 et ne
   passe pas `opencode/tests/*.sh` à `shellcheck`. Le `REPORT.md` affirme que
   les tests sont shellcheckés ; ce n’est pas le cas dans `ci.yml`.
6. `.github/workflows/fr-plan-vera.yml` est le seul `fr-*.yml` ; les fichiers
   `fr-plan-serena.yml`, `fr-build-*.yml`, etc. annoncés par `_next.yml` sont
   absents, donc la chaîne s’arrête après Vera avec « workflow suivant absent ».
   À documenter comme socle partiel.

## 4. Points vérifiés sans défaut

- `lifeos_write` a bien `default: false` dans `task.yml:28-32` et
  `fr-plan-vera.yml:28-32`, et `lifeos_write` est transmis par
  `fr-plan-vera.yml` à `_agent-run.yml` et `_next.yml` ; la valeur est bien
  présente dans `_next.yml:130` (le problème est le typage `-f`, pas l’oubli).
- Une seule bascule est codée dans `_agent-run.yml:349-379` (`switched`), et
  `quota.sh` ne fait pas de bascule supplémentaire. Le chemin nominal est
  correct.
- `quota.sh:44-47` et `:34-56` n’acceptent que `opencode/*-free` ; `models.txt`
  ne contient que des modèles `-free`.
- Le chaînage nominal ne part pas sur `quota` : `_next.yml:93-100` sort sur tout
  statut différent de `ok`. Le risque vient de la falsification du statut
  (§2.3/2.10), pas de cette condition.
- La concurrence est bien d’un run par dépôt cible :
  `_agent-run.yml:90-92`, groupe `agent-${{ inputs.target_repo }}`,
  `cancel-in-progress: false`.
- Aucun jeton n’est placé dans une URL de remote : le checkout cible utilise
  `persist-credentials: false` (`_agent-run.yml:154-162`), les clones
  supplémentaires utilisent `GIT_CONFIG_*` en environnement
  (`:170-174`), et le push utilise `GIT_ASKPASS` (`:420-425`). Le
  `x-access-token` de l’URL de push est un nom d’utilisateur, pas le secret.
- Aucun `echo` direct de secret constaté ; `::add-mask:` est utilisé pour
  l’en-tête base64 (`:170-171`, `:200-201`). Les scripts n’ont toutefois pas
  `set +x` (voir §2.13).
- Aucune sortie d’opencode n’est publiée sur un dépôt public actuellement :
  `_agent-run.yml:352-357` écrit dans `$RUNNER_TEMP` et ne l’envoie nulle part.
- Aucun secret n’est injecté dans l’environnement d’opencode : l’étape
  `_agent-run.yml:337-408` n’a pas `CI_TOKEN`/`OC_NOTIFY_KEY` dans son `env`.
  Le problème est l’accès aux scripts exécutés plus tard (§2.1).

## Verdict

VERDICT: À CORRIGER

Corrections obligatoires :

1. Figer les outils (`quota.sh`, `lifeos-guard.sh`, `notify.sh`, binaire
   `gitleaks`) hors de portée d’opencode et les exécuter par chemin absolu ;
   ne jamais exécuter un script du checkout `ci/` après opencode (§2.1).
2. Neutraliser hooks, fsmonitor, filtres et `--no-verify` pour tout git
   d’écriture ; pousser depuis une copie nue avec `CI_TOKEN` hors de portée des
   hooks du dépôt (§2.2).
3. Séparer l’exécution opencode du push/notify et revalider les inputs
   immuables (`IN_BRANCH`, `LIFEOS_WRITE`, whitelist) dans le job de push ;
   ne jamais faire confiance à `GITHUB_ENV`/`RUNNER_TEMP` après opencode (§2.3).
4. Refuser les modifications de `.github/workflows` avant push, sauf cible
   explicitement prévue et documentée (§2.4).
5. Corriger la normalisation du garde-fou (identifiants, port, `www`, `.git/`,
   query/fragment) et ajouter ces cas aux tests (§2.5).
6. Rendre la lecture seule de lifeos réellement infranchissable (propriétaire
   distinct/root, immuable, ou sandbox) et revalider avant toute décision (§2.6).
7. Interdire `lifeos` en `target_repo` et `extra_repos` ; réserver lifeos au
   clone `lifeos/` et à la branche `lifeos-ci/<job_name>` (§2.7).
8. Reprendre la porte gitleaks existante avec `--redact`, configuration/ignore
   au SHA de base, copie nue, binaire absolu et échec fermé (§2.8).
9. Passer `lifeos_write` avec `-F` (booléen typé) et ajouter `--ref` au
   dispatch de `_next.yml` (§2.9).
10. Ajouter `needs.vera.result == 'success'` (et un statut de push fiable) avant
    le chaînage (§2.10).
11. Durcir la détection quota (diffs, contexte, code indenté, prose) et ajouter
    les tests correspondants (§2.11).
12. Ajouter `github.triggering_actor` aux conditions `github.actor` (§2.12).
13. Passer l’URL et la clé de notification par stdin, ajouter `set +x`, et ne
    pas exécuter le script depuis `ci/` modifiable (§2.13).
14. Retirer `actions: write` de `_next.yml` ou l’aligner sur le jeton réellement
    utilisé (§2.14).
