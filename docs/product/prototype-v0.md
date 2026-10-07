# Prototype v0: loops, arrangements, library and learning

Status: decided by the coordinator on the Founder's brief of 2026-10-07 ("a working prototype with loops, composing loops, a working library, a learning tab and visualizations"). The Founder reviews it on a physical Android phone. Nothing here changes the accepted decisions in [vision](vision.md) except where it says so.

## What the prototype is

A phone app where a user can: shape an instrument on the pad ([instrument pad](instrument-pad.md)), build a **loop** from 2-4 layers (each with an instrument, a pitch and a beat pattern), see it as moving pictures, save loops and instruments in a **library**, chain loops into an **arrangement** and play it, and open a **Learn** tab that explains polyrhythm with live examples.

It is a prototype: the audio path is the ADR 0002 phase-1 engine (`flutter_soloud` behind the ports) and its timing is not yet measured on a device (issue #43, gates G2-G10). Do not claim timing quality. Nothing is published.

## Navigation (changes the vision)

Start screen: **Editor**, **Library**, **Learn** (Learn is new; the Founder asked for it on 2026-10-07, so the vision's "no learning panel for now" no longer holds). Editor has three panels: **Instrument**, **Loop**, **Arrangement**. Library has three tabs in the same order. Transport (Play/Stop, tempo) is always visible in the Loop and Arrangement panels.

## Models

- **Loop** = one library item: `id`, `name`, and a `SessionDocument` v3 (scenes A/B with 2-4 layers; the prototype edits and plays scene A and keeps B equal to A in structure, as the document requires). A loop never embeds instruments; layers reference them by `instrumentId` and `pitch`.
- **Instrument** library items already exist. The three factory instruments are always available; a missing instrument id is shown as "missing sound" and plays silence (no crash).
- **Arrangement** (new, pure Dart in the core): `id`, `name`, ordered `sections`, each `{loopId, repeats}` with `repeats` 1..32 and 1..16 sections. Playing it plays each loop for `repeats` cycles of its practice cycle, then the next; a change from one section to the next happens on a cycle boundary. An option "repeat all" restarts at the first section. A section that references a missing loop is skipped and marked.
- Persistence: one JSON file per item in the app's documents directory, strict validation on read (as the instrument store does), never rewritten until the user saves.

## Loop panel

Per layer: on/off, instrument (picker over the library with the mist as thumbnail), pitch (note picker C1..B7, default A4), number of beats in the cycle (1..16, pattern is evenly spaced steps with tap-to-toggle steps and accents), volume. Global: tempo (20..300 BPM), Play/Stop. Tempo and volume apply immediately; structural changes (steps, instrument, pitch, adding or removing a layer) restart from the start of the cycle (generation rule in [change safety](../agents/change-safety.md)): stale events never sound. Layer identity is its number plus its colour, never colour alone.

## Visualizations

Three views of the same loop, switchable, all driven by the transport position that the playback side exposes (never by a UI timer, and they never drive transport):

1. **Circle**: one ring per layer, a dot per enabled step, a rotating playhead; a hit pulses the dot.
2. **Timeline**: one row per layer across the cycle, a moving playhead line, steps as blocks.
3. **Polygons**: each layer is a polygon with one vertex per beat of its cycle, so 3:2 shows a triangle and a line, 5:4 a pentagon and a square; the playhead is a dot travelling along each polygon.

Arrangement view: a strip of sections with the current section and cycle progress highlighted. Instrument mist, figure and wave already exist. Painters use `CustomPainter` with `RepaintBoundary`.

## Learn tab

A list of short lessons, each: a title, 2-4 plain sentences, a live visualization (the same painters, running on a built-in loop) and an optional "Try it" button that opens the Loop panel with that loop loaded. Content lives in code as data (`lib/features/learn/`), English first (localization is issue #25). Lessons for v0: What a pulse and a cycle are; Two against three (3:2); Four against five (5:4); Layers and instruments; Shaping a sound (the pad); Building and saving a loop; Chaining loops (arrangement).

## Out of scope for v0

True sustain and the drone, noise and pitch-drop instruments, export/import files and sharing, free/pro, iOS, localization (#25), background playback, tuning the pad anchors and the factory instruments (Founder `musical` gate), measuring timing on a device (#43).

## Tasks (in dependency order)

1. This document.
2. Core: `Arrangement` model, JSON, validation, section sequencing (`DOM`).
3. Data: loop and arrangement repositories (file and in-memory) and the Library tabs (`MOB`/`UX`).
4. Audio: a playback repository that turns a `SessionDocument` into sound through `EventPlanner`, the scheduler and the SoLoud sink, with instrument buffers rendered per instrument and pitch, and that exposes the transport position (`AUD`, class L).
5. UI: visualization painters over a position source (`UX`), parallel to 4.
6. UI: Loop panel and transport (`UX`), after 3 and 4.
7. UI: Learn tab (`UX`), after 5.
8. UI: Arrangement panel and playback (`UX`), after 2, 3, 4 and 6.
9. Start screen entry, integration and a phone hand-off (`QA`).
