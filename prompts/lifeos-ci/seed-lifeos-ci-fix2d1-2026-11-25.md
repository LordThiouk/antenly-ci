# Fix2d1: ci.yml only (very short run)

Branch `seed/lifeos-ci-2026-11-24`. Modify **only** `lifeos-ci-seed/.github/workflows/ci.yml`.
Forbidden: `git push`, `gh`, any other file. Do not run the whole test suite.

1. In the Actionlint step, add `-ignore 'SC2129'` to the actionlint command.
2. Copy into ci.yml, **as is**, the installation of `age` (age and age-keygen) and the pinned `setup-ffmpeg` step from `.github/workflows/opencode-fullrun.yml` (at the repo root of antenly-ci).
   - Look for them with `rg -n 'age|ffmpeg' .github/workflows/*.yml`.
   - Put them before the « Tests shell » step.
3. Commit **right away** (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`, message `ci(seed): actionlint ignore SC2129, age, ffmpeg`).
   - Then write the SHA to `/tmp/task_done.md` and stop.
