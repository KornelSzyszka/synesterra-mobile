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
