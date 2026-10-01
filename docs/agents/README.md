# Agent collaboration

How AI coding agents (Claude, Codex) work in this repository. Private working notes live outside version control; this directory holds the rules that apply to every contributor.

- [Model routing](model-routing.md): which model class a task needs, escalation, cost reference.

## Conventions

- Tasks are [GitHub issues](https://github.com/KornelSzyszka/synesterra-mobile/issues); Linear is not used. Domain, kind, risk and horizon are labels (`domain:*`, `kind:*`, `risk:*`, `horizon:*`); `founder-review` and `decision-gate` mark Founder involvement.
- Task ID = owning-area prefix + zero-padded issue number: `DOM-007` is issue #7. Prefixes: `DOM`, `AUD`, `UX`, `MOB`, `QA`, `REL`, `AGT`.
- One task = one branch (`<prefix>-<nnn>-slug`, e.g. `dom-007-session-model`) = one commit scope = one pull request to `main` whose body contains `Closes #<n>`. In Orca, link the worktree with `orca worktree create --issue <n>`.
- Merging to `main` happens only after green CI and a cross-agent review (author and reviewer are different agents).
- Language: conversation with the product owner is in Polish; code, identifiers, documentation, commit messages and PRs are in English.
- Static analysis, emulators and unit tests are not evidence of audio quality or of behaviour on a physical phone.
