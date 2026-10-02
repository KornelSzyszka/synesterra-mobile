# Instrument recipe

Code: `packages/synesterra_core/lib/src/sound/instrument.dart`, tests in `packages/synesterra_core/test/instrument_test.dart`. Vision and the reason for the model: [product vision](../product/vision.md).

An `Instrument` is a sound recipe for one rhythm voice: pitch, harmonics, envelope and EQ. It has no rhythm, tempo or backend knowledge (core context `sound`, rule R2 of [decision 0001](../decisions/0001-architecture-style.md)). It validates in its constructor, so an existing instance is always renderable. A later audio step renders a recipe into a buffer; this module does not.

## JSON v1

```text
Instrument { version: 1, id: string, name: string, fundamentalHz: number,
  harmonics: number[], envelope: {attackMs: integer, decayMs: integer},
  eq: {lowDb: number, midDb: number, highDb: number} }
```

| Field | Range |
|---|---|
| `id` | `[A-Za-z0-9-]`, 1..64 characters (same rule as a rhythm layer id) |
| `name` | 1..40 UTF-16 units, not blank, no control characters |
| `fundamentalHz` | 40..2000, finite |
| `harmonics` | 1..32 amplitudes, each 0..1, at least one above 0; index 0 is the fundamental |
| `attackMs` | integer 0..500 |
| `decayMs` | integer 20..5000 |
| EQ gains | -12..+12 dB; fixed corners: low shelf 200 Hz, mid peak 1 kHz, high shelf 4 kHz |

`Instrument.fromJson` is strict: unknown and missing fields, wrong types and out-of-range values all throw a `FormatException` whose message starts with the JSON path (`$.envelope.decayMs: ...`). Callers reading files catch `FormatException` and treat the file as corrupt.

## Factory instruments

`factoryInstruments` has `factory-wood`, `factory-sine` and `factory-bell`, the three sounds of the web laboratory, as starting points for a new instrument. Their numbers are placeholders; tuning by ear needs the `musical` gate.

## Not here yet

A layer referencing an instrument by id, embedding instruments in a session file and a `SessionDocument` version bump are a separate task that needs a version and migration decision. So are persistence, the library and the UI.
