# Roles, agent routing and Orca

## Roles

A role is responsibility for an outcome, not a model. Each task has exactly one owning role.

| Role | Prefix | Owns | Does not |
|---|---|---|---|
| `coordinator` | `AGT` | intake, splitting work into issues, choosing agents, integration, acceptance and merge, agent rules, Orca | implement large changes in the same files as a running worker |
| `rhythm-domain` | `DOM` | the pure Dart core: session, rhythm, harmony, validation, serialization, unit tests | import Flutter, plugins or I/O |
| `audio-platform` | `AUD` | transport maths, planner, ports, audio bridge, platform channels, audio lifecycle | change musical semantics without the `musical` gate |
| `mobile-ui` | `UX` | screens, widgets, view models, visualization, accessibility | let visualization drive transport |
| `mobile-platform` | `MOB` | bootstrap, project structure, persistence, gradle/xcode, dependencies, architecture tests | change the application ID or signing |
| `qa-release` | `QA`, `REL` | integration tests, device protocols, release gates | publish without the `release` gate |

The Founder (Technical Product Owner & Musical Director) joins as described in [founder-collaboration.md](founder-collaboration.md).

## Mercury roles

Two layers. A **domain role** (above) owns the outcome of a task and has a prefix. A **Mercury role** runs a recurring process across domains: it carries messages and routine work between the coordinator, workers, GitHub and Orca. A Mercury role has no task prefix, makes no decisions and follows a checklist. It is a role, not a separate agent: Codex or Claude performs it at the class in [model-routing.md](model-routing.md).

| Mercury role | Does | Min. class | Never |
|---|---|---|---|
| `mercury-dispatch` | From the issue and its Agent brief: creates the worktree and branch `<prefix>-<nnn>-slug`, starts the worker with `--model` and `--effort` for the brief's class, waits for `worker_done`, checks that the PR exists | `S` | judge the quality of a diff; start two writers on the same files |
| `mercury-review` | Cross-agent review of a PR by an agent that did not write it ([review-and-merge.md](review-and-merge.md)) | `M`; `L` for `risk-audio` | fix the code under review; approve its own work |
| `mercury-steward` | Housekeeping: lists worktrees and branches of merged or closed PRs, workers to release, PR and CI status, and what waits for a Founder gate | `S` | delete anything without a list the coordinator or Founder approved |

Optional, not active until they save real time: `mercury-ci` (triage of a red CI: environment or code, smallest fix or a report) and `mercury-scribe` (`logs/outcomes/`, hand-off notes, recording an accepted decision).

Hard limits for every Mercury role:

- Never merges, never pushes to `main`, never passes a decision gate. Those stay with the coordinator and the Founder.
- Pushes only the task branch it was started for.
- Reports like any worker, in at most five points ([model-routing.md](model-routing.md#worker-reply)); the full result goes into the PR or a comment.
- Anything outside its checklist goes back to the coordinator, not to a guess.

### GitHub identity

Start with one GitHub App, `synesterra-mercury[bot]`. The role, agent and model go into the first line of the comment, for example `Mercury Review · Codex / gpt-5.6-luna`, followed by the review format from [review-and-merge.md](review-and-merge.md). If separate faces turn out to help, split it into `mercury-review[bot]`, `mercury-dispatch[bot]` and so on; the comment convention stays the same. The App's private key stays outside the repository. Registering the App is a Founder action in GitHub settings. An approval from the App is a signal for the coordinator, not a GitHub branch rule: the repository has no branch protection on the Free plan.

## Claude or Codex

This is the default split. The coordinator may override it and records the reason in the issue's Agent brief.

| Work | Preferred agent | Why |
|---|---|---|
| Coordination, issue writing, synthesis, architecture decisions, review | Claude | holds the conversation with the Founder; Orca orchestration skills |
| Scoped implementation with a clear brief and tests (`DOM`, `MOB`, `UX`) | Codex | efficient worker in its own worktree |
| Native audio code (Kotlin/Swift/C++), timing | Claude or Codex at class `L` | high failure cost; the other agent reviews |
| Reviewing someone else's change | the agent that did not write it ([review-and-merge.md](review-and-merge.md)) | independent view |

Never run two writers on the same files or branch without an explicit integration plan.

## Working through Orca

Orca coordinates processes; it is not evidence of completion. Evidence is the diff, test output and the PR.

- **Unsupervised hand-off** (transfer of ownership): skill `orca-cli`, separate worktree, no Run/Task/Dispatch.
- **Supervised work** (the coordinator waits for results, DAGs, gates): skill `orchestration`. Use one Run per wave of work, with the parent issue as the Run objective.
- The worker spec names the issue number and says "read `AGENTS.md` and `gh issue view <n>`". The brief lives in the issue, not in the prompt.
- Parallel implementation: give each worker its own worktree (`orca worktree create --issue <n>` or `worker-start --worktree new-top-level`), on branch `<prefix>-<nnn>-slug`. All rules are tracked in git, so every worktree has them.
- Read-only tasks and short verifications may run in `--worktree current`.
- Pass `--model` and `--effort` that match the issue's minimum class ([model-routing.md](model-routing.md)).
- The worker ends with `worker_done`, an explicit `--outcome succeeded|failed` and the PR number. The coordinator checks the diff, CI and review before merging.
- Workers push only their task branch and open a PR. They never merge and never push to `main`.

## Escalation to the Founder

Escalate only for an active gate or contradictory requirements. The decision package format is in [founder-collaboration.md](founder-collaboration.md).
