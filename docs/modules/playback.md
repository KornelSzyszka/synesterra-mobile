# Playback repository (AUD-091)

Turns a `SessionDocument` (scene A), or a sequence of them, into sound through the ADR 0002 phase-1 path: `EventPlanner` → `PlaybackScheduler` → `SoloudVoiceSink` on `flutter_soloud`. Timing is **not measured on a device** (issue #43): nothing here is a claim about latency, jitter or what is heard.

## Code

| Part | Path | Role |
|---|---|---|
| `PlaybackRepository`, `PlaybackPosition`, `PlaybackSection`, `PlaybackStatus` | `lib/data/repositories/playback_repository.dart` | Public contract for view models |
| `EnginePlaybackRepository` | `lib/data/repositories/impl/engine_playback_repository.dart` | Commands, instrument resolution, buffers, voice cap, status and position |
| `NoopPlaybackRepository` | `lib/data/repositories/impl/noop_playback_repository.dart` | Silent stand-in for view tests and previews |
| `SequenceTransport` | `lib/data/audio/sequence_transport.dart` | Tempo map, generation, beat timeline of section runs; the scheduler's state and event source |
| `PlaybackEngine`, `SoloudPlaybackEngine` | `lib/data/audio/playback_engine.dart`, `soloud_playback_engine.dart` | The ports plus lifecycle, buffers and voice cap, built from the spike's `SoloudAudioClock` and `SoloudVoiceSink` |
| `flutterSoloudPlaybackEngine()` | `lib/data/audio/soloud_plugin_binding.dart` | The only file with plugin types |

Composition for the UI task: `EnginePlaybackRepository(engine: flutterSoloudPlaybackEngine(), instruments: <InstrumentLibraryRepository>)`. `lib/app/bootstrap.dart` composes one instance and `SynesterraApp` passes it to the Editor, where the Loop and Arrangement panels share it. Nothing starts the engine before the first Play.

## Public API

```dart
abstract interface class PlaybackRepository {
  ValueListenable<PlaybackStatus> get status;
  ValueListenable<PlaybackPosition> get position; // refreshed every ~25 ms
  PlaybackPosition readPosition();                // fresh clock reading
  Future<void> play(SessionDocument document, {Object? owner});
  Future<void> playSequence(List<PlaybackSection> sections,
                            {required bool repeatAll, Object? owner});
  Future<void> stop({Object? owner});            // with an owner: only its own playback
  void setTempo(int bpm);                         // 20..300, while playing
  void setLayerGain(String layerId, double gain); // 0..1
  Future<void> dispose();
}
PlaybackPosition {bool playing, double cyclePosition /* [0, 1) */, int cycleIndex,
                  int generation, int? sectionIndex}
PlaybackSection  {int originalIndex, SessionDocument document, int repeats /* 1..32 */}
PlaybackStatus   {PlaybackState state /* stopped | preparing | playing */,
                  PlaybackStopReason stopReason /* user | emptySequence | finished | error */,
                  int? bpm, Set<String> missingInstrumentIds, int? voiceLimit,
                  bool voiceLimitSaturated, String? error,
                  Object? owner /* who started the current playback */}
```

The data layer never imports UI code. The Loop panel task writes the adapter from `PlaybackPosition` to the visualizations' `PositionSource`; for smooth animation it calls `readPosition()` once per frame (the value comes from the audio clock, the frame only decides when to read it).

## Owner

Several panels share one repository. `play` and `playSequence` take an optional `owner` (the caller, usually its view model). `PlaybackStatus.owner` names the owner of the current playback, compared by identity, and is null when stopped. A command by another owner takes the transport over; a same-structure `play` keeps the sound and only changes the owner. `stop(owner: x)` does nothing unless `x` owns the current playback, so a panel that is edited, disposed or hidden never stops playback another panel started. A panel shows Stop only while `status.owner` is itself. `stop()` without an owner stops anything; the Editor uses it when the app is hidden.

## Changes while playing

| Change | Effect |
|---|---|
| `play(doc)` with the same scene A structure, other mix (gain, pan, mute, solo, master gain) | No new generation, no cancel. Applies to events planned from the next window; events already queued (up to the 200 ms horizon) keep their old gain. |
| `setLayerGain` | Same as a mix change. Reset by the next `play` with a different document. |
| `play(doc)` with only another tempo, or `setTempo` | New generation; the scheduler cancels pending events and replans. The phase is kept: the beat reached at `renderTime + minLead` continues at the new rate. The voice cap is recomputed. |
| `play(doc)` with another structure (steps, instrument, pitch, layers, cycle, seed), or any `play` during a sequence | New generation at once (silence while buffers are prepared), then a restart from the cycle start. |
| `stop()` | New generation, cancel, engine stopped, position reset to cycle 0. |

**Tempo in a sequence:** the whole sequence plays at the first section's tempo; the other sections' document tempos are not used. `setTempo` changes the tempo of the whole sequence.

**Volume:** a gain or mix change affects only events planned after the change. Hits already queued (up to the 200 ms horizon) keep their old gain; nothing is replanned or retuned.

**Hard cancel:** stop, a structural change and a tempo change stop the older generation's voices that are **already sounding** too, not only the pending ones (`SoloudVoiceSink(stopSoundingOnCancel: true)`). This deliberately departs from ADR 0002 `cancelFrom` rule 4 ("sounding one-shots finish their envelope") for session playback, because a long instrument tail of a stopped loop must not ring on; the spike keeps the ADR rule. The cut is an immediate SoLoud `stop`, which may click; that is unmeasured. A section hand-over never cancels, so section tails ring out.

Scene B is ignored (the prototype writes A and B together). The drone is not played. A document's tempo is rounded to whole BPM, because the core `TempoMap` takes an integer BPM.

## Sequences

`playSequence` lays the sections end to end on one beat timeline: section *k* lasts `repeats × practiceCycleBeats` (rounded up to a whole tick when the cycle is not a whole number of ticks). The whole sequence plays at the first section's tempo; `setTempo` changes it for the whole sequence (other sections' tempos are not used; see *Open points*). An empty list stops with `emptySequence`; without `repeatAll` the transport stops with `finished` once the end has been heard.

