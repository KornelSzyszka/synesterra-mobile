# Instrument recipe

Code: `packages/synesterra_core/lib/src/sound/` (`instrument.dart`, `instrument_renderer.dart`, `instrument_response.dart`, internal `biquad.dart`), tests in `packages/synesterra_core/test/`. Vision and the reason for the model: [product vision](../product/vision.md).

An `Instrument` is a **reusable timbre preset**: harmonics, envelope, EQ and tags. It has **no pitch** (Founder, 2026-10-02): whoever plays it chooses the frequency. A loop layer does that; the editor only plays a note or a chord to let the user hear it, and that test sound is not stored in the instrument. An instrument knows nothing about rhythm, tempo or the audio backend (core context `sound`, rule R2 of [decision 0001](../decisions/0001-architecture-style.md)). It validates in its constructor, so an existing instance is always renderable.

## PCM rendering

`renderInstrument(instrument, fundamentalHz: ..., sampleRate: 48000)` produces a deterministic, mono `Float32List` in the pure-Dart core for one pitch (20..8000 Hz). It sums the harmonics at multiples of `fundamentalHz`, skips harmonics at or above Nyquist, applies broad RBJ low-shelf (200 Hz), peaking (1 kHz, Q 1.0) and high-shelf (4 kHz) filters using `InstrumentEq`, then applies the envelope and peak-normalises only when needed. Attack is linear; `decayMs` is the exponential time to -60 dB, and the first and last samples are forced to zero. The buffer is capped at six seconds and contains no UI, plugin or I/O work, so a caller may render it in an isolate before handing it to the audio backend.

On the task host (Windows 11, Dart from Flutter 3.35.7), rendering the heaviest permitted recipe (32 harmonics, 5 s decay, 48 kHz; 240001 samples) had a median time of **67.9 ms** across five post-warm-up runs. This is a unit-level host measurement, not evidence of audio timing or sound quality on a device.

A chord is several buffers, one per note, played together. A buffer is identified by the sound-defining part of the recipe (harmonics, envelope, EQ) and one frequency; name, id and tags do not change the sound.

## JSON v2

```text
Instrument { version: 2, id: string, name: string, tags: string[],
  harmonics: number[], envelope: {attackMs: integer, decayMs: integer},
  eq: {lowDb: number, midDb: number, highDb: number} }
```

| Field | Range |
|---|---|
| `id` | `[A-Za-z0-9-]`, 1..64 characters (same rule as a rhythm layer id) |
| `name` | 1..40 UTF-16 units, not blank, no control characters |
| `tags` | at most 6, no repeats; each 1..24 characters, lowercase `a-z`, `0-9`, space or `-`, not starting with a space or `-` |
| `harmonics` | 1..32 amplitudes, each 0..1, at least one above 0; index 0 is the fundamental |
| `attackMs` | integer 0..500 |
| `decayMs` | integer 20..5000 |
| EQ gains | -12..+12 dB; fixed corners: low shelf 200 Hz, mid peak 1 kHz, high shelf 4 kHz |

`Instrument.fromJson` is strict: unknown and missing fields, wrong types and out-of-range values all throw a `FormatException` whose message starts with the JSON path (`$.envelope.decayMs: ...`). Callers reading files catch `FormatException` and treat the file as corrupt.

**Version 1** (the first release, where an instrument had a `fundamentalHz` and no tags) still loads: the pitch is checked for shape and then dropped, and the tags are empty. Loading never rewrites a file; the next save writes version 2. Any other version is rejected with `$.version: unsupported version`.

`Instrument.normalizeTag(raw)` trims, lowercases and collapses spaces, and returns null for anything that is not a valid tag. The editor uses it, so a stored tag is always already normalized. `suggestedInstrumentTags` lists the quick-add labels (click, wood, metal, bell, tone, drum, soft, bright, dark); any valid tag is allowed.

## Factory instruments

`factoryInstruments` has `factory-wood`, `factory-sine` and `factory-bell`, the three sounds of the web laboratory, as starting points for a new instrument, each with tags. Their numbers are placeholders; tuning by ear needs the `musical` gate.

