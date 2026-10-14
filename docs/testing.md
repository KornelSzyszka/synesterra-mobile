# Testing and evidence

## Levels of evidence

| Level | Command / environment | Proves | Does not prove |
|---|---|---|---|
| `static` | `flutter analyze`, `dart format`, architecture tests | types, lint, dependency rules | behaviour |
| `unit` | `dart test` in `packages/synesterra_core`, `flutter test test/<path>` | core logic, planner, migration | audio timing |
| `widget` | `flutter test` | UI in isolation | platform, audio |
| `emulator` | `flutter run -d emulator-*` (see [Emulators](#emulators) section), Orca `orca-emulator-android` skill | UI flow, Android integration | latency, jitter, Bluetooth |
| `device` | physical phone + `docs/QA.md` protocol | timing, lifecycle, listening | — |

Report the highest level reached (it is also the `evidence` field of the model outcome log). Never present an emulator result as device evidence.

## Minimum set per change

- Documentation or agent rules only: link and consistency check; app tests are not needed (CI is skipped for documentation-only PRs).
- Dart code: `flutter analyze` and the narrowest test (`dart test` in the core, `flutter test <path>` in the app). Run the full suite when shared code changed.
- Native code (gradle, Kotlin, Swift) and any task that touches the build: also `flutter build apk --debug` locally, and the on-demand CI job `gh workflow run CI -f apk=true --ref <branch>` (the APK build no longer runs on every PR). iOS needs macOS — use the manual CI job (`gh workflow run CI -f ios=true --ref <branch>`).
- Bug fix: a regression test that fails before the fix and passes after, when feasible.

## Host environment (2026-10-02)

Windows 11, Flutter 3.47.6, Android SDK 36.1, Android Studio. No Chrome or Visual Studio (web and desktop targets are not used). iOS cannot be built locally. Android builds use JDK 17 or 21; JDK 25 is unsupported by the Android Gradle Plugin ([Flutter issue #187223](https://github.com/flutter/flutter/issues/187223)). Select the JDK with `flutter config --jdk-dir=<path>`.

## Emulators

Agents never use the Founder's personal emulator. You must use the dedicated agent AVD.

### Agent emulator

AVD: `Synesterra_Agent_API_36` on port 5560 (serial `emulator-5560`).

Start with:
```powershell
"$LOCALAPPDATA/Android/Sdk/emulator/emulator.exe" -avd Synesterra_Agent_API_36 -port 5560 -no-snapshot-save -no-boot-anim
```

Check if the emulator is ready:
```powershell
& "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" -s emulator-5560 shell getprop sys.boot_completed
```
Wait until it returns `1`.

Run the app:
```powershell
flutter run -d emulator-5560
```

Rules:
- Never uninstall, clear, launch, or tap other apps on this emulator.
- Stop the Synesterra app after taking screenshots (don't leave it running).
- Screenshots go in the PR description, not the repository.

### Founder's emulator (off-limits)

AVD: `Medium_Phone_API_36.1` on port 5554 (serial `emulator-5554`). This is the Founder's personal emulator and may hold unrelated apps. Agents must never use it.

### Known AVD setup issues

If the emulator won't boot or runs very slowly, check the config file at `~/.android/avd/Synesterra_Agent_API_36.avd/config.ini`:

- `hw.ramSize=2G`: This is interpreted as 256 MB, which is too small. Change it to `hw.ramSize=2048`.
- `hw.gpu.enabled=no`: Disable GPU acceleration causes slowdowns. Change it to `hw.gpu.enabled=yes`.
