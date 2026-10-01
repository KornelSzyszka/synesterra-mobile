# Agent collaboration

How AI coding agents (Claude, Codex) work in this repository. Private working notes live outside version control; this directory holds the rules that apply to every contributor.

- [Model routing](model-routing.md): which model class a task needs, escalation, cost reference.

## Conventions

- Task IDs are `<PREFIX>-###`; the prefix names the owning area (`DOM`, `AUD`, `UX`, `MOB`, `QA`, `REL`, `AGT`).
- One task = one branch (`<prefix>-###-slug`) = one commit scope = one pull request to `main`.
- Merging to `main` happens only after green CI and a cross-agent review (author and reviewer are different agents).
- Language: conversation with the product owner is in Polish; code, identifiers, documentation, commit messages and PRs are in English.
- Static analysis, emulators and unit tests are not evidence of audio quality or of behaviour on a physical phone.
