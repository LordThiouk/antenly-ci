# Review of PR clean/product-ci-2026-11-25 (antenly-ci). Short run, commit the report RIGHT AWAY.

Forbidden: push, `gh`, editing anything other than `REVIEW-CLEAN.md`. Author: `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`.

1. `git diff origin/main...HEAD --stat` and read `CLEANUP.md`.
2. Check: (a) every removed file really is generic opencode/FullRun/ISA machinery, not product; (b) the 5 remaining workflows (`ci`, `pr-dispatch`, `inventory-probe`, `inventory-pass2`, `language`) reference no removed file (`rg` on every removed path); (c) no secret or URL in the diff; (d) the remaining YAML is valid (`python3 -c "import yaml,glob;[yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml')]"`).
3. Write `REVIEW-CLEAN.md`: verdict `MERGE OK` or `BLOQUANT`, then high/medium/low points with file:line. Commit with the message "review: nettoyage produit". Stop.
