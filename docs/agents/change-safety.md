# Change safety

## Invariants

These hold from the first line of implementation.

- The audio path is local. Network, backend and UI never drive the musical clock or scheduler.
- The time source is the platform audio clock, not `Timer`, `Future.delayed` or UI frames. Dart timers may only wake the scheduler.
- Planning windows are half-open (`from <= event < to`), so window boundaries never double a hit.
- Pause keeps the cycle position, Stop resets it, a tempo change keeps the phase. After a stall, late hits are skipped, not replayed as a burst.
- Playback never starts automatically when the app launches.
- The planner works only in absolute beats (`[fromBeat, toBeat)`). `TempoMap` is the only beat ↔ audio-time conversion. `VoiceSink` receives only audio-clock timestamps.
- Generation rule: pause, stop, a tempo or scene change, an edit while playing and an audio interruption increment `generation`. Events from an older generation must never sound.
- `PlaybackRepository` owns `RuntimePerformanceState`. View models only read it and send commands.
- Visualization reads the transport position and never drives transport.
- The session model is serializable, versioned and validated on every read. Target contract: `SessionDocument v2` (see *External references*).
- Dependency rules R1–R9 of [decision 0001](../decisions/0001-architecture-style.md) hold. Changing a rule means changing that decision first.

## Change boundaries

- Do not port the TypeScript/Web Audio runtime from `synesterra-web`. The web lab is a reference for behaviour, not code to share.
- Do not add aggregates, domain events, CQRS, a state-management/DI package or code generation without amending decision 0001 (*Not now*).
- A new `pub.dev` dependency or native audio library needs a justification in the PR. Choosing the audio backend (e.g. Oboe/AAudio, AVAudioEngine) goes through the `architecture` gate.
- The application ID `com.example.synesterra` is a placeholder. Only a `REL` task with the `release` gate may change it.
- A session schema change needs an explicit version and migration decision.
- Never commit keystores, `key.properties`, provisioning files or secrets.

## Risky areas

- Audio lifecycle: interruptions, screen lock, Bluetooth and background behaviour differ between Android and iOS. Only a physical device is evidence here.
- Platform channels: a native-side failure is invisible to `flutter test`.

## External references

The web laboratory's specifications live in `synesterra-web` and are not part of this repository:

- **`SessionDocument v2` contract (web PLR-010):** `SessionDocument`, `SessionProject`, `RuntimePerformanceState`, validation limits, v1 → v2 migration, planner invariants.
- **Rhythm core gap analysis (web PLR-004):** the core boundary `SessionDocument → SessionProject + RuntimePerformanceState → EventPlanner → platform scheduler → VoiceSink`.

The first `DOM` task that needs the contract copies the relevant parts into `docs/modules/` of this repository. After that, agents in any worktree read it from here.
