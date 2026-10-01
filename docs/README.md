# Documentation

All documentation is in English. Diagrams use Mermaid (rendered by GitHub, no external service), so they stay reviewable as text in pull requests.

| Document | Purpose |
|---|---|
| [architecture.md](architecture.md) | Module layout, dependency direction, which parts exist or are planned |
| [agents/](agents/README.md) | Agent collaboration rules and model routing |

## Where new material goes

- **Patterns** (recurring solutions, naming, error handling, test structure): `docs/patterns/<topic>.md`. Record the problem, the chosen pattern, a short example from the code, and when not to use it.
- **Code documentation** (how a module works, contracts, invariants, timing assumptions): `docs/modules/<module>.md`, next to a `///` doc comment on the public API. Keep prose about why; the code says what.
- **Charts and diagrams** (flows, sequences, state machines, data models): Mermaid blocks inside the relevant document. Mark planned parts as planned, so a diagram never claims code that does not exist.
- **Decisions**: `docs/decisions/NNNN-title.md`, short: context, decision, consequences.
- **Device and QA protocols**: `docs/QA.md`. Emulator results are never recorded as device evidence.

Create a directory when its first document is added, not before.
