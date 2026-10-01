# Testing and evidence

## Levels of evidence

| Level | Command / environment | Proves | Does not prove |
|---|---|---|---|
| `static` | `flutter analyze`, `dart format`, architecture tests | types, lint, dependency rules | behaviour |
| `unit` | `dart test` in `packages/synesterra_core`, `flutter test test/<path>` | core logic, planner, migration | audio timing |
| `widget` | `flutter test` | UI in isolation | platform, audio |
| `emulator` | `flutter run -d emulator-*`, Orca `orca-emulator-android` skill | UI flow, Android integration | latency, jitter, Bluetooth |
| `device` | physical phone + `docs/QA.md` protocol | timing, lifecycle, listening | — |

Report the highest level reached (it is also the `evidence` field of the model outcome log). Never present an emulator result as device evidence.

## Minimum set per change

- Documentation or agent rules only: link and consistency check; app tests are not needed (CI still runs).
- Dart code: `flutter analyze` and the narrowest test (`dart test` in the core, `flutter test <path>` in the app). Run the full suite when shared code changed.
- Native code (gradle, Kotlin, Swift): also `flutter build apk --debug`. iOS needs macOS — use the manual CI job (`gh workflow run CI -f ios=true --ref <branch>`).
- Bug fix: a regression test that fails before the fix and passes after, when feasible.

## Host environment (2026-10-01)

Windows 11, Flutter 3.35.7, Android SDK 36.1, Android Studio. No Chrome or Visual Studio (web and desktop targets are not used). iOS cannot be built locally.