**Section boundary = generation handover.** A section switch increments the generation, but a cancel at that moment would cut the previous section's hits that are already queued up to 200 ms ahead. So `PlaybackScheduler` gained two optional snapshot fields: `planUntilBeat` stops planning at the section end, and `continuousSince` marks generations of one continuous run. When planning reaches the boundary (or the clock passed it after a stall), the transport moves to the next section with a new generation; the scheduler sees that the previous generation belongs to the same run and continues planning from the boundary **without** `cancelFrom`. Every event of a section therefore carries that section's generation, and nothing older is cancelled because nothing older lies after the boundary. Start, stop, tempo and structural changes still start a new run and cancel. Existing callers (the spike) pass neither field and keep the old rule.

`PlaybackPosition.generation` is the generation of the section **being heard**: it increments when the boundary is heard, while the planner may already be on the next generation up to one horizon earlier. `sectionIndex` is the caller's `originalIndex`, and `cycleIndex` restarts at 0 in each section.

**Bounded "repeat all".** Section runs are laid out lazily, one per pass. A run (and its generation mark) is forgotten once the heard position has passed its end and planning has moved beyond it, so a sequence on "repeat all" keeps only a few runs however long it plays (`test/data/audio/sequence_transport_test.dart`: 2000 passes, at most 4). Event ids stay unique because a run keeps its absolute index.

## How the position is derived

