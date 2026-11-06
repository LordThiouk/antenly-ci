# antenly-ci

CI publique (minutes GitHub Actions gratuites) pour le dépôt privé `LordThiouk/antenly`.
Ce dépôt ne contient que des workflows : le code reste dans `antenly`, récupéré au run
avec le secret `ANTENLY_TOKEN` (jeton fine-grained limité à `antenly`).

- `ci.yml` : statut `antenly-ci` pending, puis rust, python, preannot-ina (vrai inaSpeechSegmenter + TensorFlow CPU), licences, secrets (gitleaks), puis success/failure sur le commit d'`antenly` testé.
- `pr-dispatch.yml` : cron toutes les 15 min (ou à la main), lance `ci.yml` pour chaque SHA de tête de PR ouverte d'`antenly` sans statut `antenly-ci`. GitHub suspend les crons d'un dépôt public après 60 jours sans activité : le réactiver dans l'onglet Actions.
- `inventory-probe.yml` : passe 1 (cron lundi 04:00 UTC, ou à la main).
- `inventory-pass2.yml` : passe 2 1 h plus tard (cron lundi 05:00 UTC), rapport, gates, PR `inventory/auto-update` sur `antenly`.

Les logs et artifacts de ce dépôt sont publics. Aucun push direct sur une branche de base d'`antenly` ; le merge reste manuel.
