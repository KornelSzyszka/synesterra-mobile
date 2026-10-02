# Audio scheduler (AUD-042, C0)

The core exports `AudioClock`, `VoiceSink`, `AudioTime`, `TempoMap`, and voice
events. `AudioTime` is an integer number of microseconds on the engine timeline.
Beat positions are integer ticks, with 960 ticks per quarter note. `TempoMap` is
the only beat/audio-time conversion. This C0 map has one constant BPM and one
anchor; the DOM planner and runtime state will replace or extend these C0 types.

`PlaybackScheduler` lives in `lib/data/audio/`. Its state and event source are
injected. Until the DOM planner exists, tests load precomputed 3:2 and 5:4
events from `test/data/audio/fixtures/polyrhythms.json`. The fixture is test
data and is not a production music planner.

Each 25 ms timer tick only wakes the scheduler. It reads `AudioClock.now()`,
plans the half-open beat window up to 200 ms after `renderTime`, and passes
audio timestamps to `VoiceSink`. A state change calls `replan()` synchronously.
The scheduler applies a new generation cutoff before checking transport or
engine state, then starts again from `renderTime + minLead`. After a clock jump,
missed beats are skipped. The native sink remains responsible for generation
filtering, late and overflow diagnostics, one-shot tails, drone adoption and
release, and the route-dependent audible output tail, as specified in ADR 0002.

This module has unit evidence only. It has no engine or device audio output.
