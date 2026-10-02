# SessionDocument v2 contract

Source: accepted web laboratory specification `PLR-010-session-document-v2-contract.md`, sections 4–8. This page is the local contract for DOM-015. The web app is a behaviour reference, not a runtime dependency.

## Model and units

`SessionDocument` is portable, immutable, versioned data. It is validated on every read before use. `SessionProject`, the planner, runtime performance state, v1 migration, persistence, UI, and native audio are deferred. Transport beats are quarter notes. `transport.bpm` defines their rate. `transport.practiceCycleBeats` is the quantization and UI cycle; it does not constrain individual pattern periods. A pattern's `durationBeats` is its own period, and step `i` starts at `durationBeats * i / steps.length`. The phase is `durationBeats * phaseSteps / steps.length` modulo the period. Runtime transport and pending changes never appear in the document or export envelope.

The exact v2 JSON shape is:

```text
SessionDocument { format: "polyrhythmer.session", version: 2, revision: 0,
  title: string, transport: {beatUnit: "quarter-note", bpm: number,
    practiceCycleBeats: Rational}, referenceClick: {subdivision: integer},
  randomSeed: integer, scenes: [Scene(A), Scene(B)], defaultSceneId: "A"|"B",
  presentation: {visualMode: "circle"|"timeline"} }
Rational {numerator: integer, denominator: integer}
Scene {id: "A"|"B", layers: Layer[], masterGain: number, drone: Drone}
Layer {id: string, sound: "wood"|"sine"|"bell",
  pattern: {durationBeats: Rational, steps: Step[]}, phaseSteps: integer,
  swing: {grid: "off"|"eighth"|"sixteenth", amount: number},
  mix: {gain: number, pan: number, muted: boolean, solo: boolean} }
Step {enabled: boolean, velocity: number, accent: boolean, probability: number}
Drone {enabled: boolean, root: integer, octave: integer, mode: string,
  chord: "root"|"fifth"|"octave"|"triad", gain: number,
  filterHz: number, spread: number}
```

`velocity` and `accent` are distinct. Disabled steps make no triggers. The planner's probability choice will use `randomSeed` and event coordinates deterministically; mutable global randomness is outside this contract. Swing `off` requires amount zero. Eighth swing uses a half-beat grid; sixteenth uses a quarter-beat grid. Every enabled step must lie on the selected grid before swing. An amount of 1 delays alternate grid points by half a grid interval, giving at most a 75:25 ratio. Micro offsets, tuplet swing, arbitrary groove templates, and per-step timing shifts require a future schema revision.

Scenes contain pattern, phase, swing, sound, mix, master gain, and drone snapshots. They contain no BPM, practice cycle, reference click, title, seed, presentation, active scene, transport state, or device state. A and B have 2–4 layers each and the same ordered layer IDs. Pattern, mix, sound, and drone may differ. Changing topology between scenes is deferred.

## Validation

The parser rejects the whole input; it never trims, partially imports, or silently drops fields. Errors carry a JSON path and code. There are no unknown fields at any level. Unsafe keys `__proto__`, `prototype`, and `constructor` are rejected at every depth. JSON has at most 16 container levels and at most 128 KiB of UTF-8 before parsing. All numbers are finite JSON numbers, never strings or negative zero. Integer fields reject fractional values.

| Field | Allowed values |
|---|---|
| `title` | 0–80 Unicode code points after NFC normalization; no control characters |
| `scenes` | exactly A and B in order |
| `layers` | 2–4 per scene; unique ID, same ordered IDs across scenes |
| `layer.id` | 1–64 ASCII characters, `^[A-Za-z0-9-]{1,64}$` |
| `steps` | 1–32 per layer, at most 256 in the document |
| `bpm` | 20–300 |
| rational periods | 1/16–32; numerator 1–1024; denominator 1–32; reduced form only |
| step spacing | duration divided by step count at least 1/16 beat |
| `phaseSteps` | integer 0 through `steps.length - 1` |
| velocity, probability, gain, spread, swing amount | 0–1 |
| pan | -1–1 |
| `randomSeed` | uint32, 0–4294967295 |
| reference subdivision | integer 0–6; 0 disables click |
| drone root, octave, filter | integer root 0–11; integer octave 1–5; filter 100–8000 Hz |

Title limits use NFC normalization before counting Unicode code points, while preserving the supplied title value. This uses `unorm_dart` 0.3.2: a pure-Dart MIT-licensed package, maintained with Unicode 17 data and no platform dependency. A local normalization table would be larger to maintain and more likely to be incomplete. No other field in this implemented shape has an NFC length limit.

## Export envelope

```text
{ format: "polyrhythmer.session-export", envelopeVersion: 1,
  exportedAt: RFC 3339 UTC string,
  createdWith: {app: "Polyrhythmer", version: 1–32 ASCII characters},
  session: SessionDocument }
```

`exportedAt` and `createdWith` are informational. Compatibility depends on the envelope and document versions and session validation. Export serializes canonical field order and blocks output over 128 KiB. Import checks bytes, JSON, depth, and unsafe keys first. It then checks format and supported envelope/document versions before enforcing exact object shapes and other document invariants. This resolves the PLR-010 §8.1 ordering inconsistency in favor of its requirement that a newer version returns `unsupported_version`, even when it adds fields; invalid content returns `validation_error`. No owner, library metadata, file path, entitlement, audio data, asset URL, executable code, or runtime state belongs in the envelope. Legacy v1 import, migration, preview, and committing an imported session to the library are deferred. File and system share sheet are the intended transfer path; link and QR transfer are deferred.
