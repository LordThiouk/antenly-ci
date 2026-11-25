# Inventory: antenly-ci vs galass-ci, one copy per function (short run, NO code)

Branch `seed/lifeos-ci-2026-11-24`. Forbidden: `git push`, `gh`, changing code or scripts.
Clone galass-ci read-only: `git clone https://github.com/LordThiouk/galass-ci /tmp/galass-ci`.

Goal: **no redundancy**. For each function, keep **only the best version**.

1. List every script (`opencode/**/*.sh`, `ci/**`, `*.ts`), workflow and workflow step (opencode-fullrun.yml, opencode-task.yml, ci.yml, ci-scripts.yml) in:
   - antenly-ci;
   - galass-ci;
   - `lifeos-ci-seed/`.
2. Group them by **function** (same role even if the name differs).
3. For each function, write a table row with:
   - the antenly version, the galass version, and the seed version (path or absent);
   - identical, or how they differ (one line);
   - **the one to keep** and why: more complete, more tested, more secure, more recent;
   - what the other has that is missing and worth bringing in (if any);
   - the tests that cover it.
4. Also flag the duplicates already present in `lifeos-ci-seed/` (two files for the same function).

Write `lifeos-ci-seed/INVENTAIRE.md` and commit **right away** after the first full section, then complete it (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`). Put the summary in `/tmp/task_done.md`: number of functions, duplicates found, files to replace or remove.
