# The 2 tests: mechanical (very short run, commit after each step)

Branch `seed/lifeos-ci-2026-11-24`, folder `lifeos-ci-seed/`. Forbidden: `git push`, `gh`, deleting files. Author: `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`.

## Step 1 (2 min max): case 15c
`ci-scripts.yml` was deleted (Papa's OK); the pin `ref: 4fac2d59de94bf6a5fa6c68c7f09874a2f9cd634` is already in `ci.yml`. Only the test is out of date.
In `opencode/tests/upstream-fullrun/done-check-test.sh`, line ~459:
- remove the condition `&& grep -q "ref: 4fac2d5..." "$ROOT/.github/workflows/ci-scripts.yml"`;
- in the ok message for 15c, replace « ci.yml et ci-scripts.yml épinglent » with « ci.yml épingle ».

Run `bash opencode/tests/upstream-fullrun/done-check-test.sh 2>&1 | tail -3`, then **commit right away** (`test(seed): 15c sans ci-scripts.yml`).

## Step 2: input `with_emulators`
The test (`with-emulators-test.sh` line 386–393) wants, in `.github/workflows/opencode-fullrun.yml` under `workflow_dispatch.inputs`:
```yaml
      with_emulators:
        description: "…"
        type: boolean
        default: false
```
Warning: GitHub allows **at most 25 inputs**. Count them (`rg -c '^      [a-z_]+:$'` within the inputs block).
- If there are already 25, do it the way galass-ci does: `git clone -q --depth 1 https://github.com/LordThiouk/galass-ci /tmp/g && rg -n -A4 'with_emulators:' /tmp/g/.github/workflows/opencode-fullrun.yml`.
- Copy its approach exactly (same input; if galass-ci merged another input to make room, do the same merge).

Then run `bash opencode/tests/upstream-fullrun/with-emulators-test.sh 2>&1 | tail -3` and actionlint if available, then **commit**.

`/tmp/task_done.md`: SHAs plus OK/FAIL for both tests.
