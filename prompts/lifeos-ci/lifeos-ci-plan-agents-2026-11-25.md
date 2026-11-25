# Plan: one workflow per LifeOS agent (read-only plus a single file, short run)

Forbidden: `git push`, `gh`, changing code. Only write `lifeos-ci-seed/PLAN-AGENTS.md` on the current branch.

1. Clone: `git clone -q --depth 1 https://x-access-token:${CI_TOKEN:-$GH_TOKEN}@github.com/LordThiouk/lifeos /tmp/lifeos 2>/dev/null || git clone -q --depth 1 https://github.com/LordThiouk/lifeos /tmp/lifeos`
2. List the agents and the FullRun skill (do not read anything else):
   `fd -t f . /tmp/lifeos | rg -i 'agents?/|fullrun|skills?/.*(fullrun|run)' | head -80`
3. For each agent: name, role in one line, and the FullRun step it handles (plan / build / verify / close…).

Write `PLAN-AGENTS.md` (at most 80 lines), with **a commit after each section**:
- **Agents**: a table with agent, role, FullRun step, and the lifeos source file.
- **Workflows to create**: one `.github/workflows/agent-<name>.yml` per agent, all calling `_agent-run.yml` (no duplication), with the same steps as the FullRun skill.
- **Tasks to run in parallel**: one task per workflow, independent ones together, plus dependencies.
- **Open questions**: what is missing or ambiguous.

Author: `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`. **Commit right away.**
