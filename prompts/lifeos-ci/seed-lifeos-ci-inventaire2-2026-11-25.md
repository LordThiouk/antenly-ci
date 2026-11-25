# Inventory 2/2: workflows and steps (short run, NO code)

Branch `seed/lifeos-ci-2026-11-24`. Forbidden: `git push`, `gh`, changing code.
Read `lifeos-ci-seed/INVENTAIRE.md` (the scripts part is already done). Add a section « Workflows et steps ».

**Step A (commit right away):**
```
git clone -q --depth 1 https://github.com/LordThiouk/galass-ci /tmp/galass-ci
for d in . /tmp/galass-ci lifeos-ci-seed; do for f in $d/.github/workflows/*.yml; do echo "== $f"; rg -n '^\s+- name:' "$f" | sed 's/^\([0-9]*\):\s*- name:/\1 /'; done; done > /tmp/steps.txt
```
Build a table: workflow file × (antenly / galass / seed), with the number of steps and the steps present in only one of them.

Commit right away (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`).

**Step B:** for the workflows that do the same job (opencode-fullrun, opencode-task, ci, ci-scripts, etc.):
- which version to keep as the base;
- which steps from the other one to bring in (list);
- which steps are **duplicated** within the seed (same role twice, for example two lifeos clones or two installs of the same tool);
- point out `with_emulators`/sudoers and the token in `ci-scripts.yml` (`LIFEOS_READ_TOKEN`, to replace with `CI_TOKEN`).

Commit after each workflow. `/tmp/task_done.md`: summary in 5 lines.
