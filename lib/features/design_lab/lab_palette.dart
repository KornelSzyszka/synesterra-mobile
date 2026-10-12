import 'package:flutter/material.dart';

import '../../shared/theme/synesterra_theme.dart';

/// Light or dark ground for the lab. The app itself is dark only; the light
/// ground is a lab-local proposal built from the same tokens.
enum LabTone {
  dark('Dark'),
  light('Light');

  const LabTone(this.label);
  final String label;
}

/// The lab's colours for one palette and tone. Every value comes from
/// [SynesterraTokens]; the light tone swaps ground and ink and pulls the gold
/// toward the ink for small text. Nothing here changes the shared theme.
@immutable
class LabPalette {
  const LabPalette._({
    required this.tone,
    required this.ground,
    required this.surface,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.aura,
    required this.auraAlpha,
    required this.light,
    required this.shade,
  });

  /// [aura] is the instrument's identity colour: a data colour, used only for
  /// the mist.
  factory LabPalette.of(SynesterraTokens tokens, LabTone tone, Color aura) {
    switch (tone) {
      case LabTone.dark:
        return LabPalette._(
          tone: tone,
          ground: tokens.background,
          surface: tokens.surface,
          text: tokens.text,
          muted: tokens.muted,
          accent: tokens.accent,
          onAccent: tokens.onAccent,
          accentText: tokens.accentText,
          aura: aura,
          auraAlpha: .1,
          light: Colors.white,
          shade: Colors.black,
        );
      case LabTone.light:
        final ink = tokens.background;
        return LabPalette._(
          tone: tone,
          ground: Color.lerp(tokens.text, Colors.white, .4)!,
          surface: Color.lerp(tokens.text, Colors.white, .72)!,
          text: ink,
          muted: Color.lerp(ink, tokens.muted, .36)!,
          accent: tokens.accent,
          onAccent: ink,
          accentText: Color.lerp(tokens.accent, ink, .62)!,
          aura: aura,
          auraAlpha: .2,
          light: Colors.white,
          shade: Color.lerp(ink, Colors.black, .4)!,
        );
    }
  }

  final LabTone tone;
  final Color ground;
  final Color surface;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color accentText;
  final Color aura;

  /// The strongest alpha of the mist behind the components.
  final double auraAlpha;

  /// The colour of highlights (light on glass, glaze, sheen).
  final Color light;

  /// The colour of shadows.
  final Color shade;

  bool get isDark => tone == LabTone.dark;

  List<Object> get _fields => [
    tone,
    ground,
    surface,
    text,
    muted,
    accent,
    onAccent,
    accentText,
    aura,
    auraAlpha,
    light,
    shade,
  ];

  @override
  bool operator ==(Object other) =>
      other is LabPalette && _listEquals(other._fields, _fields);

  @override
  int get hashCode => Object.hashAll(_fields);

  static bool _listEquals(List<Object> a, List<Object> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The opaque grounds text can sit on: the plain ground and the ground under
  /// the brightest point of the mist (instrument colour, accent and both).
  List<Color> get groundSamples {
    Color veil(Color color, Color under) =>
        Color.alphaBlend(color.withValues(alpha: auraAlpha), under);
    return [
      ground,
      veil(aura, ground),
      veil(accent, ground),
      veil(accent, veil(aura, ground)),
    ];
  }
}

/// WCAG 2.x contrast ratio of two opaque colours, 1..21.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

/// A text colour and every opaque colour it may be drawn on, for the
/// contrast test.
@immutable
class LabTextPair {
  const LabTextPair(this.name, this.text, this.backgrounds);

  final String name;
  final Color text;
  final List<Color> backgrounds;

  /// The lowest contrast of [text] over [backgrounds].
  double get worstContrast => backgrounds
      .map((background) => contrastRatio(text, background))
      .reduce((a, b) => a < b ? a : b);
}
