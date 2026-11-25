# Fix2d5a: antenly side of TESTS-DIAG (short run)

Branch `seed/lifeos-ci-2026-11-24`. Read `lifeos-ci-seed/TESTS-DIAG.md` first.
Forbidden: `git push`, `gh`, deleting files, rewriting.
**Copy** from antenly-ci (repo root) only.

Scope: the tests **preflight**, **done-check**, **checkpoint-watchdog-verdict** only.
1. Copy into `lifeos-ci-seed/` the README sections that preflight and done-check expect (codes table, cause, scope, relaunch parameters), taken from the antenly-ci README.
2. If the table names it, copy `ci-scripts.yml` (and the pinned parts of antenly's ci.yml that done-check expects).
3. In `lifeos-ci-seed/.github/workflows/ci.yml`, add the private **lifeos** clone exactly the way antenly-ci does it for its tests (same step, same secret, `CI_TOKEN`, read-only). Do not print any secret.
4. After each point, run the tests concerned (those that do not need lifeos) and **commit right away** (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`).

`/tmp/task_done.md`: SHAs + OK/FAIL/not replayable for each of the 3 tests.
