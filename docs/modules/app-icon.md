# App icon (Android)

A working launcher icon (Founder, 2026-10-08), not a final brand identity. It is the
figure curve `z(t) = sum s_n * e^(i * n * t)` of `lib/shared/instrument_figure/figure_spec.dart`
with harmonics 1 and 4 (amplitudes 1 and 0.24, so three lobes), accent on background of
the Forest palette (`#E4B46A` on `#111512`). Lobe up, farthest point on a 30 dp radius with
a 4 dp stroke on the 108 dp adaptive canvas, so it stays inside the 33 dp safe radius.

## Files (generated, committed; do not edit by hand)

| Path | Role |
|---|---|
| `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` | adaptive icon: background, foreground, monochrome |
| `android/app/src/main/res/values/ic_launcher_background.xml` | background colour |
| `android/app/src/main/res/drawable/ic_launcher_{foreground,monochrome}.xml` | vector layers (the same sampled curve; monochrome is one colour) |
| `android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` | legacy icons, 48 to 192 px |
| `docs/assets/app-icon-{512,192}.png` | previews |

`android:label` is `Synesterra` in `AndroidManifest.xml` (not generated).

## Regenerate

From the repository root:

```text
dart run tool/app_icon.dart           # write the files
dart run tool/app_icon.dart --check   # exit 1 when a committed file is stale
```

`tool/app_icon.dart` is pure Dart with no packages. It holds the harmonics, the
palette constants and its own PNG encoder. Change the curve or colours there, run
the command and commit the result. `flutter_soloud`'s build hook needs a C compiler
on Windows, so `dart run` from the repo root can fail on a host without MSVC; run
it in a copy of the repository whose `pubspec.yaml` has no native-asset
dependencies and copy the output back.

`test/tool/app_icon_test.dart` checks determinism, that the committed files equal the
generator output (PNGs compared as decoded pixels, because the zlib stream may differ
between Dart versions), that the colours equal the Forest tokens in
`synesterra_theme.dart`, the lobe count and the safe zone.

The generator cannot import `figure_spec.dart` (it needs `dart:ui` and an `Instrument`),
so it repeats the harmonic sum; keep the formula in sync if the figure maths changes.