From one `AudioClockReading`: heard time = `outputTime` when the engine reports one, else `renderTime − fallbackOutputLatency` (always the case with SoLoud, so the position is **approximate**, ADR 0002). `TempoMap.beatAt(heard)` gives a tick; the section run containing it gives `sectionIndex`; the tick within that run divided by the practice cycle (exact integer arithmetic) gives `cycleIndex` and `cyclePosition` in [0, 1). Before the first beat (the 30 ms start pad) the position is cycle 0, position 0. The section layout is fixed when playback starts, so a read finds the heard section even when planning has not handed over yet (for example a read exactly on a boundary before the next scheduler wake); it then reports the generation that section is about to receive.

## Engine lifecycle

Every engine operation (start, stop, buffer load and unload, maintenance, dispose) runs through one queue in call order. Each Play carries a request token; a start or buffer load whose token is no longer current, or that arrives after `dispose()`, is skipped. So a Stop during a slow initialization leaves the engine stopped, and a render that finishes after dispose loads nothing. Rendering itself runs in an isolate outside the queue.

## Instruments and buffers

Each layer's `instrumentId` resolves to a factory instrument first, then to the library (`InstrumentLibraryRepository`). A missing id plays silence for that layer and is listed in `PlaybackStatus.missingInstrumentIds`; nothing crashes. Buffers are rendered with `renderInstrument` at `440 · 2^((pitch − 69) / 12)` Hz in an isolate, cached by the sound-defining recipe (harmonics, envelope, EQ; not id, name or tags) and the frequency, loaded as WAV through `loadMem`, and registered **before** the first event of the program is scheduled. Two layers with the same recipe and pitch share one buffer. Beyond 24 cached buffers the least recently used ones that the current program does not use are retired (released after their last voice). Instrument edits in the library apply on the next structural start, not to a running loop.

Gain staging (placeholders until the `musical` gate): `velocity × layer gain × master gain × (accent ? 1 : 0.7) × 0.6`.

## ADR 0002 rev 5 invariants, and where they hold

- **Generation rule:** the transport increments the generation on start, stop, tempo, structure and section switch; `PlaybackScheduler` cancels on every change except a section handover; `SoloudVoiceSink` drops batches older than its cutoff and stops pending older handles.
- **Inverse rebase and late drop:** unchanged spike code. `SoloudVoiceSink` converts each event with `engineAt = event.at − offset` from the same `SoloudAudioClock` snapshot it uses to drop events already late against that snapshot, before `playScheduled`.
- **Voice cap:** `concurrentVoiceLimit` from the program (layers, densest layer in hits per quarter, longest recipe ring capped at 6 s, BPM, 200 ms horizon, 8 audition voices); `setVoiceLimit` reads back the accepted value and Play fails with an error state if SoLoud did not accept it. A program that would need 1023 or more voices is capped at 1022 and reported as `voiceLimitSaturated`.
- **Shared engine:** audition and playback share `SoLoud.instance`; playback never deinitializes it. If another owner deinitialized it (for example the spike screen on close), the next Play detects the lost sources and loads the buffers again.

## Evidence and what is not measured

Unit tests with a fake clock, fake sink and fake engine (`test/data/engine_playback_repository_test.dart`), the spike adapters under a fake plugin (`test/data/audio/soloud_playback_engine_test.dart`) and the scheduler handover (`test/data/audio/playback_scheduler_test.dart`). Evidence level: `unit` and an APK build. **Not measured:** onset timing, jitter, drift, output latency, the audible stop tail, the delay of a mix or tempo change, buffer render time on a phone, whether the voice cap ever saturates audibly, and lifecycle (interruptions, routes, background). These belong to the Founder's device run (`docs/QA.md`, #43).

## Open points

- Per-section tempo in a sequence needs a piecewise `TempoMap` in the core; today one tempo plays the whole sequence.
- Interruptions, audio focus and background are not handled here yet (ADR 0002 lifecycle table); the UI should stop playback when the app leaves the foreground.
- If the spike screen re-initializes SoLoud while playback is running, playback goes silent until the next Play.
