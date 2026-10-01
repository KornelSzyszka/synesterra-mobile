# Architecture tests

`test/architecture/architecture_scan.dart` scans Dart `import`, `export`, `part`, and `part of` directives under the app and core `lib/` trees. It resolves relative and workspace package URIs to repository paths, then checks ADR 0001 rules R1–R9. `flutter test` runs the repository check and one deliberately broken fixture per rule. Each violation includes its rule, source file, and directive.

To add or amend a rule, update [ADR 0001](../decisions/0001-architecture-style.md) first. Then change `scanArchitecture`, add a minimal `fixtures/rN/` tree that violates the new rule, and run `flutter test test/architecture/`. Keep the real-repository check green.

The core is also tested with `dart test` from `packages/synesterra_core/` in CI. The pure Dart package has `test` as its only dev dependency; its runtime has no third-party dependencies. In a pub workspace, `dart test` only compiles imports reached by its tests, so R1's scan is the required guard against an unused Flutter import.

The scanner checks directives, not instantiated classes, runtime behavior, or generated code. Its lightweight regular expression expects ordinary Dart directives ending in semicolons; unusual comment layouts and URI interpolation need review. Review must also check that visualization never commands transport, widgets hold no business logic, value objects validate on construction, planned events carry a generation, and no factory hides concrete construction behind an abstract import.
