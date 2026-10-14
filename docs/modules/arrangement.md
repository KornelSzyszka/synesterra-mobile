# Arrangement

Code: `packages/synesterra_core/lib/src/arrangement/arrangement.dart`, tests in `packages/synesterra_core/test/arrangement_test.dart`. Scope: [prototype v0](../product/prototype-v0.md). Pure Dart, no Flutter, I/O or playback (R1 of [decision 0001](../decisions/0001-architecture-style.md)).

An `Arrangement` chains loops into a song: an ordered list of sections, each a loop id and a number of repeats. A repeat is one **cycle** of that loop (its `transport.practiceCycleBeats`). The model holds only ids; whether a loop exists is the data layer's question, and the sequencer receives the answer as a predicate.

## JSON v1

```text
Arrangement { version: 1, id: string, name: string,
  sections: [ { loopId: string, repeats: integer } ] }
```

| Field | Range |
|---|---|
| `id`, `loopId` | `[A-Za-z0-9-]`, 1..64 characters (same rule as instrument and layer ids) |
| `name` | 1..40 UTF-16 units, not blank, no control characters |
| `sections` | 1..16 entries, order is playing order |
| `repeats` | integer 1..32 |

`Arrangement.fromJson` is strict: unknown and missing fields, wrong types (including a non-integer `repeats`), an unsupported `version` and out-of-range values throw `FormatException` whose message starts with the JSON path, for example `$.sections[1].repeats: ...`. Callers reading files catch it and treat the file as corrupt. Constructors (`Arrangement`, `ArrangementSection`) validate the same ranges and throw `ArgumentError`; `toJson` always writes `version: 1`. Equality is by value, and section order matters.

## Sequencing

```dart
SequencePosition sequenceAt({
  required List<ArrangementSection> sections,
  required bool repeatAll,
  required int cycleIndex, // zero-based, whole cycles since the start
  bool Function(ArrangementSection section)? isSkipped,
})
```

The result is `SequenceAt(sectionIndex, cycleInSection)` or `SequenceDone`. Both are 0-based, and `sectionIndex` is an index into the **original** `sections` list, so a skipped section keeps its slot and a strip of sections highlights the right one.

- Section boundaries fall on cycle starts: cycle `k` is the first of the next section exactly when the previous sections' repeats add up to `k`. Tempo does not enter.
- `isSkipped` marks sections that cannot play (a missing loop). They take no cycles.
- Without `repeatAll` the sequence ends after the last playable cycle (`SequenceDone`). With it, the cycle index wraps modulo the playable total, however large it is.
- If every section is skipped the result is `SequenceDone`, also with `repeatAll`, so a caller never loops on an empty list. The UI uses this to disable Play and explain why.
- A negative `cycleIndex` throws `ArgumentError`.

## Not here

Storage is `ArrangementLibraryRepository` (`lib/data/repositories/`), playback is `PlaybackRepository.playSequence` ([playback](playback.md)), and the Editor's Arrangement panel is `lib/features/arrangement/`: it looks loops up in the loop library (factory loops included), marks and skips missing ones, passes the original section index to `playSequence`, and feeds `ArrangementRing` (see [loop views](loop-view.md#arrangement-ring-ux-123)) from the Editor's shared position. A loop deleted from the library while the panel plays replaces the running sequence with the sections that can still play (same original indexes), and the Editor asks before an unsaved arrangement is dropped on exit (`EditorShell.guardPanel`). "Repeat all" is panel state; the JSON v1 has no field for it. A random arrangement comes from `randomArrangement` ([randomizer](randomizer.md)).
