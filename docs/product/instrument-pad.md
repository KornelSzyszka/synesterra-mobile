# Instrument pad

Status: rules decided by the Founder on 2026-10-04 (issue #83); anchor values are **untuned**. Code: `packages/synesterra_core/lib/src/sound/instrument_pad.dart`. Module notes: [instrument](../modules/instrument.md).

## Principles (Founder)

- The instrument experience is simple and synaesthetic. Technical parameters (harmonics, envelope, EQ) are hidden. There is **no advanced mode in v1**.
- The user shapes a timbre by placing one dot on a 2D pad.
- The pad is a view on the existing recipe. The `Instrument` model and its JSON v2 do not change; the pad only produces an ordinary `Instrument`.

## The two axes

| Axis | 0 | 1 |
|---|---|---|
| Horizontal `x` | dark | bright |
| Vertical `y` (grows downward) | soft and airy (top) | hard and sharp (bottom) |

Brightness comes from the harmonic balance (more and stronger upper harmonics to the right) and the EQ. Hardness comes from the envelope: a slow attack and a long decay at the top, an instant attack and a short decay at the bottom.

## Anchors (untuned)

The five named anchors; the names stay. Values are a first proposal derived from the factory instruments (`wood`, `sine`, `bell`) and the character names. They are **untuned** and need a `musical` gate (listening on a device, Founder).

| Anchor | Point (x, y) | Harmonics (amplitude) | Attack | Decay | EQ low / mid / high |
|---|---|---|---|---|---|
| warm drone | (0, 0) | 4, falling fast | 400 ms | 5000 ms | +3 / -1 / -6 dB |
| airy pad | (1, 0) | 9, strong upper partials | 300 ms | 4000 ms | -3 / 0 / +6 dB |
| bass | (0, 1) | 5, mostly low | 2 ms | 500 ms | +6 / 0 / -6 dB |
| guitar | (1, 1) | 12, slowly falling | 1 ms | 1200 ms | -1 / +2 / +3 dB |
| click | (0.5, 1) | 10, broadband | 0 ms | 40 ms | -4 / +4 / +6 dB |

The exact harmonic lists are in `padAnchors`. The click is the hardest point: shortest decay and no attack. Its harmonic centroid sits between bass and guitar so brightness stays ordered along the bottom edge.

## Mapping

The point blends the anchors by edge interpolation:

1. the top edge goes from warm drone to airy pad with `x`;
2. the bottom edge goes from bass to click (`x` 0 to 0.5) and from click to guitar (`x` 0.5 to 1);
3. the point blends the top-edge recipe to the bottom-edge recipe with `y`.

Harmonic lists are padded with zeros to a common length and blended in amplitude; attack (`ln(1 + ms)`) and decay (`ln(ms)`) are blended in the log domain; EQ gains are blended in dB. Result: deterministic, continuous, always a valid `Instrument`, and an anchor point returns its anchor exactly.

Why not inverse-distance weighting: it was tried first. It is smooth, but anchors off the row pulled the spectrum around the click and made brightness drop slightly with `x` on rows near the bottom, breaking the rule that brightness never decreases to the right. Edge interpolation keeps that ordering and is simpler to reason about. Unit tests check each anchor, a 21x21 grid (valid and audible at 48 kHz), continuity, brightness along rows and hardness toward the bottom. This is not evidence of how it sounds.

## v1 covers, later work

- v1 covers the soft half with a slow attack and a long decay inside the model limits (attack up to 500 ms, decay up to 5000 ms).
- Later model change, out of scope here (follow-up): a true sustain (note length and release), noise and a pitch drop (recipe v2).
- Also out of scope: the pad UI, the inverse mapping from an arbitrary instrument to a pad point, saving the pad position.
