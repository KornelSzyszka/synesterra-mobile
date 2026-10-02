# Documentation

All documentation is in English. Diagrams use Mermaid (rendered by GitHub, no external service), so they stay reviewable as text in pull requests.

| Document | Purpose |
|---|---|
| [architecture.md](architecture.md) | Module layout, dependency direction, which parts exist or are planned |
| [decisions/](decisions/README.md) | Decision records and the decision log; [0001](decisions/0001-architecture-style.md): hybrid DDD-lite (accepted) |
| [agents/](agents/README.md) | Agent rules: task lifecycle, roles and routing, review and merge, change safety, Founder collaboration, model routing |
| [product/vision.md](product/vision.md) | Mobile product vision: domain model (Instrument, Loop, Arrangement), start screen, editing and visualization layers (draft) |
| [testing.md](testing.md) | Levels of evidence and the minimum checks per change |
| [QA.md](QA.md) | Physical-device audio QA protocol and result form |
| [../logs/](../logs/README.md) | Model outcome data, one JSON file per task, validated in CI |

## Where new material goes

- **Patterns** (recurring solutions, naming, error handling, test structure): `docs/patterns/<topic>.md`. Record the problem, the chosen pattern, a short example from the code, and when not to use it.
- **Code documentation** (how a module works, contracts, invariants, timing assumptions): `docs/modules/<module>.md`, next to a `///` doc comment on the public API. Keep prose about why; the code says what.
- **Charts and diagrams** (flows, sequences, state machines, data models): Mermaid blocks inside the relevant document. Mark planned parts as planned, so a diagram never claims code that does not exist.
- **Decisions**: `docs/decisions/NNNN-title.md`, short: context, decision, consequences.
- **Device and QA protocols**: `docs/QA.md`. Emulator results are never recorded as device evidence.

Create a directory when its first document is added, not before.
