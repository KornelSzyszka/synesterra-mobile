# Loop views

`lib/shared/loop_view/` draws a loop as a circle, a timeline or polygons, and an arrangement strip. Everything is pure painters over an abstract position; nothing here plays sound or touches transport.

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

`ArrangementStrip` takes `StripSection {label, repeats, missing}` and highlights `sectionIndex`, filling the current section by `(cycleIndex mod repeats + cyclePosition) / repeats`.

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
