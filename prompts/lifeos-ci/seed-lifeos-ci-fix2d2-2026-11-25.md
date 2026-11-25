# Fix2d2: 3 copy tests (short run)

Branch `seed/lifeos-ci-2026-11-24`. Only work under `lifeos-ci-seed/`.
Forbidden: `git push`, `gh`, deleting files, rewriting.
**Copy** what exists in antenly-ci (repo root) or galass-ci. **Do not touch** `opencode-fullrun.yml`.

These 3 tests in `lifeos-ci-seed/opencode/tests/upstream-fullrun/` fail:
- `allowed-repos-cwd-test.sh`: « allowed-repos.sh non mentionné dans le workflow »
- `merge-signed-carry-test.sh`: « merge-signed-carry.sh non installé dans le workflow »
- `preannot-test.sh`: « ci-preamble.md ne cite pas l'outil figé »

For each one, in this order:
- read the test and see which file it checks;
- fix by copying from the original (a missing file, or a test path pointing at a workflow or file that has a different name in lifeos-ci-seed);
- run that test only (`bash <test>`);
- **commit right away** (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`).

If a test needs a change in `opencode-fullrun.yml`, write it down and move on to the next one.
At the end, write to `/tmp/task_done.md` the SHAs and the OK/FAIL of each of the 3 tests.
