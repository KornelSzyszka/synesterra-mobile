# Decisions

Larger decisions get a numbered record (`NNNN-title.md`: context, decision, alternatives, consequences). Smaller ones are a row in the log below. A changed decision updates this log, the dependent issues and, if public behaviour changes, the README or docs.

## Records

| No. | Decision | Status |
|---|---|---|
| [0001](0001-architecture-style.md) | Architecture style: hybrid DDD-lite | accepted 2026-10-01 |
| [0002](0002-audio-backend.md) | Native audio backend and scheduling hand-off: engine-agnostic ports and scheduler; discovery spike with `flutter_soloud` (option C), then our own C++ engine (A) or `flutter_soloud` (B) | accepted 2026-10-02: option C (`architecture` gate, #16); PR #24 merged; revision 5 addresses review #71 |

## Log

| Date | Decision | Why | Consequence |
|---|---|---|---|
| 2026-09-30 | Separate `synesterra-mobile` repository in Flutter/Dart | Founder (web PLR-059) | No shared TS/Web Audio runtime; session contract and audio QA verified separately |
| 2026-09-17 | Session model direction: `SessionDocument v2` | Founder accepted web PLR-010 | The mobile core implements that contract; migration and planner come as separate steps |
| — | The audio path is local and independent of any backend | The network must not drive the clock | A future API may only sync session documents |
| 2026-10-01 | Placeholder application ID `com.example.synesterra` | Founder: final ID later | Change only through a `REL` task with the `release` gate |
| 2026-10-01 | GitHub Issues instead of Linear; task ID = area prefix + issue number (`DOM-007` = #7); labels for domain, kind, risk, size, horizon | Founder: Orca links worktrees to issues; PRs, CI and reviews are on GitHub; web is paused | Old task IDs renumbered (#7) |
| 2026-10-01 | CI on GitHub Actions; cross-agent review (Claude/Codex); only the coordinator merges | Founder; GitHub Free has no branch protection for private repos | Rules in `docs/agents/review-and-merge.md`, enforced by the coordinator; iOS CI on demand (macOS cost) |
| 2026-10-01 | Standing consent to push task branches and open PRs | Founder | Merging and pushing to `main` remain coordinator-only |
| 2026-10-01 | Hybrid DDD-lite architecture ([0001](0001-architecture-style.md)) | Founder, `architecture` gate (#9, PR #11) | Core package `packages/synesterra_core`, MVVM feature-first app, ports, generation rule; architecture tests enforce R1–R9 (#10) |
| 2026-10-02 | All agent rules and context live in the repository; no private, untracked agent workspace | Founder (#13): every Orca worktree and agent must see the same rules | `AGENTS.md`, `CLAUDE.md` and `docs/agents/` are tracked; task briefs live in issues |
| 2026-10-02 | Accepted: native audio backend and scheduling hand-off ([0002](0002-audio-backend.md)), option C (discovery spike with `flutter_soloud`), foreground-only 1.0, `minSdk` 27 unless the test phone is older, iOS device stages blocked | #16; the Founder accepted it on 2026-10-02 (`architecture` gate) | PR #24 merged; the discovery spike uses go/no-go gates G1–G10, Android first |
