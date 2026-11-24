# opencode-task : accès corpus Hugging Face + ffmpeg pour la cible antenly

But : permettre au vrai test radio des moteurs d'empreinte de lire le corpus privé HF `LordThiouk/antenly-corpus` (~2,4 Go, .opus) et de décoder l'Opus.

À faire dans `.github/workflows/opencode-task.yml` (cible antenly seulement) :
1. Installer ffmpeg/ffprobe avec exactement le même schéma que `opencode-fullrun.yml` (setup-ffmpeg épinglé par SHA + secours apt + vérification).
2. Installer la CLI Hugging Face (`pip install -U "huggingface_hub[cli]"` ou uv) et exposer le secret existant `HF_TOKEN` à l'étape opencode via env (jamais écho, jamais dans le prompt, jamais commité). Ajouter un input booléen optionnel `with_hf_corpus` (défaut false) : si true, télécharger le dataset dans `$RUNNER_TEMP/corpus/antenly-corpus` AVANT opencode (hors target/, lecture seule chmod a-w), exposé en `ANTENLY_CORPUS_DIR`, et une ligne dans le prompt qui le signale. Échec de téléchargement non bloquant, avec résumé.
3. Garder le reste du workflow inchangé ; la porte gitleaks/push ne doit jamais voir le corpus.

Sortie : le jeton CI ne peut pas pousser .github/workflows. Donc écris le changement sous forme de patch `docs/patches/opencode-task-hf-ffmpeg-2026-11-24.patch` (applicable avec `git apply` sur main) + rapport `docs/reports/opencode-task-hf-ffmpeg-2026-11-24.md` (ce qui change, comment vérifier). Ne commite rien sous .github. Valide le YAML patché (python yaml) avant de finir. Pas de PR, pas de push sur main.
