# Loop views

`lib/shared/loop_view/` draws a loop as a circle, a timeline or polygons, and an arrangement as a ring of sections or a strip. Everything is pure painters over an abstract position; nothing here plays sound or touches transport.

## Position contract

`PositionSource` is a `ValueListenable<LoopPosition>`. `LoopPosition` is `{playing, cyclePosition in [0, 1) (half-open: the boundary is 0 of the next cycle), cycleIndex, generation, sectionIndex (nullable)}`. `cycleIndex` counts whole cycles since the current section began (since play began outside an arrangement). Implementations: `FakePositionSource` (tests, demos), `TutorialClock` (ticker-driven, deterministic, no audio, no transport; the one allowed exception to "never driven by a UI timer") and, in the Loop panel task, an adapter over the playback repository's position. The painters repaint through `CustomPainter(repaint: source)`; the widget tree is not rebuilt per frame.

## Model and views

`LoopViewState.fromDocument(SessionDocument)` reads the default scene: per layer its 1-based number, colour index, enabled steps, phase and mute, plus the cycle length. A layer's number is always drawn next to its colour. A step's place in the cycle is `((index + phaseSteps) mod n) / n` (the planner's rule), which assumes every pattern spans the practice cycle (the prototype's rule).

| View | One layer is | Playhead |
|---|---|---|
| Circle | a ring (first layer outermost), a dot per step | rotating line from 12 o'clock, clockwise |
| Timeline | a row, a block per step | vertical line |
| Polygons | a regular polygon with one vertex per **step** (3: triangle, 2: line, 4: square, 5: pentagon) | a dot on the perimeter, on vertex `k` exactly when step `k` hits |

A hit pulse is a function of the position (`stepPulse`), so a stopped view is still. The mode switch is UI state; Polygons is never stored (`presentation.visualMode` stays `circle` or `timeline`). Geometry lives in `loop_geometry.dart` with unit tests; `describeLoop` gives the screen-reader text ("Loop of 4 beats with 2 layers, 3 against 2. ...").

`ArrangementStrip` takes `StripSection {label, repeats, missing, colorIndex, layerSteps}` (the last two feed only the ring) and highlights `sectionIndex`, filling the current section by `(cycleIndex mod repeats + cyclePosition) / repeats`.

`LoopViewDemo` is a debug harness (no route in the app shell) showing the 3:2 and 5:4 examples.

## Look (UX-119)

Visual language v2, painting style only: geometry, layouts and the tested draw
points (playhead line, step and dot centres) are unchanged. Steps are small
lit pearls that bloom into a soft halo on their hit; rings are a hairline over
a faint band; timeline steps are capsules; polygons have a faint fill, a soft
band and a fine edge with round joins; the playhead is a thin gold line over a
glow with a small light at its tip, which also marks the polygons' travelling
dot. Glows use small blurs only, since a playing view repaints every frame.
The mode switch is the shared `RoundSegmented`; the legend is a small light
and the number per layer. The strip draws a capsule per section; the current
one has a gold rim, glow and progress, and its label stays in the text
colour (`ArrangementStripPainter.labelGrounds` lists what labels sit on, for
the contrast test).

## Arrangement ring (UX-123)

The Arrangement panel shows the whole arrangement as a ring of sections
(`arrangement_ring.dart`, geometry in `arrangement_ring_geometry.dart` with
unit tests). The ring is the first version proposed by the coordinator from
the candidates in issue #123 (ring of sections, timeline of mini figures,
stacked polygons). The form is chosen with the Founder, who has not decided
yet and may redirect it after seeing it on the phone.

| Part | Rule |
|---|---|
| Arc | One per section, clockwise from 12 o'clock with a small gap between neighbours (the first gap, with a small gold point, marks the start). Its sweep is proportional to the section's repeats; no arc is shorter than `ringMinSweep` (~8°), and the rest of the ring is shared in proportion (`ringArcs`, for 1..16 sections of 1..32 repeats). |
| Colour | One per distinct loop, in order of first appearance (`loopColorIndexes`), so sections that play the same loop share it. The section card's number gets the same colour as its rim. |
| Number | Outside the arc, in the text colour, when it fits along the arc. |
| Figure | The loop's layers as nested regular polygons (a vertex per step, the Polygons view in miniature) inside the arc, when it fits. |
| Missing loop | A dashed grey arc, no figure. It never holds the light. |
| Playing | The current section glows, gets a gold outer rim and fills in its colour by `ringProgress`; a light walks along its arc (`ringPlayheadAngle`: the playhead walks each section's own arc). Sections already played in this pass are dimmed. The middle shows the section number, its loop and "cycle n of m". |
| Stopped | The middle shows the number of sections and the cycles that will play. |

Driven only by the `PositionSource` (`CustomPainter(repaint: source)` behind
a `RepaintBoundary`): no ticker, no controller, nothing animates while
stopped. Under reduce motion the light moves once a cycle
(`ringProgress(continuous: false)`). No `BackdropFilter`; the glows are two
small `MaskFilter.blur`s.

Semantics: one node with the structure ("3 sections: 1, Verse, 4 times; 2,
Chorus, twice; 3, missing loop, skipped.", `describeArrangement`) and inside
it the strip's live label ("Section 2 of 3, Chorus, cycle 2 of 2.",
`describeArrangementPosition`), rebuilt only when that text changes.

Layout: on a phone held upright the ring (up to 320 dp) sits under the
transport, above the section cards; from 600 dp wide it sits beside the
controls (260 dp) so the sections stay in view. The strip is no longer in the
panel; it stays in Learn and the demo. Section numbers sit on the ground,
possibly under a neighbour's glow; they keep 4.5:1 there in every palette
and under every mist colour (`ArrangementRingPainter.numberGrounds`), which
is why they are never in the muted colour.

Screenshots (Graphite, rendered by a widget test with real fonts, not a
device): [stopped](../assets/arrangement-viz/ring-dark-stopped.png),
[playing section 4](../assets/arrangement-viz/ring-dark-playing.png),
[16 sections](../assets/arrangement-viz/ring-dark-16.png),
[wide](../assets/arrangement-viz/ring-dark-wide.png).
