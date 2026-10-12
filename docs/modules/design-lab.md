# Design lab (debug only)

A debug-only screen that renders **the same components** in three visual
directions, so the Founder can compare them on a phone and pick one or a blend.
Brief (Founder, 2026-10-13): round shapes (circles and soft organic curves, not
rounded rectangles), minimal (few elements, much space, almost no chrome) and a
touch of magic (soft light, gentle glow, slow drift; never noisy). Addition
(Founder, 2026-10-13): a short glitch / polarization flash as a tap response.

Code: `lib/features/design_lab/`. Nothing here is product UI, and the shared
theme (`SynesterraTokens`, `design_scale.dart`) is unchanged: the light ground,
shapes, shadows and glows are local to the lab.

## How to open it

1. `flutter run -d <device>` (a debug build; `flutter build apk --debug` and
   install also works).
2. On the Start screen, **long-press the title "◉ synesterra"**.
3. In release builds the long press does nothing (`designLabAvailable()` is
   `kDebugMode`; `SynesterraApp(designLab: false)` simulates release in tests).

Top of the lab: back, the ground switch (sun / moon icon: dark or light),
the variant switch **Glass · Organic · Material**, the **Tap flash** strength
(**Off · Subtle · Strong**) and a small frame-time line (average build and
raster time of the last reported frames, and the worst raster time).

## The components

Each variant shows, top to bottom: a section header, the circular instrument
pad (the lab's own painter with the Bell's mist inside; drag the light), a
segmented control (Mist / Figure / Wave), a slider (Level), tags (chips), a
library card (mist in a round vessel, name, kind, small Play), the transport
bar (Loop, Play, Stop, tempo), and a bottom sheet sample (inline preview, and
"Open as sheet" opens it as a real modal sheet). The instrument mist also
drifts very softly behind everything.

## The three variants

| | Glass | Organic | Material |
|---|---|---|---|
| Idea | Light through clear lenses | Soft forms that breathe | Pebbles and glazed ceramic |
| Shapes | Exact circles and capsules | Blobs: capsules and circles pushed in and out by three slow waves, each element with its own asymmetry | Slightly uneven superellipses (pebbles), circles for buttons |
| Surfaces | Translucent gradient fill, soft inner highlight at the top, 1 px light rim; no `BackdropFilter` | Opaque radial light from the top-left, no border, a faint halo in the instrument's colour | Opaque, lit top-left, soft drop shadow, faint fixed grain; concave trays (pad well, segment track, slider groove) |
| Gold | A lit orb with a soft glow | A gold blob with a warm halo | A glazed gold pebble with a glaze highlight |
| Segmented | One glass track, the choice is an inner lens | Three separate blobs | A concave tray, the choice is a raised pebble |
| Slider | Hairline with a glowing gold line, glass bead | A tail that swells from thin to full, gold blob | A groove filled with gold, a pebble thumb |
| Sheet | Lens-shaped top (one shallow arc) | Slow wave along the top | Ceramic slab with a full rounded top |
| Motion | Mist drift; the light on the pad glows slowly | Mist drift; the pad edge and the Play blob breathe | Mist drift; a slow glint on the pad's pebble |
| Tap flash | Polarized sheen: a narrow band of violet, cyan and gold sweeps once across the lens | Chromatic split: a cool and a warm copy of the outline slip apart and snap back | Slice jitter: a few horizontal slices step sideways with a faint gold edge and snap back |

Screenshots (rendered by a widget test with real fonts, Forest palette, Bell
instrument; the drift is frozen at one moment):

| | Dark | Light |
|---|---|---|
| Glass | ![](../assets/design-lab/glass-dark.png) | ![](../assets/design-lab/glass-light.png) |
| Organic | ![](../assets/design-lab/organic-dark.png) | ![](../assets/design-lab/organic-light.png) |
| Material | ![](../assets/design-lab/material-dark.png) | ![](../assets/design-lab/material-light.png) |

Tap flash, Strong, about 70 ms into a tap on Play:
`glass-dark-flash.png`, `organic-dark-flash.png`, `material-dark-flash.png`
and the `-light-flash` versions in `docs/assets/design-lab/`.

## Rules the lab keeps (tested)

- **Contrast**: every text colour on every surface it is drawn on is at least
  4.5:1, for all three palettes, both grounds, all twelve instrument colours
  and all variants (`test/features/design_lab/lab_contrast_test.dart`). The
  test checks the worst case: gradient stops and highlights composited over the
  ground under the brightest point of the mist. One finding: over a lit mist,
  dark glass has no room for a dim second text tier, so its secondary text is
  pulled most of the way toward the main text.
- **Touch targets** at least 48 dp and **labels** for TalkBack on every
  control (`androidTapTargetGuideline`, `labeledTapTargetGuideline`).
- **Reduce motion** (system "remove animations"): the drift and breathing
  stop and the tap flash becomes a plain short fade, no movement.
- **Flash safety**: one flash lasts 220 ms; at most three flashes per second
  across the whole lab (a shared `FlashGate`; a faster retap still works but
  does not flash), small areas only, no full-screen flash (WCAG 2.3.1).
- **Cost**: no `BackdropFilter`, no shaders. Animated layers per variant: the
  mist (all), the pad, and the Play blob (organic only), each behind a
  `RepaintBoundary`. Glows and shadows use `MaskFilter.blur` on small shapes.
  The material grain is computed once per size. The inline sheet preview uses
  one static `saveLayer` for its fade.

No live-blur variant was built (the brief allowed one only as a marked toggle
with measured frame time).

## What to look at on the phone

1. Each variant on the dark and the light ground: which feels most like
   Synesterra; does anything read as a rectangle or as chrome?
2. Drag the light on the pad; tap Play, the chips and the segments with Tap
   flash on Subtle and on Strong. Is the flash a touch of magic or noise?
3. Turn on Settings > Accessibility > Remove animations, reopen the lab: still
   pleasant without motion?
4. Watch the frame-time line while the lab idles and while tapping. On a
   Galaxy A33 a frame has 16.7 ms; a debug build is slower than release, so
   treat the numbers as an upper bound.
5. Text readability outdoors / at low brightness, especially secondary text on
   glass.

## Decision record (to fill after the Founder's review)

- Date:
- Chosen direction (or blend, and which part from which variant):
- Ground: dark only / dark and light:
- Tap flash: off / subtle / strong, and in which variant's form:
- What to drop or change:
- Follow-up tasks (theme tokens, shared widgets):
