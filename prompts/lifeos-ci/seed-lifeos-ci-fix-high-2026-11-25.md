# Fix the 2 high-severity review points (short run, commit after each step)

Branch `seed/lifeos-ci-2026-11-24`, folder `lifeos-ci-seed/`. Forbidden: `git push`, `gh`, deleting files. Author: `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. Read `lifeos-ci-seed/REVIEW-PR1.md` first.
Reference: `git clone -q --depth 1 https://github.com/LordThiouk/galass-ci /tmp/g`, file `/tmp/g/.github/workflows/opencode-fullrun.yml`, lines 820–847.

## Step 1: create the emu-e2e token and state (high #2)
In `lifeos-ci-seed/.github/workflows/opencode-fullrun.yml`, right before the sudoers block for emu-e2e (~line 977), copy the galass-ci block from lines ~820–842:
- `/opt/fullrun-live/emu-e2e.token` as root 0600;
- `$T/emu-e2e.state` as root 0644.

Only when `with_emulators` is true, as in galass. Use the secret `CI_TOKEN` in place of `GALASS_TOKEN`. Never print the token. **Commit.**

## Step 2: remove the sudoers wildcard (high #1)
Line ~982: `/opt/fullrun-tools/emu-e2e.sh status *`.
1. Read `lifeos-ci-seed/opencode/emu-e2e.sh`: what argument does `status` take?
2. If `status` works with no argument, the rule becomes `.../emu-e2e.sh status` with no wildcard. Otherwise, make `emu-e2e.sh status` validate its argument strictly (regex `^[0-9]+$` or the real format, otherwise exit 2), and keep the narrowest possible rule.
3. Adjust `opencode/tests/upstream-fullrun/with-emulators-test.sh` if it checks the exact rule.

Run `bash opencode/tests/upstream-fullrun/with-emulators-test.sh 2>&1 | tail -3`, then **commit**.

## Step 3 (if time is left): `_next.yml:130`
Use `-F` instead of `-f` if the review says it is a boolean or number. **Commit.**

`/tmp/task_done.md`: SHAs plus test results.
