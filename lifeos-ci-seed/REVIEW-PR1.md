# Revue PR #1 — lifeos-ci

- Dépôt revu : `LordThiouk/lifeos-ci`, branche `seed/socle-2026-11-25`.
- Commit revu : `fd3f9ce0e33c3e5dd705c29a77d79d916ab6fbbb` (`seed: sync 869190a`), obtenu par
  `git clone https://github.com/LordThiouk/lifeos-ci /tmp/l && git fetch origin seed/socle-2026-11-25 && git checkout FETCH_HEAD`.
- Méthode : `requesting-code-review`, sévérités **blocking / high / low**.
- Mode : lecture seule ; aucun fichier du dépôt revu n'a été modifié.
- Les chemins `fichier:ligne` ci-dessous sont relatifs à la racine de `lifeos-ci` (clone `/tmp/l`),
  pas à `lifeos-ci-seed/`.
- Contrôle exécuté : `bash opencode/tests/upstream-fullrun/with-emulators-test.sh` → rc 0 (25 OK).
  Ce test ne couvre pas le provisioning réel du jeton/état e2e (voir §1).

## 1. Règle sudoers `emu-e2e.sh` — `.github/workflows/opencode-fullrun.yml`

Bloc audité : `opencode-fullrun.yml:976-985` (créé seulement si `WITH_EMULATORS=true`). L'outil est
figé root en `opencode-fullrun.yml:897-902` dans `/opt/fullrun-tools/emu-e2e.sh` (chemin fixe,
root:root 0755), et `/opt` est rendu non inscriptible en `:894-895`.

- **[high] Wildcard dans une règle `NOPASSWD` root.** `opencode-fullrun.yml:982` autorise
  `/opt/fullrun-tools/emu-e2e.sh status *`. Le `*` final de sudoers accepte un nombre arbitraire
  d'arguments : c'est exactement le wildcard que le point de revue interdit. Le risque est atténué
  aujourd'hui par `opencode/emu-e2e.sh:389` (`status` n'accepte qu'un id `^[0-9]{1,20}$`, les
  arguments suivants sont ignorés), mais la règle root reste plus large que nécessaire et le
  devient dangereuse si le script évolue. `opencode/tests/upstream-fullrun/with-emulators-test.sh:374`
  **fige** même ce wildcard comme attendu (`grep -q 'emu-e2e.sh status \*'`) : un correctif devra
  aussi ajuster ce test. Correctif attendu : retirer `status *` de la règle (ou le remplacer par une
  variante sans wildcard, p. ex. un `status` sans argument lisant un fichier root) et ne garder que
  `run` / `resolve-refs` (sans argument) plus le strict nécessaire.
- **Chemin fixe : OK.** `opencode-fullrun.yml:982` cible uniquement
  `/opt/fullrun-tools/emu-e2e.sh`, installé root-owned en `:897-902` ; aucune commande arbitraire,
  aucun `ALL` de commande.
- **Pas d'escalade au-delà de l'outil : OK pour l'environnement.** `env_reset` et `secure_path`
  sont posés en `:980-981` ; l'appel `sudo -n -H` de `opencode/emu-e2e.sh:59` ne propage pas
  l'environnement de l'agent. Le `NOPASSWD` root est le mécanisme voulu (le jeton doit rester hors
  d'opencode).
- **[high] `with_emulators=true` est non fonctionnel : jeton et état e2e jamais provisionnés.**
  Le workflow crée la règle sudoers mais n'écrit jamais `/opt/fullrun-live/emu-e2e.token` ni
  `/opt/fullrun-tools/emu-e2e.state` : un `grep` sur `.github/workflows/` ne trouve aucune
  occurrence de `emu-e2e.token` / `emu-e2e.state` (seul `:2039` lit `/opt/fullrun-live/emu-run`).
  Or `opencode/emu-e2e.sh:20` lit `CANON_TOKEN=/opt/fullrun-live/emu-e2e.token`, `:19`
  `CANON_STATE=/opt/fullrun-tools/emu-e2e.state`, et `:152-160` (`read_token`, appelé en `:185`,
  `:391`, `:407`) échoue si le jeton est absent. De plus, lancé via `sudo` avec `env_reset`,
  `IN_BRANCH` n'est plus visible : `load_config` (`:87-107`) ne peut pas retomber sur
  l'environnement et `:121` échoue (« branche de travail manquante »). Conséquence :
  `with_emulators=true` échoue dès le premier `emu-e2e.sh run`. `INVENTAIRE.md:292` confirme que
  le provisioning (jeton root 0600, `emu-run`/`emu-resume`, état) reste « à porter depuis galass ».
  À corriger avant d'exposer l'option, ou retirer l'option tant que le provisioning n'est pas porté.

**Verdict section 1 : à corriger** (wildcard `status *` + provisioning e2e absent).

## 2. `chain_prompts` (JSON) à la place des 3 entrées — `.github/workflows/opencode-fullrun.yml`

- **Entrées remplacées : OK.** Les trois entrées `prompt_path_build` / `prompt_path_verify` /
  `prompt_path_close` ont disparu de `workflow_dispatch` (diff `fd3f9ce`) et sont remplacées par
  `chain_prompts` (`opencode-fullrun.yml:96-99`, type non explicite → défaut GitHub `string`).
  Le workflow a **24 entrées**, sous la limite GitHub de 25, conforme à l'objectif annoncé.
- **Lecture / validation : OK.** Les trois phases sont extraites par
  `fromJSON(inputs.chain_prompts || '{}')` en `:176-178` (env du job) et re-pinnées en
  `:1836-1838` (step `chain`, jamais depuis l'env empoisonnable). La garde exige les trois prompts
  quand `chain_enabled=true` (`:278-283`) et choisit le prompt effectif selon `chain_phase`
  (`:290-301`).
- **Dispatch du lien suivant : OK.** `prompts_json` est reconstruit en `:2047-2048` puis transmis
  en `-f chain_prompts="$prompts_json"` (`:2061`) ; `prompt_path` reste le prompt plan inchangé
  (`:2052`) et `chain_phase` passe par `:2060`. `chain_progress` reste au format `count/max`
  (`:2061`). Aucun autre `gh workflow run opencode-fullrun.yml` n'existe dans le dépôt.
- **Chaîne `_next.yml` : hors périmètre `chain_prompts`.** `_next.yml:127-134` enchaîne des
  workflows `fr-*.yml` basés sur `_agent-run.yml`, qui n'ont pas d'entrée `chain_prompts` ; rien à
  transmettre. (Voir toutefois le défaut `-f lifeos_write` en §3.)
- **[low] Référence morte dans un message d'erreur.** `opencode-fullrun.yml:282` affiche encore
  « chain_enabled=true exige prompt_path_build/verify/close » alors que ces entrées n'existent
  plus ; le message doit nommer `chain_prompts`. Même résidu cosmétique dans le libellé de test
  `opencode/tests/upstream-fullrun/first-link-prompt-test.sh:102` (« prompt_path_build »).
  Aucune référence **fonctionnelle** aux anciennes entrées ne subsiste.
- **[low] JSON invalide = échec d'évaluation d'expression.** Un `chain_prompts` non JSON fait
  échouer `fromJSON(...)` avant la garde (message générique), au lieu du message clair de `:282`.
  Ce n'est pas un défaut de sécurité ; une validation explicite serait plus lisible.

**Verdict section 2 : à corriger** (fonctionnel OK ; message `:282` à mettre à jour).
