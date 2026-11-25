# Clean this repo: keep ONLY the product CI. Short run, commit after each step.

Forbidden: push, `gh`, reading or writing secrets, touching `main`. Author: `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`.
Context: the generic opencode / FullRun / agent machinery now lives in `LordThiouk/lifeos-ci`. This repo must keep only what builds, tests, checks or deploys the PRODUCT (Galass or Antenly): product test workflows, emulators, product checks, CI triggered by product PRs.

1. `rg --files .github scripts opencode prompts 2>/dev/null` plus the root files. Write `CLEANUP.md`: a table of every file → KEEP (product) or REMOVE (generic opencode/FullRun/agents/prompts/guard machinery, duplicated in lifeos-ci), with a one-line reason. Commit.
2. Remove (`git rm`) the REMOVE files. If a KEEP workflow calls a removed file, keep that file and change it to KEEP in CLEANUP.md. Commit.
3. Update the README: one paragraph "product CI; the opencode/FullRun runs live in LordThiouk/lifeos-ci". Check the remaining YAML files with `python3 -c "import yaml,sys;[yaml.safe_load(open(f)) for f in sys.argv[1:]]" .github/workflows/*.yml`. Commit. Stop.
