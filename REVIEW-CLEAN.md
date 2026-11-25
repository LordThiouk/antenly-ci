# Review — `clean/product-ci-2026-11-25` (antenly-ci)

Base : `origin/main` = `22f672e`. HEAD = `4263936` (`prompt: review clean`).
Diff `origin/main...HEAD` : 67 fichiers, +136 / −12869.

Verdict : **MERGE OK**

## High

- (a) Périmètre des suppressions correct : les 64 fichiers retirés sont tous de la
  machinerie générique, aucun test/déploiement produit.
  - `.github/workflows/ci-scripts.yml:1` teste `opencode/tests/*-test.sh` (générique).
  - `.github/workflows/isa-human-tick.yml:1` est l'outillage de gouvernance ISA.
  - `.github/workflows/opencode-fullrun.yml`, `.github/workflows/opencode-task.yml`,
    `opencode/**` et `docs/patches|reports/**` sont FullRun/opencode.
  - Les workflows produit (`ci`, `pr-dispatch`, `inventory-probe`, `inventory-pass2`,
    `language`) sont tous conservés (`.github/workflows/ci.yml:1`).
- (b) Aucune référence morte : `grep -rF` de chacun des 64 chemins supprimés sur
  `.github/`, `README.md` et `prompts/` → 0 occurrence. Les seules occurrences
  d'« opencode » restantes sont du texte/commentaire (`README.md:7`) ou le mot
  produit `preannot` (`ci.yml:135`, `language.yml:97`).
- (d) YAML valide : `yaml.safe_load` sur les 5 `.github/workflows/*.yml` → OK.
- (c) Aucun secret ni URL ajouté dans le diff : uniquement des noms de secrets déjà
  utilisés (`secrets.ANTENLY_TOKEN`, `HF_TOKEN`) et de la prose.

## Medium

- `prompts/review-clean.md:1` : ce prompt de revue générique est ajouté et conservé
  dans le dépôt produit, alors que l'objectif est « uniquement la CI produit »
  (`CLEANUP.md:1-8`). À retirer avant/après merge pour respecter le périmètre.

## Low

- `CLEANUP.md:83` : la ligne déclare `prompts/clean-product-ci.md` en REMOVE, mais ce
  fichier n'existe pas sur `origin/main` (aucun `prompts/` dans l'arbre de base) ;
  ligne d'inventaire inexacte à corriger.
