# Design tokens

`lib/shared/theme/synesterra_theme.dart` is the visual styling API for Flutter widgets.
`SynesterraTokens` is a `ThemeExtension` exposed by `synesterraTheme`; widgets read it
with `SynesterraTokens.of(context)`. `SynesterraPalette` selects Graphite (default),
Forest, Autumn, or High contrast. The app's palette menu lists them in that order and
changes the current theme in memory.

**Graphite** (Founder, 2026-10-13) is the default: neutral dark greys with a very
slight cool tint (`background #121417`, `surface #1C1F24`, `border #2C3036`, `text
#E6E7EA`, `muted #A8ADB5`) and the launcher icon's gold (`accent #E4B46A`), so the app
and the icon belong together. `muted` was lifted from a first `#9EA3AB` after the
design lab's contrast test found 4.30:1 on a raised organic surface. Forest, Autumn
and High contrast are unchanged. The launcher icon stays on the Forest values: its
generator (`tool/app_icon.dart`) and its test read the `forest` token by name, not
the default palette.

The six base colours (`background`, `surface`, `text`, `muted`, `border`, `accent`)
and twelve layer colours mirror the web laboratory's `palette.ts`. Derived control
colours follow its `tokens.css` mixes. `onAccent` uses the palette background.
Layer colours remain fixed between palettes so a layer's identity stays stable.

UI text uses Android `sans-serif` or iOS `CupertinoSystemText`. Large numbers use
Android `serif` or iOS `Georgia`; metadata uses Android `monospace` or iOS `Menlo`.
Each family has an explicit `fontFamilyFallback` list for missing glyphs. Section
labels use uppercase with wide spacing. There are no bundled fonts or new
dependencies. Disabled layers blend their own colour toward `surface` for text
and more strongly for the swatch, keeping layer identity and 4.5:1 text contrast
on the chip background in all palettes.

Shared widgets in `lib/shared/widgets/design_components.dart` provide panels,
section labels, numbered chips, number steppers, layer toggles and a gold primary
button. The rhythm screen uses these widgets without owning palette values.
The tempo stepper repeats on a long press with increasing speed; a tap changes
one BPM. The UI timer only handles input and does not drive playback timing.

## Visual language v2: round shapes, three surfaces (UX-112)

The shared foundation for the blend of glass, organic and material chosen after the
design lab (Founder, 2026-10-13). Screens adopt it in later tasks; until then they
keep the rounded-rectangle `Radii` (kept as they are, with a note in
`design_scale.dart`). Code: `lib/shared/theme/` and `lib/shared/widgets/`.

### Tokens (`lib/shared/theme/`)

