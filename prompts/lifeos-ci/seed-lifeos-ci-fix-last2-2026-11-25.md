# The last 2 failing tests (short run)

Branch `seed/lifeos-ci-2026-11-24`. Only work under `lifeos-ci-seed/`. Forbidden: `git push`, `gh`, deleting files.
PR CI run 45554628401: 145/146 in done-check, everything else is green except these two.

1. `opencode/tests/upstream-fullrun/done-check-test.sh`, case **15c « pin lifeos dans ci.yml »**:
   - read case 15c to see exactly what it expects (pin of the lifeos ref in ci.yml);
   - the ci.yml / ci-scripts.yml merge lost it: restore it in `ci.yml` the way it was in the old `ci-scripts.yml` (see `git show 565b128^:lifeos-ci-seed/.github/workflows/ci-scripts.yml`);
   - run the test, then **commit**.
2. `opencode/tests/upstream-fullrun/with-emulators-test.sh`: « input with_emulators absent du workflow »:
   - read what the test expects (which workflow file, which input);
   - copy the `with_emulators` input from galass-ci (`git clone -q --depth 1 https://github.com/LordThiouk/galass-ci /tmp/galass-ci`, `opencode-fullrun.yml`) into the workflow the test reads, **without duplicating** anything already present;
   - run the test plus actionlint, then **commit**.

Author: `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. `/tmp/task_done.md`: SHAs plus the OK/FAIL of both tests.