## EQ response and shaped harmonics

`eqResponseDb(eq, hz)` is the combined gain of the three EQ bands at a frequency, in dB. `shapedHarmonics(instrument, fundamentalHz: ...)` is each harmonic's amplitude after that gain when the instrument plays at that pitch (0 at or above Nyquist); the EQ acts on frequencies, so the result depends on the pitch. Both use the same internal `Biquad` as `renderInstrument`, so a picture drawn from them describes what the renderer does (a test compares the predicted gain of a tone with the rendered one). They feed the Figure and Wave views (for the test sound's root note) and, later, the EQ curve editor.

## In the editor

The test sound is **Note** (any note C1..B7, default A4) or **Chord** (root plus Major, Minor, Dom 7, Maj 7, Min 7, Sus 4 or Power). It lives in the view model, not in the draft: choosing it does not mark the instrument changed and is never saved. Playing the instrument renders and plays one buffer per note. The colour of an instrument (mist, figure, wave, thumbnails) comes from a stable hash of its id, so it does not change with the test note. Tags are edited in the panel and filter the library.

## Drawing the spectrum

The Spectrum section is a bar chart with one bar per harmonic (the stepper sets how many). Touch or drag across the bars to set their heights; a fast stroke is interpolated so no bar is skipped, a touch in the bottom 3 % sets 0, and the last touched bar is selected and shown with a 48 dp slider for fine tuning (the accessible way to set one harmonic). White marks show each harmonic after the EQ at the test note. Shapes (Sine, Saw 1/n, Square odd 1/n, Soft 1/n²) and the Brightness slider redraw every bar; changing the count keeps the bars already drawn and continues the brightness curve for new ones. The chart wins the gesture at once, so touching it draws instead of scrolling the page. Every change goes through `setHarmonics`, which ignores a change that would silence the instrument and never plays sound itself; the sound plays after the finger is lifted. Pure helpers (`barIndexAt`, `amplitudeAt`, `strokeBetween`) are in `lib/features/editor/spectrum_geometry.dart`.

## Envelope and EQ graphs

The envelope graph draws the real envelope (`envelopeLevel`, shared with the renderer): a linear attack to full level, then an exponential decay to -60 dB. The time axis is square-root scaled (a 2 ms click and a 5 s tail both readable). Two handles: the **peak** sets the attack (0..500 ms), the **end** sets the decay (20..5000 ms), and the values are written next to them.

The EQ graph draws the combined response (`eqResponseDb`) on a log frequency axis (20 Hz..20 kHz) and a ±12 dB gain axis. Three handles sit at the fixed corners (200 Hz, 1 kHz, 4 kHz); dragging one up or down sets that band's gain in half-decibel steps. Faint vertical ticks mark the harmonics of the test note, so it is visible which harmonics each band touches. The corner frequencies are fixed in the model, so a handle moves only vertically.

Both graphs take the gesture at once (`ImmediatePanDetector`, shared with the spectrum), so touching them never scrolls the page. A touch picks the nearest handle within 28 dp; farther away does nothing. The sound plays after the finger is lifted. The sliders under the graphs stay as the precise and accessible way to set the same values. Pure axis and hit-testing helpers are in `lib/features/editor/curve_geometry.dart`.

## Sessions reference instruments