| File | API | What it is |
|---|---|---|
| `round_shapes.dart` | `sealed class RoundShape { Path outline(Rect rect, {double breath = 0}); }` with `RoundShape.circle`, `RoundShape.capsule`, `RoundShape.lens`, `BlobShape({required int seed, double amount = BlobAmount.round})`, `PebbleShape({int seed = 0, double exponent = 4})`; `BlobAmount.still / round / wide` (.05 / .075 / .16); path functions `circlePath`, `capsulePath`, `blobPath`, `pebblePath`, `lensPath`, `smoothClosedPath` | Shape tokens. No straight corner anywhere. Blobs breathe through `breath` (radians). |
| `surfaces.dart` | `enum SurfaceKind { glass, organic, tactile }`; `enum SurfaceStyle { glass, organic, tactile, tactileSelected, primary, tray }` (each has a `kind`); `class Surfaces(GroundPalette)` with `paint(canvas, path, rect, style, {pressed})`, `textOn(style)`, `mutedOn(style)`, `fillSamples(style)`, `textPairs()`, `paintHighlight`, `paintRim`; `Elevation.tactileLift / floatingBlur`; `Glow.accentBlur / accentAlpha / accentPressedAlpha / haloBlur` | Surface kinds with one job each: **glass** for floating layers over the mist (panels, sheets, the transport bar), **organic** for shapes and figures (cards, the pad), **tactile** for things you press (Play, chips, segments, the slider). |
| `ground_palette.dart` | `enum GroundTone { dark, light }`; `GroundPalette.of(SynesterraTokens, GroundTone, Color aura)`; `contrastRatio(a, b)`; `TextContrastPair`; `veiled(color, alpha, grounds)` | The palette of one ground, from the tokens (the light ground is the lab's proposal). |
| `tap_effect.dart` | `enum GlitchStrength { off, subtle, strong }`; `GlitchMode`, `glitchModeFor(strength, reduceMotion:)`; `glitchDuration` (220 ms); `maxFlashesPerSecond` (3); `flashAllowed(now:, last:)`; `FlashGate({Duration Function()? clock})` with `tryFlash(now)`, `tryFlashNow()` and the app-wide `FlashGate.app`; `driftPeriod` (18 s) | The tap-effect safety rules, moved from the lab. |
| `ambient_scope.dart` | `AmbientScope({required GroundPalette palette, Animation<double>? drift, GlitchStrength? tapStrength, FlashGate? gate, required Widget child})`; `paletteOf`, `driftOf` (null under reduce motion), `tapStrengthOf`, `gateOf`; `breathPhase(drift)` | What the round components read. Without a scope: the dark ground of the current tokens, no breathing, the token's tap strength, `FlashGate.app`. |
| `synesterra_theme.dart` | `SynesterraTokens.tapEffect` (`GlitchStrength`, optional, default `subtle`; in `copyWith` and `lerp`) | The tap-effect strength token. Existing callers are unchanged. |

### Components (`lib/shared/widgets/`)

| Component | Signature | Surface |
|---|---|---|
| `RoundActionButton` | `({required IconData icon, required String label, required VoidCallback? onPressed, double size = 64})` | tactile `primary`: a glazed gold disc with a soft glow |
| `RoundIconButton` | `({required IconData icon, required String label, required VoidCallback? onPressed, bool? selected, double size = 48})` | tactile, `tactileSelected` while a toggle is on |
| `TactileChip` | `({required String label, required VoidCallback? onPressed, bool? selected, bool primary = false})` | tactile capsule; `primary` is the gold answer |
| `RoundSegmented<T>` | `({required List<(T, String)> options, required T value, required ValueChanged<T> onChanged})` | a tactile `tray` with the choice raised |
| `RoundSlider` | `({required String label, required double value, required ValueChanged<double> onChanged, String Function(double) valueText})` | a tactile groove filled with gold, a tactile thumb |
| `GlassPanel` | `({required Widget child, RoundShape shape = RoundShape.capsule, EdgeInsetsGeometry padding})` | glass; `RoundShape.lens` for a sheet |
| `OrganicCard` | `({required Widget child, String? label, VoidCallback? onTap, int seed = 7, bool breathes = false, EdgeInsetsGeometry padding})` | organic blob |
| `RoundSurface` | `({required SurfaceStyle style, RoundShape shape = RoundShape.capsule, bool pressed = false, bool breathes = false, EdgeInsetsGeometry padding, Widget? child})` | the building block of all of the above |
| `TapGlitch` | `({required Widget child, RoundShape shape = RoundShape.circle, GlitchStrength? strength})` | the tap effect |

Helpers: `roundText(context, color:, size:, serif:, weight:, spacing:)`, `textOn(context, style)`,
`mutedTextOn(context, style)`.

Every tappable component is one semantics node with its label (`selected` and
`enabled` where they apply) and at least 48 × 48 dp. The slider is announced as a
slider with its value and steps by a tenth.

**`TapGlitch`**: a polarized split. A cool and a warm copy of the element's outline
slip apart and snap back while the rim catches the light. It stays inside the
element and lasts 220 ms. The `FlashGate` in scope allows at most three flashes per
second across the screen; a faster retap still reaches the child but does not flash.
Under reduce motion it is a plain short fade, and with strength `off` it paints
nothing. It only watches the pointer (a drag never flashes); do not wrap things
that are dragged.

**Cost**: no `BackdropFilter` and no shaders. Glass is a translucent gradient with a
highlight and a 1 px rim. Glows and shadows use `MaskFilter.blur` on small shapes.
The only continuous animation is the scope's one drift, used by shapes that
`breathe`; keep that to one or two elements per screen (the Blend breathes the pad
only). Animated parts sit behind `RepaintBoundary`.

**Contrast**: `Surfaces.textPairs()` lists every text colour with every opaque colour
it is drawn on. For glass that means the gradient stops and the highlight over the
ground under the brightest point of the mist. `test/shared/surfaces_test.dart`
checks 4.5:1 for every surface style, all four palettes, both grounds and all twelve
instrument colours. Two rules come from that test: on dark glass, secondary text is
pulled toward the main text, and on a selected (gold-tinted) tactile surface there
is no dim second tier at all.

## Colour roles: three colours, 60 : 30 : 10

The interface uses three colour roles in roughly these proportions:

| Role | Share | Tokens |
|---|---|---|
| Ground | 60% | `background`, `surface`, `surfaceHigh` (dialogs, menus, snack bars) |
| Neutral | 30% | `text`, `muted`, `border` |
| Accent | 10% | `accent` (gold): the primary action, the selection, the focus. `accentText` (gold pulled 20% toward `text`) is the small text on tinted or raised grounds: selected chip and segment labels, dialog and snack bar actions |

Everything interactive that is not the primary action stays neutral: controls are
outlined in `border`, selected chips and segments get a gold-tinted background and
accent text, sliders and tabs use the accent. The `ColorScheme` in `synesterraTheme`
is built only from these tokens (primary, secondary and tertiary are all the accent;
containers use the selected-control tint), so a stock Material widget cannot bring in
a colour of its own. The twelve layer colours and the identity colour of an
instrument are **data** colours (they say which layer or which sound it is) and are
the only places where more hues appear.

## Golden ratio and scales

`lib/shared/theme/design_scale.dart` holds the numbers; widgets use them instead of
literals:

- `Space`: 4, 6, 10, 16, 26, 42, 68 (steps of about φ from 16).
- `Radii`: 4, 7, 10, 17.
- `TypeScale`: 10, 12.5, 14, 16, 20.5, 26, 42, on `16 · φ^(n/4)` to half a point
  (`typeStep(n)`).
- `goldenHeight(width) = width / φ` for drawing surfaces (the spectrum and the EQ;
  limited to 120–260 and 140–260 dp) and `flatGoldenHeight(width) = width / φ²` for
  the flatter envelope graph (96–200 dp).

The old literals map to the nearest step: 4→xs, 5–9→sm, 10–12→md, 16–20→lg, 24→xl.
Tests (`test/shared/design_scale_test.dart`, `test/shared/synesterra_theme_test.dart`)
check the scale, the contrast of every text role (4.5:1) and that the accent is the
only colour of the theme's primary roles.

What this does not claim: that the look is right. The proportions are a rule; whether
the app feels balanced is a Founder review on a phone.
