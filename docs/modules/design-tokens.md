# Design tokens

`lib/shared/theme/synesterra_theme.dart` is the visual styling API for Flutter widgets.
`SynesterraTokens` is a `ThemeExtension` exposed by `synesterraTheme`; widgets read it
with `SynesterraTokens.of(context)`. `SynesterraPalette` selects Forest (default),
Autumn, or High contrast. The app's palette menu changes the current theme in memory.

The six base colours (`background`, `surface`, `text`, `muted`, `border`, `accent`)
and twelve layer colours mirror the web laboratory's `palette.ts`. Derived control
colours follow its `tokens.css` mixes. `onAccent` uses the palette background.
Layer colours remain fixed between palettes so a layer's identity stays stable.

UI text uses the system sans family, large numbers use the platform serif family,
and small metadata uses monospace. Section labels use uppercase with wide spacing.
There are no bundled fonts or new dependencies. Disabled layers display their
number, name and value in `muted` instead of reducing opacity, preserving text
contrast. The theme test checks foreground roles and all layer colours against
surface at 4.5:1 or higher.

Shared widgets in `lib/shared/widgets/design_components.dart` provide panels,
section labels, numbered chips, number steppers, layer toggles and a gold primary
button. The rhythm screen uses these widgets without owning palette values.
