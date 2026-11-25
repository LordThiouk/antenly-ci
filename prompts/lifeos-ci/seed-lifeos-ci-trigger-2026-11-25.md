# ci.yml: one run per commit (very short run)

Branch `seed/lifeos-ci-2026-11-24`. Modify **only** `lifeos-ci-seed/.github/workflows/ci.yml`. Forbidden: `git push`, `gh`.

Today `on: push` + `pull_request` runs CI **twice** on every commit of a PR.

Replace the triggers with:
```yaml
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
```

Add `cancel-in-progress: true` to the existing `concurrency` block.

Run actionlint on the file, commit right away (author `Papa Diop <76528706+LordThiouk@users.noreply.github.com>`, message `ci(seed): une seule CI par commit`), write the SHA to `/tmp/task_done.md`.
