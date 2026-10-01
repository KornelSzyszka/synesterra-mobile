import 'package:flutter/material.dart';

enum SynesterraPalette { forest, autumn, highContrast }

@immutable
class SynesterraTokens extends ThemeExtension<SynesterraTokens> {
  const SynesterraTokens({
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.border,
    required this.accent,
    required this.layerColors,
  });

  final Color background;
  final Color surface;
  final Color text;
  final Color muted;
  final Color border;
  final Color accent;
  final List<Color> layerColors;

  Color get controlBackground => surface;
  Color get controlBorder => border;
  Color get controlHoverBackground => Color.lerp(surface, text, .2)!;
  Color get controlHoverBorder => muted;
  Color get controlSelectedBackground => Color.lerp(surface, accent, .16)!;
  Color get controlSelectedBorder => Color.lerp(border, accent, .45)!;
  Color get focus => accent;
  Color get onAccent => background;

  // A slight blend keeps layer identity while meeting text contrast on the
  // tinted chip background in all three palettes.
  Color disabledLayerText(Color layerColor) =>
      Color.lerp(surface, layerColor, .88)!;

  Color disabledLayerSwatch(Color layerColor) =>
      Color.lerp(surface, layerColor, .55)!;

  static const layerPalette = <Color>[
    Color(0xffe4b46a),
    Color(0xff81b6bf),
    Color(0xffc3a1d9),
    Color(0xffa5bd80),
    Color(0xffdf8f6f),
    Color(0xffd5a6e8),
    Color(0xff7fc7a8),
    Color(0xffd8c06d),
    Color(0xff8fa9df),
    Color(0xffd98eae),
    Color(0xff8bc4bb),
    Color(0xffc5a27d),
  ];

  static const forest = SynesterraTokens(
    background: Color(0xff111512),
    surface: Color(0xff1a1f1a),
    text: Color(0xffeae9df),
    muted: Color(0xffa0a89e),
    border: Color(0xff333a32),
    accent: Color(0xffe4b46a),
    layerColors: layerPalette,
  );

  static const autumn = SynesterraTokens(
    background: Color(0xff15120f),
    surface: Color(0xff211b16),
    text: Color(0xfff1e8dc),
    muted: Color(0xffb7a99b),
    border: Color(0xff49392c),
    accent: Color(0xffc37a24),
    layerColors: layerPalette,
  );

  static const highContrast = SynesterraTokens(
    background: Color(0xff000000),
    surface: Color(0xff000000),
    text: Color(0xffffffff),
    muted: Color(0xffffffff),
    border: Color(0xffffffff),
    accent: Color(0xffffff00),
    layerColors: layerPalette,
  );

  static SynesterraTokens forPalette(SynesterraPalette palette) =>
      switch (palette) {
        SynesterraPalette.forest => forest,
        SynesterraPalette.autumn => autumn,
        SynesterraPalette.highContrast => highContrast,
      };

  static SynesterraTokens of(BuildContext context) =>
      Theme.of(context).extension<SynesterraTokens>()!;

  @override
  SynesterraTokens copyWith({
    Color? background,
    Color? surface,
    Color? text,
    Color? muted,
    Color? border,
    Color? accent,
    List<Color>? layerColors,
  }) => SynesterraTokens(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    accent: accent ?? this.accent,
    layerColors: layerColors ?? this.layerColors,
  );

  @override
  SynesterraTokens lerp(ThemeExtension<SynesterraTokens>? other, double t) {
    if (other is! SynesterraTokens) return this;
    return SynesterraTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      layerColors: [
        for (var i = 0; i < layerColors.length; i++)
          Color.lerp(layerColors[i], other.layerColors[i], t)!,
      ],
    );
  }
}

class SynesterraFonts {
  const SynesterraFonts._();

  static bool _isApple(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  static String ui(TargetPlatform platform) =>
      _isApple(platform) ? 'CupertinoSystemText' : 'sans-serif';

  static List<String> uiFallback(TargetPlatform platform) => _isApple(platform)
      ? const ['Helvetica Neue', 'sans-serif']
      : const ['Roboto'];

  static String serif(TargetPlatform platform) =>
      _isApple(platform) ? 'Georgia' : 'serif';

  static List<String> serifFallback(TargetPlatform platform) =>
      _isApple(platform)
      ? const ['Times New Roman', 'serif']
      : const ['Noto Serif', 'Georgia'];

  static String monospace(TargetPlatform platform) =>
      _isApple(platform) ? 'Menlo' : 'monospace';

  static List<String> monospaceFallback(TargetPlatform platform) =>
      _isApple(platform)
      ? const ['Courier New', 'monospace']
      : const ['Roboto Mono', 'Menlo'];
}

ThemeData synesterraTheme(SynesterraPalette palette) {
  final tokens = SynesterraTokens.forPalette(palette);
  final base = ThemeData.dark(useMaterial3: true);
  final platform = base.platform;
  return base.copyWith(
    scaffoldBackgroundColor: tokens.background,
    colorScheme: ColorScheme.dark(
      primary: tokens.accent,
      onPrimary: tokens.onAccent,
      surface: tokens.surface,
      onSurface: tokens.text,
      outline: tokens.border,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.background,
      foregroundColor: tokens.text,
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.surface,
      textStyle: TextStyle(color: tokens.text),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: tokens.text,
      displayColor: tokens.text,
      fontFamily: SynesterraFonts.ui(platform),
      fontFamilyFallback: SynesterraFonts.uiFallback(platform),
    ),
    extensions: [tokens],
  );
}
