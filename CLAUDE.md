@AGENTS.md

## Claude Code

- Multi-agent work goes through Orca (skills `orchestration` and `orca-cli`), not built-in subagents, when it should leave a trace in Orca.
- Claude usually coordinates and reviews Codex's work. Split and review flow: [docs/agents/roles-and-routing.md](docs/agents/roles-and-routing.md), [docs/agents/review-and-merge.md](docs/agents/review-and-merge.md).
