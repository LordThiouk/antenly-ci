# Inventory 1/2: scripts only (short run, NO code)

Branch `seed/lifeos-ci-2026-11-24`. Forbidden: `git push`, `gh`, changing code.

**Step A (2 min max, commit right away):**
```
git clone -q --depth 1 https://github.com/LordThiouk/galass-ci /tmp/galass-ci
for d in . /tmp/galass-ci lifeos-ci-seed; do (cd $d && fd -t f -e sh -e ts -e py . opencode ci 2>/dev/null | while read f; do echo "$d|$f|$(sha256sum "$f"|cut -c1-12)|$(wc -l <"$f")"; done); done > /tmp/raw.txt
```
Turn `/tmp/raw.txt` into a table in `lifeos-ci-seed/INVENTAIRE.md`:
- one row per **file name**, with antenly/galass/seed columns showing short sha and line count;
- mark identical when the sha values match.

Commit immediately (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`).

**Step B:** only for the files that **differ** or that have **different names but the same role**:
- read their header and the `diff --stat`;
- add one line per row: which one to keep (more complete, tested or secure) and what the other has that is missing;
- flag the **duplicates** inside `lifeos-ci-seed/`.

Commit after every 10 rows.

`/tmp/task_done.md`: number of files, identical, different, duplicates in the seed.
