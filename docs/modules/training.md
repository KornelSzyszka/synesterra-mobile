# Training

`lib/features/training/` is the Training tab (issue #132). It replaced the Learn tab, whose lessons were removed (Founder, 2026-10-14). The Start screen's third entry opens `TrainingView`, a list of round cards: Tap in rhythm (this PR), then Note, Chord and Progression.

## Tap in rhythm

- **Core, pure**: `packages/synesterra_core/lib/src/training/tap_training.dart`. `TapPreset` (steady pulse, keep the pulse, 3:2, 4:3), `TapDifficulty` (tolerance 120 / 80 / 50 ms) and `scoreTaps`, which takes plain millisecond numbers. One count-in cycle is not scored, then 4 cycles are. A tap matches the nearest unmatched hit within half the shortest gap (at most 250 ms); otherwise it is an extra tap. Score 0..100: each hit earns `1 - |error| / tolerance`, summed and divided by the hits plus the extra taps.
- **Time source**: `TapTrainerModel` reads `PlaybackRepository.readPosition()` at the moment of a tap (cycle index and position become milliseconds with the preset's cycle length). There is no UI timer. The pad reacts to pointer-down.
- **Click**: `tapExerciseDocument` builds a `SessionDocument` with `simpleLoopDocument`: a wood click layer and a bell target layer. A scene needs 2..4 layers, so a preset that does not sound its target keeps the layer muted.
- **Latency offset**: a manual setting in 10 ms steps, +-250 ms, subtracted from every tap. It is held by `TrainingView` while the tab is open and is not persisted. It is not a measurement: audio and touch latency of a device are unknown (issue #43), and the position is the scheduler's audio clock reading, not what is heard.
- **Not claimed**: that the numbers match what a listener hears, or any timing accuracy on a device.

The end of an exercise is detected from the position listener (about every 25 ms): once the position is past the last cycle plus 250 ms the model stops the sound and shows the summary.
