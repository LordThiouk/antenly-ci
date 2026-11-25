# Fix2d : make the lifeos-ci-seed CI pass

Branch `seed/lifeos-ci-2026-11-24`, HEAD 2eaea94. Only work under `lifeos-ci-seed/`.
Forbidden: `git push`, `gh`, deleting files, rewriting from scratch.
Rule: **copy what already exists** in antenly-ci or galass-ci (same file or same lines). Do not invent.
Short run: **commit after each test you fix** (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`).

The lifeos-ci CI (run 45539197104) fails as follows.

1. **Actionlint**: the only remaining error is SC2129 (style) at `.github/workflows/opencode-fullrun.yml:1996`.
   - Do NOT touch `opencode-fullrun.yml`.
   - In `ci.yml`, run actionlint with `-ignore 'SC2129'` (or the equivalent shellcheck config), then re-run actionlint locally to confirm.
2. **Failing shell tests** (`opencode/tests/upstream-fullrun/`, run through `opencode/tests/run-all.sh`):
   - allowed-repos-cwd-test.sh: « allowed-repos.sh non mentionné dans le workflow »
   - ffmpeg-install-test.sh: « pin setup-ffmpeg introuvable dans ci.yml »
   - leaklog-test.sh: « age absent »; livelog-test.sh: « age-keygen »
     - Install `age` in ci.yml the way antenly-ci does.
   - merge-signed-carry-test.sh: « merge-signed-carry.sh non installé dans le workflow »
   - preannot-test.sh: « ci-preamble.md ne cite pas l'outil figé »
   - hmac-state-test.sh: B1 status=failed absent / DELETE en échec silencieux
   - preflight-test.sh: préflight placement, `--isa` missing, a broken bun stub, README missing cause/scope rule
   - checkpoint-watchdog-verdict-test.sh, done-check-test.sh, stop-step-target-agent-test.sh, unit-contract-test.sh, with-emulators-test.sh

   For each test:
   - Cause = a missing file, a wrong path, or a test that targets a workflow of the original repo?
     - Fix by copying the original.
     - If the test checks a workflow that does not exist in lifeos-ci (for example antenly's ci.yml), point it at the right copied workflow (opencode-fullrun.yml) or at the copied original workflow file.
   - Re-run that test locally.
   - Start with the quickest ones: age, ffmpeg, allowed-repos, merge-signed-carry, preannot.
3. At the end, run `bash opencode/tests/run-all.sh` from `lifeos-ci-seed/`.
   - Write to `/tmp/task_done.md`: SHAs, tests that are OK, tests still FAIL with their cause in one line.
