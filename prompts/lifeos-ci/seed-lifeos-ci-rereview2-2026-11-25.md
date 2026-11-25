# Re-review PR #1: one write right away (very short)

Branch `seed/lifeos-ci-2026-11-24`. Forbidden: `git push`, `gh`, changing code. Do not read anything else.

Run only:
```
cd lifeos-ci-seed
git show 8218748 3d406a7 a7e2103 --stat
git show 3d406a7 | rg -n 'NOPASSWD|exit 2|\[0-9\]'
git show 8218748 | rg -n 'token|chmod|chown|with_emulators'
git show a7e2103 | rg -n '\-F '
```

Then add right away, at the end of `REVIEW-PR1.md`, a section « Re-revue 2026-11-25 » of at most 15 lines:
1. token: root, 0600, not printed, only if with_emulators;
2. sudoers `status [0-9]*` plus the `^[0-9]{1,20}$` check in emu-e2e.sh: is there any escalation left?
3. `-F` in `_next.yml`.

End with « Verdict : merge OK » or « Verdict : à corriger (raison) ».

**Commit right away** (`docs(seed): re-revue PR1`). Author: `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. Nothing else.
