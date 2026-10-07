# Design tokens

`lib/shared/theme/synesterra_theme.dart` is the visual styling API for Flutter widgets.
`SynesterraTokens` is a `ThemeExtension` exposed by `synesterraTheme`; widgets read it
with `SynesterraTokens.of(context)`. `SynesterraPalette` selects Forest (default),
Autumn, or High contrast. The app's palette menu changes the current theme in memory.

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
