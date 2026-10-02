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
