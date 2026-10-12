# Instrument pad

Status: rules decided by the Founder on 2026-10-04 (issue #83); the pad became a **circle** on 2026-10-13 (issue #107, after the first phone test). Anchor values and the centre recipe are **untuned**. Code: `packages/synesterra_core/lib/src/sound/instrument_pad.dart` (mapping), `lib/features/editor/instrument_pad_view.dart` and `pad_geometry.dart` (UI). Module notes: [instrument](../modules/instrument.md).

## Principles (Founder)

- The instrument experience is simple and synaesthetic. Technical parameters (harmonics, envelope, EQ) are hidden. There is **no advanced mode in v1**.
- The user shapes a timbre by placing one dot on a round pad.
- The pad is a view on the existing recipe. The `Instrument` model and its JSON v2 do not change; the pad only produces an ordinary `Instrument`.

## The two quantities

| Quantity | Meaning |
|---|---|
| Angle around the disc | picks the **character**: which of the five named anchors the sound leans toward |
| Distance from the centre | sets how **pronounced** it is: the centre is a neutral recipe, the rim is the pure character |

The old feel still reads on the rim (a circle inscribed in the old square): soft at the top, hard at the bottom, dark on the left, bright on the right. Brightness comes from the harmonic balance (more and stronger upper harmonics) and the EQ; hardness comes from the envelope (a slow attack and a long decay at the top, an instant attack and a short decay at the bottom).

## Anchors (untuned)

The five named anchors; the names stay. They sit **on the rim**, where the old square corners and the bottom midpoint project onto the inscribed circle. Angles are measured clockwise on screen from the right (`+x`), so 90 degrees is straight down. Values are a first proposal derived from the factory instruments (`wood`, `sine`, `bell`) and the character names. They are **untuned** and need a `musical` gate (listening on a device, Founder).

| Anchor | Place on the rim | Harmonics (amplitude) | Attack | Decay | EQ low / mid / high |
|---|---|---|---|---|---|
| warm drone | top left, -135 degrees | 4, falling fast | 400 ms | 5000 ms | +3 / -1 / -6 dB |
| airy pad | top right, -45 degrees | 9, strong upper partials | 300 ms | 4000 ms | -3 / 0 / +6 dB |
| guitar | bottom right, 45 degrees | 12, slowly falling | 1 ms | 1200 ms | -1 / +2 / +3 dB |
| click | bottom, 90 degrees | 10, broadband | 0 ms | 40 ms | -4 / +4 / +6 dB |
| bass | bottom left, 135 degrees | 5, mostly low | 2 ms | 500 ms | +6 / 0 / -6 dB |

The exact harmonic lists are in `padAnchors`. The click is the hardest point: shortest decay and no attack. Its harmonic centroid sits between bass and guitar so brightness stays ordered along the bottom of the rim.

## The centre (decision)

The Founder asked for a neutral blend at the centre. The Founder has **not** chosen the recipe; the working default (coordinator, 2026-10-13) is the **neutral blend of the five anchors**: the equal-weight mean of the anchors in the same domain where they are blended (amplitudes, log attack and decay, dB). It is always valid and sits in the middle of the pad's range.

The choice lives in one named value, `padCenterRecipe` in `instrument_pad.dart`. To use something else, replace its right-hand side with another `PadRecipe`, for example `PadRecipe.pureSine` (a plain sine with a short fade); nothing else changes, and the tests read the centre through that value. The centre is **untuned**.

## Mapping

The point is polar: a `radius` from 0 (centre) to 1 (rim) and an `angle`.

1. The **rim character** at the point's angle blends the two neighbouring anchors linearly in angle. The list of anchors wraps around, so the seam (the left side) is continuous.
2. The result blends `padCenterRecipe` toward that rim character linearly with the radius.

Harmonic lists are padded with zeros to a common length and blended in amplitude; attack (`ln(1 + ms)`) and decay (`ln(ms)`) are blended in the log domain; EQ gains are blended in dB. Result: deterministic, continuous (also at the centre, where the angle is undefined and does not matter), always a valid `Instrument`; a rim anchor returns its anchor and the centre returns the centre recipe. Because the radius blend is linear, every recipe field moves monotonically from the centre toward the rim as the dot moves outward.

Why angular interpolation of neighbouring anchors: it is the circular counterpart of the edge interpolation the square used, keeps the brightness ordering from the left rim to the right rim through the centre, and is easy to reason about. Inverse-distance weighting was rejected earlier because anchors pulled the spectrum around the click. Unit tests check the rim anchors, the centre, a grid over the disc (valid and audible at 48 kHz), continuity (also across the seam and near the centre), monotonic strength, brightness along the horizontal diameter and hardness toward the bottom. This is not evidence of how it sounds.

## The pad on screen

A disc with faint concentric rings (hints of distance) and the five anchor names on the rim. The dot is clamped inside the disc: a touch outside it puts the dot on the rim in that direction. The gesture is unchanged: touch, drag, and the sound plays once when the finger lifts. For screen readers the pad exposes two adjustable controls in plain words: *Character, turn around the circle* (a step turns 15 degrees; the spoken value names the closest anchor) and *Strength, centre to rim* (a step is 10 % of the radius). Every adjustment plays the sound once. Technical controls stay hidden.

## v1 covers, later work

- v1 covers the soft half with a slow attack and a long decay inside the model limits (attack up to 500 ms, decay up to 5000 ms).
- Later model change, out of scope here (follow-up): a true sustain (note length and release), noise and a pitch drop (recipe v2).
- Also out of scope: the inverse mapping from an arbitrary instrument to a pad point, saving the pad position, and a new visual language for the pad (a separate exploration task).
