# One task only: restore `isa-human-tick.yml` in antenly-ci. Commit RIGHT AWAY.

Forbidden: push, `gh`. Author: `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`.
Papa keeps `isa-human-tick.yml` (product CI). It was removed by mistake in f4a983f.

1. `git log --oneline -3`, then restore it from the commit before the cleanup: `git checkout f4a983f~1 -- .github/workflows/isa-human-tick.yml`, plus every file it calls (read it, e.g. `opencode/allowed-repos.sh`; restore each one the same way from `f4a983f~1`).
2. Check the YAML with `python3 -c "import yaml;yaml.safe_load(open('.github/workflows/isa-human-tick.yml'))"` and that each file it references exists. In `CLEANUP.md`, change those files to KEEP. Commit with the message "fix: garde isa-human-tick (produit)". Stop.
