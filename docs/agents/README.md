# Agent collaboration

How AI coding agents (Claude, Codex) and the Founder work in this repository. Everything here is tracked in git, so every Orca worktree and agent sees the same rules. Start with [AGENTS.md](../../AGENTS.md).

| Document | Covers |
|---|---|
| [task-lifecycle.md](task-lifecycle.md) | creating, executing and finishing a task (GitHub issue → branch → PR) |
| [roles-and-routing.md](roles-and-routing.md) | roles, the Claude/Codex split, working through Orca |
| [review-and-merge.md](review-and-merge.md) | CI, cross-agent review, merge rules, push consent |
| [change-safety.md](change-safety.md) | invariants, change boundaries, risky areas |
| [founder-collaboration.md](founder-collaboration.md) | Founder involvement, decision gates, the decision package |
| [model-routing.md](model-routing.md) | model class per task, models per class, escalation, cost, outcome logging |

## Conventions

- Tasks are [GitHub issues](https://github.com/KornelSzyszka/synesterra-mobile/issues) created from the **Task** form; Linear is not used.
- Domain, kind, risk, size and horizon are labels (`domain:*`, `kind:*`, `risk:*`, `size:*`, `horizon:*`). `founder-review` and `decision-gate` mark Founder involvement.
- Task ID = owning-area prefix + zero-padded issue number: `DOM-007` is issue #7. Prefixes: `DOM`, `AUD`, `UX`, `MOB`, `QA`, `REL`, `AGT`.
- One task = one branch (`<prefix>-<nnn>-slug`, e.g. `dom-007-session-model`) = one commit scope = one pull request to `main` whose body contains `Closes #<n>`. In Orca, link the worktree with `orca worktree create --issue <n>`.
- Merging to `main` happens only after green CI and a cross-agent review (author and reviewer are different agents).
- Language: conversation with the Founder is in Polish; code, identifiers, documentation, commit messages, issues and PRs are in English.
- Static analysis, emulators and unit tests are not evidence of audio quality or of behaviour on a physical phone.
