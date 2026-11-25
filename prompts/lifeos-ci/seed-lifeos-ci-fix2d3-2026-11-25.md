# Fix2d3: 2 tests, diagnose then copy (short run)

Branch `seed/lifeos-ci-2026-11-24`. Only work under `lifeos-ci-seed/`.
Forbidden: `git push`, `gh`, deleting files, rewriting.

Still failing (lifeos-ci CI, run 45542232249):
- `opencode/tests/upstream-fullrun/allowed-repos-cwd-test.sh`: « allowed-repos.sh non mentionné dans le workflow »
- `opencode/tests/upstream-fullrun/merge-signed-carry-test.sh`: « merge-signed-carry.sh non installé dans le workflow »

For each test:
1. Find the exact path of the workflow the test reads (a variable or path hard-coded in the test).
2. Compare it with the same test in antenly-ci (`opencode/tests/` at the root) and with `.github/workflows/opencode-fullrun.yml` at the root of antenly-ci, using `rg -n 'allowed-repos|merge-signed-carry'`.
3. Fix by copying:
   - if the test points at a wrong path, fix the path in the test;
   - if `lifeos-ci-seed/.github/workflows/opencode-fullrun.yml` lacks the lines that are in the antenly-ci original, copy those lines **as is**, and nothing else.
4. Run `bash <test>` and **commit right away** (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`).

**Write `/tmp/task_done.md` first** with the cause of each test (one line), then update it with the SHAs and OK/FAIL.
