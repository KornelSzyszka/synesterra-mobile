# Review, CI and merge

## Flow for a code task

1. A GitHub issue with labels exists; the task ID is its prefix plus the issue number. Branch `<prefix>-<nnn>-slug` (e.g. `dom-007-session-model`) from current `main`. In Orca: `orca worktree create --issue <n>`. Give parallel tasks separate worktrees.
2. The author commits only the task's changes and runs locally: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, the narrowest `flutter test`.
3. The author pushes the branch and opens a PR to `main` from the PR template. The PR includes the task ID, `Closes #<n>`, the goal, changes, tests and risks.
4. CI ([ci.yml](../../.github/workflows/ci.yml)) must be green: model log check, format, analyze, test, `flutter build apk --debug`. Run iOS by hand (`gh workflow run CI -f ios=true --ref <branch>`) when the task touches `ios/` or native iOS code.
5. A cross-agent review (below) with no unresolved `blocker` or `major` finding.
6. The task's model outcome record `logs/outcomes/<TASK-ID>.json` is in the PR; CI validates it.
7. Only the coordinator merges: squash, delete the branch. The issue closes through `Closes #n`. Remove `founder-review` once the Founder has accepted.

GitHub Free does not offer branch protection for private repositories. These conditions are the coordinator's rule, not a GitHub block. Never push directly to `main` without the Founder's explicit consent.

## Cross-agent review

The reviewer is a different agent from the author.

| Author | Reviewer | How |
|---|---|---|
| Codex (Orca worker) | Claude (coordinator) | the `code-review` skill on the PR diff |
| Claude | Codex as an Orca worker | `orca orchestration worker-start --agent codex --worktree current` with the PR number; Codex reads `gh pr diff <n>` or `git diff main...<branch>` |

Scope: correctness, [change-safety.md](change-safety.md), the dependency rules of [decision 0001](../decisions/0001-architecture-style.md), tests proportional to risk, unnecessary complexity and dependencies. Out of scope: style already enforced by `dart format` and the linter.

Result format (posted as a PR comment headed `Review: <agent> / <model>`):

```markdown
Verdict: approve | changes-requested
Findings:
- [blocker|major|minor] path:line — problem; failure scenario; proposal
Tests checked: …
```

`blocker` and `major` go back to the author as a fix on the same branch, then the reviewer re-reviews. A `minor` may become a follow-up issue.

## Push

Standing consent (Founder, 2026-10-01): agents push task branches and open PRs. Only the coordinator merges to `main` or pushes to it, after the conditions above.
