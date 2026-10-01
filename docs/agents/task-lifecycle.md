# Task lifecycle

## Create (coordinator)

1. Turn each request into a GitHub issue using the **Task** form. The issue has a goal, acceptance criteria, verification and an Agent brief.
2. Labels: one or more `domain:*`, `kind:*`, the highest `risk:*` (if any), one `size:*`, `horizon:*`. Add `founder-review` or `decision-gate` when the Founder is involved.
3. The task ID is the issue's area prefix plus its zero-padded number (`DOM-007` for #7). Use it in the branch, PR title, commits and the outcome log.
4. Pick the owning role and agent ([roles-and-routing.md](roles-and-routing.md)) and the minimum model class ([model-routing.md](model-routing.md)).
5. Use several agents only for independent subtasks with disjoint write scopes. The coordinator integrates and verifies. A small one-step task may be done by the coordinator directly.

## Execute (owner)

1. Read `AGENTS.md`, the issue (`gh issue view <n>`) and only the files in its Agent brief.
2. Confirm one outcome, the write scope, the acceptance criteria and what is out of scope. Fill gaps only when they follow from the repository; stop at a decision that changes the product, a public contract or an active gate.
3. Branch `<prefix>-<nnn>-slug` from `main`. Read [change-safety.md](change-safety.md) before code.
4. Verify as the issue says; levels of evidence are in [docs/testing.md](../testing.md).
5. Add `logs/outcomes/<TASK-ID>.json` ([schema](../../logs/README.md)) with honest attempts and outcome.
6. Push the branch and open a PR (template) with `Closes #<n>`.
7. Report back in at most five points: status, PR, up to three findings, tests run and not run, blocker or next step. As an Orca worker, put this in `worker_done` with an explicit `--outcome`.

## Finish (coordinator)

Review, merge and close as in [review-and-merge.md](review-and-merge.md). The owner never merges.
