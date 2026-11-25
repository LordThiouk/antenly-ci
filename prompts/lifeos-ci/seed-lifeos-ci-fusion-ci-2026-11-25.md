# Merge ci.yml + ci-scripts.yml (short run, Papa's OK 05:16)

Branch `seed/lifeos-ci-2026-11-24`. Only work under `lifeos-ci-seed/`.
Read the « ci.yml et ci-scripts.yml » and « Points de sécurité » sections of `lifeos-ci-seed/INVENTAIRE.md`.
Forbidden: `git push`, `gh`, touching `opencode-fullrun.yml` (except the sudoers line, step 3), `_agent-run.yml` or any other workflow.

1. Merge `lifeos-ci-seed/.github/workflows/ci-scripts.yml` into `ci.yml`:
   - a single PR/push trigger;
   - a single LifeOS checkout, **with `CI_TOKEN`** (no `LIFEOS_READ_TOKEN` anywhere);
   - each tool (age, ripgrep, bun, ffmpeg, shellcheck, actionlint) installed **only once**;
   - keep every check from both files, plus `gitleaks detect` taken from galass-ci (pinned).
   Then `git rm lifeos-ci-seed/.github/workflows/ci-scripts.yml` (Papa authorized this deletion only).
   Run actionlint on the result, then **commit**.
2. Check that `rg -n LIFEOS_READ_TOKEN lifeos-ci-seed` returns nothing.
3. with-emulators: add the sudoers `status` the test expects (« sudoers : status absent de la liste autorisée »), **copied** from galass-ci (`fullrun-emu-e2e`).
   Run `bash lifeos-ci-seed/opencode/tests/upstream-fullrun/with-emulators-test.sh`, then **commit**.

Author of every commit: `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`.
Write `/tmp/task_done.md`: SHAs, actionlint result, with-emulators result.
