# Fix2d4: diagnose the 7 remaining tests (short run, NO code fix)

Branch `seed/lifeos-ci-2026-11-24`. Forbidden: `git push`, `gh`, changing code.

These tests in `lifeos-ci-seed/opencode/tests/upstream-fullrun/` still fail:
- checkpoint-watchdog-verdict
- done-check
- hmac-state (B1 status=failed absent, DELETE silencieux)
- preflight (placement of the préflight step, `--isa`, README codes table)
- stop-step-target-agent (verify/Silas not passed through, values like 'deploy' accepted)
- unit-contract
- with-emulators (« sudoers : status absent »)

Main hypothesis: the tests come from a version (antenly-ci main or galass-ci main) different from the copied `opencode-fullrun.yml` / scripts.

For each test:
1. Run it in antenly-ci at the root (`bash opencode/tests/<test>`) and, if possible, against galass-ci (clone it read-only through `git clone https://github.com/LordThiouk/galass-ci` if it is accessible without gh). Does it pass there?
2. If it passes there: list the files (workflow, script, README) that differ between the original and `lifeos-ci-seed/` and that the test reads (`diff`).
3. If it does not pass anywhere: say so (an orphan test).

Write `lifeos-ci-seed/TESTS-DIAG.md`: one line per test with **where it passes**, **the files to recopy**, and **orphan yes/no**. Commit right away (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`), then copy that table into `/tmp/task_done.md`.