Since `SessionDocument v3` ([session document](session-document.md)) a loop layer holds an `instrumentId` (the id rule above) and a `pitch`, an integer MIDI note 24..107 (C1..B7, the editor's test range). The frequency for `renderInstrument` is `440 * 2^((pitch - 69) / 12)`. Instruments are never embedded in a session; the library owns them. The core accepts an id it cannot resolve, and the data layer decides what a missing instrument means.

## Radar (UI)

The Instrument panel's main control is the radar of traits (UX-115; it replaced the circular pad, whose `instrument_pad.dart` was removed from the core). `InstrumentRadar` in `lib/features/editor/instrument_radar_view.dart` draws one axis per `TraitDefinition` (any number from three up), lets the user drag a vertex along its axis only, plays on lift, offers the `traitPresets` as chips and exposes one adjustable semantics control per trait. The editor view model holds `InstrumentTraits` and builds the draft with `instrumentForTraits`; an opened instrument shows `traitsForInstrument` and is not rewritten until the user moves the radar and saves. Pure geometry: `lib/shared/instrument_radar/radar_geometry.dart`; painters (also used for the library thumbnail): `radar_painter.dart`. Product rules: [instrument radar](../product/instrument-radar.md).

## Traits

`instrument_traits.dart` is the radar-chart view on the recipe (Founder, 2026-10-13, issue #111): a few plain-language traits, each 0 (centre) to 1 (edge), produce an ordinary `Instrument`. The recipe and JSON v2 do not change; traits are not saved. The traits are **data**: `defaultTraitDefinitions` is a list of `TraitDefinition(id, label, defaultValue, effect)`, and `InstrumentTraits(Map<String, double>, {definitions})` holds immutable, validated values (unknown id, NaN, infinity or a value outside 0..1 throw `ArgumentError`; a missing id takes its default). Each definition declares a `TraitEffect` (`harmonicTilt`, `harmonicCount`, `lowShelf`, `highShelf`, `attack`, `decay`), the recipe field it drives, so a trait added to the list works without code; two definitions with the same effect are rejected, and an effect no trait drives stays neutral (0.5). Equality of `InstrumentTraits` includes the definitions. The values below are **untuned**; the Founder judges the sound by ear.

| Trait | Recipe field | Forward mapping |
|---|---|---|
| Brightness | harmonic amplitudes | harmonic `k` has amplitude `k^-slope`, slope 2 (dark) down to 0 (bright) |
| Fullness | harmonic count | `1 + 31 * fullness` harmonics; the last, partial one fades in (continuous) |
| Warmth | low shelf EQ | -12..+12 dB, linear |
| Air | high shelf EQ | -12..+12 dB, linear |
| Softness | `attackMs` | 0..500 ms, exponential (`20 * (exp(s * ln 26) - 1)`) |
| Length | `decayMs` | 20..5000 ms, exponential |

`instrumentForTraits(traits, id:, name:, tags:)` is deterministic, always valid and non-silent (the fundamental is 1), monotonic in every trait with the others held fixed, and continuous up to the whole milliseconds of attack and decay. The mid EQ band stays 0 dB.

`traitsForInstrument(instrument)` is an **approximate inverse** so a saved or factory instrument can be shown on the chart. Fullness is the last harmonic above 1e-4 of the strongest (with the fractional last harmonic recovered from the measured slope); brightness is the amplitude-weighted harmonic centroid `sum(k * a_k) / sum(a_k)`, matched by bisection against the forward mapping at the measured count (below fullness 0.1 it is not observable and reads 0.5); warmth and air are the shelf gains; softness and length invert the attack and decay scales. Everything is clamped into 0..1. Tested bound: for an instrument made by `instrumentForTraits`, every trait comes back within **0.02** (measured worst case on 30 000 random vectors: 0.016, fullness; the largest part of it is the 2-harmonic case, where the fade of the second harmonic cannot be told from its slope and the midpoint is taken, an error of at most 0.5/31 = 0.016; softness from whole-millisecond attack is 0.008; brightness is checked from fullness 0.1 up). For other recipes the result is the nearest reading, not a promise of the same sound.

`traitPresets` are named shapes: `neutral` and the five characters `warm drone`, `airy pad`, `bass`, `guitar`, `click` (dark soft long, bright soft, dark hard, bright hard, hardest and shortest). The radar screen uses them since UX-115. Tests: `test/instrument_traits_test.dart` (validation, presets, seeded vectors and cube corners, monotonicity, continuity, round trip, factory instruments). This is not evidence of how it sounds.

## Not here yet

A true sustain (note length and release), noise and a pitch drop, and saving the trait values with an instrument (traits are read back approximately). Also the UI to choose an instrument or a pitch in the Loop panel, and resolving a missing instrument against the library. So is a progression as a test sound (it needs timing).
