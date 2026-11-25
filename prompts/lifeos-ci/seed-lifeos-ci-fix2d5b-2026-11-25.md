# Fix2d5b: galass side of TESTS-DIAG (short run)

Branch `seed/lifeos-ci-2026-11-24`. Read `lifeos-ci-seed/TESTS-DIAG.md` first.
Forbidden: `git push`, `gh`, deleting files, rewriting.
**Copy** from galass-ci (`git clone https://github.com/LordThiouk/galass-ci /tmp/galass-ci`, read-only).

Scope: the tests **stop-step-target-agent**, **hmac-state**, **unit-contract**, **with-emulators** only, in that order.

For each one:
- copy from galass-ci only the parts the table names: `run-fullrun.sh` (galass version) for stop-step; the `restore_state` steps (hmac-state), `chain` steps (unit-contract) and `with_emulators` steps with the sudoers line (with-emulators) into `lifeos-ci-seed/.github/workflows/opencode-fullrun.yml`;
- **add, never remove**, the existing antenly steps, so that the tests already passing stay OK;
- run the test concerned plus `allowed-repos-cwd-test.sh` and `merge-signed-carry-test.sh` (non-regression);
- **commit right away** (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`).

`/tmp/task_done.md`: SHAs + OK/FAIL/not replayable for each test.
