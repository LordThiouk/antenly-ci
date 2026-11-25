# Read-only review of lifeos-ci PR #1 (short run)

Clone: `git clone -q https://github.com/LordThiouk/lifeos-ci /tmp/l && cd /tmp/l && git fetch -q origin seed/socle-2026-11-25 && git checkout -q FETCH_HEAD`.
Read only. No changes to the code. Forbidden: `git push`, `gh`, editing anything outside the report.

Use the `requesting-code-review` method (severity: blocking / high / low). Check, in this order:
1. The sudoers rule for `emu-e2e.sh` in `.github/workflows/opencode-fullrun.yml`: no wildcard, no privilege escalation, a fixed path.
2. `chain_prompts` (JSON) in place of 3 inputs: every dispatch and every chaining step passes it correctly, and nothing still references `prompt_path_build/verify/close`.
3. The `ci.yml` triggers plus concurrency; no secret printed; `CI_TOKEN` used everywhere.
4. Duplicates that are still left (see `INVENTAIRE.md`): list them, do not fix them.

Write `REVIEW-PR1.md` at the root of `lifeos-ci-seed/` in the branch `seed/lifeos-ci-2026-11-24` of antenly-ci (the current repo), with file:line for each point and a final verdict « merge OK / à corriger ». **Commit right away** after each section. Author: `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`.
