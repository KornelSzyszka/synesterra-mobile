# Randomizer

Code: `packages/synesterra_core/lib/src/randomizer/` (pure Dart, R1 of [decision 0001](../decisions/0001-architecture-style.md)), tests in `packages/synesterra_core/test/randomizer_test.dart`. UI: the dice in the Loop panel (`lib/features/editor/loop_panel.dart`, `LoopEditorViewModel.randomize`). Issue #125. The rules below are coordinator defaults; the Founder tunes them by ear (`founder-review`).

`randomizer` is its own core context. [ADR 0001](../decisions/0001-architecture-style.md) R2 was amended minimally for it (coordinator confirmed, 2026-10-14): it may use `rhythm`, `harmony`, `sound`, `session` and `arrangement`, and no context depends on it.

## Public API

```dart
SessionDocument randomLoopDocument({
  required int seed,                       // uint32
  List<String> instrumentIds = const [],   // empty: the factory instruments
  String title = '',
});

Arrangement? randomArrangement({
  required int seed,                       // uint32
  required List<String> loopIds,           // empty: null, no arrangement
  required String id,
  required String name,
});

class SeededRandom implements Random { SeededRandom(int seed); int nextUint32(); ... }
const maxRandomSeed = 0xffffffff;
void checkRandomSeed(int seed, [String name]);
// Ranges: randomLoopCycleBeats, randomLoopMinTempo/MaxTempo,
// randomLoopMinRoot/MaxRoot, randomArrangementMinSections/MaxSections/MaxRepeats.
```

Both generators build their result through the core constructors (`SessionDocument`, `Arrangement`), so the output is valid by construction; the tests also send every result through the real parsers. Invalid input (a seed outside uint32, an id that breaks `[A-Za-z0-9-]{1,64}`, an arrangement name `Arrangement` rejects) throws `ArgumentError`. An empty loop list is not an error: `randomArrangement` returns `null`.

## Determinism

The same seed and arguments give the same result on every platform and SDK. `dart:math`'s seeded `Random` and `List.shuffle` do not promise their algorithms, so the core has its own:

- `SeededRandom` is **mulberry32**: a 32-bit state, advanced by `0x6D2B79F5` per output and mixed by two multiply-xorshift rounds. Its first outputs for seeds 0, 1 and `0xffffffff` are pinned against the JavaScript reference. Multiplication is split into 16-bit halves (no 64-bit overflow, web-safe).
- `nextInt(n)` rejects outputs at or above the largest multiple of `n` below 2^32 (no bias); `nextDouble` uses 53 bits from two outputs; a weighted choice draws one `nextInt(total weight)` and walks the options in order; a shuffle is Fisher-Yates from the last index down.

Changing any rule below, or the order in which it draws numbers, changes what a stored seed produces. That is allowed (seeds are not stored as a contract), but say so in the PR.

## Loop rules (`randomLoopDocument`)

Draw order: layer count, cycle, step counts, patterns (layer by layer), pitches, instrument order, tempo.

| What | Rule |
|---|---|
| Layers | 2, 3 or 4 (weights 35 / 40 / 25), ids `layer-1`… |
| Cycle | one of 2, 3, 4, 6, 8 beats; every layer lasts exactly one cycle (a prototype-v0 loop the Loop panel can edit) |
| Step counts | all different. The first two are a polyrhythm pair `k·p : k·q` from 3:2 (weight 5), 4:3 (4), 5:4 (3), 7:4 (2), 5:3 (2), 5:2 (1), 7:3 (1), shuffled between the two layers. `k` is chosen, when possible, so the slower layer steps at most every 2 beats. A third or fourth layer takes a count related to an earlier one by 2:1, 3:2, 4:3, 5:4, 7:4 or 5:3 (either way), or the beat or half beat of the cycle |
| Speed | at most 16 steps and at most 4 steps per beat, so the step spacing is never below 1/4 beat (the contract's floor is 1/16) |
| Hits | 30-70 % of a layer's steps are on (integer bounds `ceil(0.3 n)`..`floor(0.7 n)`); the first step is always on, where the layers meet; other steps on a whole beat are twice as likely as steps between beats |
| Accents | only the first step, 60 % of layers; velocity 1 accented, 0.9 not; other hits 0.60-0.85 |
| Pitches | a major or minor pentatonic (50/50) on a root drawn from MIDI 36..72, over the octave below and the octave of the root, never below C2 (36; lower barely sounds on a phone). The slowest layer takes the root or the root an octave down; faster layers take distinct notes above it, the faster the higher |
| Instruments | the given ids (deduplicated) or the three factory instruments, shuffled, one per layer, repeated only when there are fewer instruments than layers |
| Tempo | whole BPM in 70..130, capped at 110 when the fastest layer plays more than 3 steps a beat |
| Mix | gain 0.85 / 0.75 / 0.7 for 2 / 3 / 4 layers on the slowest layer, down to 0.15 less on the fastest; pan 0, not muted, no solo, swing off, phase 0 |
| Document | scene B equals scene A (as the Loop panel writes), master gain 0.8, drone off, click off, circle view, `randomSeed` = the seed |

## Arrangement rules (`randomArrangement`)

2..6 sections (weights 2 / 3 / 3 / 2 / 1), each with 1..4 repeats (weights 2 / 4 / 1 / 3, so 2 and 4 cycles, phrase lengths, are favoured). Duplicate loop ids count once. A section never takes the loop of the section before it, unless there is only one loop; with three or more sections the last one returns to the first loop 40 % of the time (when that is not a repeat).

## Loop panel

A round dice (`RoundIconButton`, label *Randomize loop*) sits under the loop's name. A roll replaces the loop being edited as an unsaved change: the id and the name stay, the status says *Changed, not saved yet*, and nothing starts playing. Each roll asks the generator with the next seed (the first is random per panel, wrapping in uint32). Instruments come from the factory and the user's library. *Undo randomize* appears after a roll and restores the exact document from just before the last roll (edits made after that roll go with it). Every roll keeps its own snapshot, so repeated undo steps back to the loop as it was before the first roll, unsaved edits included: a roll never destroys work. Saving or opening another loop clears the snapshots. The roll and its undo go through the same edit path as any change, so while the loop plays they restart it from the cycle start under a new generation (playback's generation rule). The tap flash is the shared `TapGlitch` and its `FlashGate`.

## Not here

The dice in the Arrangement panel (a later task, after the arrangement visualization lands); rolling only part of a loop; a seed field in the UI; machine-learning generators.
