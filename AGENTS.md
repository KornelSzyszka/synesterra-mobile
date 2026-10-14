# Synesterra Mobile — agent instructions

Standalone Flutter/Dart app for Android and iOS. The TypeScript web laboratory (`synesterra-web`) is a behaviour reference only. It is not a runtime dependency, and its work is paused.

Everything an agent needs is in this repository or in GitHub Issues/PRs. Do not create private workspaces next to the code.

## Working agreement

- Talk to the Founder in Polish. Write code, identifiers, documentation, commit messages, issues and PRs in English.
- A goal, its constraints and observable acceptance criteria are enough to start. Take everything else from the repository.
- Carry an assigned task through to verification while respecting its decision gates. Investigation alone does not authorize code changes.
- Tie important criteria to evidence. For a bug fix, show the regression test going red, then green, when feasible.
- A repeated failure needs a new hypothesis, not an identical retry. Check running emulators and processes before starting new ones.
- A runnable hand-off states the command, the device or emulator, the UI steps and the expected result. Keep checks that ran separate from checks that did not, and both separate from listening on a device.
- Static analysis, `flutter test` and emulators are not evidence of audio quality or of behaviour on a physical phone.

## Read on demand (progressive disclosure)

1. This file and the task's GitHub issue (`gh issue view <n>`), including its **Agent brief**.
2. Only the files listed in the brief's context.
3. [docs/agents/change-safety.md](docs/agents/change-safety.md) before changing code.
4. [docs/testing.md](docs/testing.md) before verifying.
5. [docs/agents/roles-and-routing.md](docs/agents/roles-and-routing.md) when delegating, choosing an agent or working through Orca.
6. [docs/agents/review-and-merge.md](docs/agents/review-and-merge.md) before opening a PR, reviewing or merging.
7. [docs/agents/founder-collaboration.md](docs/agents/founder-collaboration.md) only for a `decision-gate` or `founder-review` issue.
8. [docs/agents/model-routing.md](docs/agents/model-routing.md) when picking a model or budget.
9. [docs/decisions/](docs/decisions/README.md) when the task touches an earlier decision.

## Code map

Layout and dependency rules R1–R9 come from the accepted [decision 0001](docs/decisions/0001-architecture-style.md). Directories appear with the first task that needs them.

| Area | Path | Prefix | Role |
|---|---|---|---|
| Rhythm, harmony and session contexts, value objects, `SessionDocument` migration and validation (pure Dart) | `packages/synesterra_core/lib/src/{rhythm,harmony,session}/` | `DOM` | rhythm-domain |
| Sound context: instrument model, renderer and EQ/envelope maths (pure Dart) | `packages/synesterra_core/lib/src/sound/` | `DOM` | rhythm-domain |
| `TempoMap`, beat windows, `EventPlanner`, `RuntimePerformanceState`, ports | `packages/synesterra_core/lib/src/{playback,ports}/` | `AUD` | audio-platform |
| Audio bridge and `PlaybackScheduler`, native engine, platform channels | `lib/data/audio/`, `android/`, `ios/` | `AUD` | audio-platform |
| Views and view models per feature, shared widgets, visualization | `lib/features/<feature>/`, `lib/shared/` | `UX` | mobile-ui |
| Composition root, repositories (abstract + `impl/`), stateless services, build, workspace, architecture tests | `lib/main.dart`, `lib/app/`, `lib/data/repositories/`, `lib/data/services/`, `pubspec.yaml`, gradle/xcode, `test/architecture/` | `MOB` | mobile-platform |
| Integration tests, device protocols | `integration_test/`, `docs/QA.md` | `QA` | qa-release |
| Signing, application ID, stores | release configuration | `REL` | qa-release + Founder |
| Agent rules, Orca, issues, CI | `AGENTS.md`, `CLAUDE.md`, `docs/agents/`, `.github/` | `AGT` | coordinator |

Dependencies in short: `features → repositories (abstract) → core`; only `app/` imports `repositories/impl/`; `impl/` uses `services/` and `audio/`; `data/` never imports the UI; the core imports no Flutter, plugins or I/O; no `part` files.

## Tasks

- Every task is a GitHub issue created from the **Task** form (`.github/ISSUE_TEMPLATE/task.yml`). Linear is not used.
- Task ID = owning-area prefix + zero-padded issue number: `DOM-007` is #7.
- Labels: `domain:*` (one or more), `kind:*`, `risk:*`, `size:*`, `horizon:*`, `founder-review`, `decision-gate`.
- The issue's **Agent brief** holds what an agent needs beyond the goal: context files, write scope, minimum model class, out of scope.
- Status: an open issue without a PR is backlog/ready; an open PR is in progress or review; a merged PR with `Closes #n` is done. `done` is decided by the coordinator after review.
- Lifecycle: [docs/agents/task-lifecycle.md](docs/agents/task-lifecycle.md).

## Commands

```powershell
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter run -d <device-id>          # flutter devices
flutter build apk --debug
dart run tool/model_log.dart check  # model outcome log
```

CI: [.github/workflows/ci.yml](.github/workflows/ci.yml). Linux (model log, format, analyze, tests) runs on every PR that changes more than documentation (not on a push to `main`, to save Actions minutes); the debug APK and iOS builds run on demand with `gh workflow run CI -f apk=true --ref <branch>` and `-f ios=true`. Push once per review round: every push to a PR costs a full run.

## Git

- One task = one branch `<prefix>-<nnn>-slug` = one PR to `main` with `Closes #<n>`.
- Agents may push task branches and open PRs (standing consent, Founder, 2026-10-01).
- Only the coordinator merges to `main`, after green CI and a cross-agent review. Squash merge and delete the branch.
- Never publish to stores. Never change the application ID without a `REL` task and the `release` gate.
- Never commit secrets, keystores, `key.properties` or provisioning files. New `pub.dev` dependencies need a justification in the PR.
