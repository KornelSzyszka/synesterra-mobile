import 'package:flutter/material.dart';

import 'design_scale.dart';

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

  /// A step above [surface]: dialogs, snackbars and tooltips.
  Color get surfaceHigh => Color.lerp(surface, text, .1)!;

  Color get controlBackground => surface;
  Color get controlBorder => border;
  Color get controlHoverBackground => Color.lerp(surface, text, .2)!;
  Color get controlHoverBorder => muted;
  Color get controlSelectedBackground => Color.lerp(surface, accent, .16)!;
  Color get controlSelectedBorder => Color.lerp(border, accent, .45)!;
  Color get focus => accent;

  /// Accent for small text on tinted or raised grounds (selected controls,
  /// dialog and snack bar actions), where the plain accent falls below 4.5:1
  /// in Autumn. A slight pull toward [text] keeps the hue.
  Color get accentText => Color.lerp(accent, text, .2)!;
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

/// The functional error colour: the only colour outside the three-colour rule
/// (ground, ivory, gold). Layer and identity colours are data colours and
/// appear only inside visualizations.
const _error = Color(0xffe8998a);

ThemeData synesterraTheme(SynesterraPalette palette) {
  final tokens = SynesterraTokens.forPalette(palette);
  final base = ThemeData.dark(useMaterial3: true);
  final platform = base.platform;
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.sm),
  );
  final hairline = BorderSide(color: tokens.controlBorder);
  final selectedSide = BorderSide(color: tokens.controlSelectedBorder);
  final accentOverlay = tokens.accent.withValues(alpha: .14);

  // Every role is set from the tokens, so no Material default hue (the teal
  // of ColorScheme.dark, a tinted surface) can appear. Secondary and tertiary
  // are the accent: the interface has one accent colour.
  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: tokens.accent,
    onPrimary: tokens.onAccent,
    primaryContainer: tokens.controlSelectedBackground,
    onPrimaryContainer: tokens.accentText,
    secondary: tokens.accent,
    onSecondary: tokens.onAccent,
    secondaryContainer: tokens.controlSelectedBackground,
    onSecondaryContainer: tokens.accentText,
    tertiary: tokens.accent,
    onTertiary: tokens.onAccent,
    tertiaryContainer: tokens.controlSelectedBackground,
    onTertiaryContainer: tokens.accentText,
    error: _error,
    onError: tokens.background,
    errorContainer: Color.lerp(tokens.surface, _error, .18)!,
    onErrorContainer: _error,
    surface: tokens.surface,
    onSurface: tokens.text,
    onSurfaceVariant: tokens.muted,
    outline: tokens.controlBorder,
    outlineVariant: tokens.border,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: tokens.text,
    onInverseSurface: tokens.background,
    inversePrimary: tokens.accent,
    surfaceTint: Colors.transparent,
    surfaceDim: tokens.background,
    surfaceBright: tokens.surfaceHigh,
    surfaceContainerLowest: tokens.background,
    surfaceContainerLow: tokens.surface,
    surfaceContainer: tokens.surface,
    surfaceContainerHigh: tokens.surfaceHigh,
    surfaceContainerHighest: tokens.surfaceHigh,
  );

  Color selectedOr(Set<WidgetState> states, Color selected, Color other) =>
      states.contains(WidgetState.selected) ? selected : other;

  final themedText = base.textTheme.apply(
    bodyColor: tokens.text,
    displayColor: tokens.text,
    fontFamily: SynesterraFonts.ui(platform),
    fontFamilyFallback: SynesterraFonts.uiFallback(platform),
  );
  final textTheme = themedText.copyWith(
    displaySmall: themedText.displaySmall?.copyWith(
      fontSize: TypeScale.display,
    ),
    headlineSmall: themedText.headlineSmall?.copyWith(
      fontSize: TypeScale.headline,
    ),
    titleLarge: themedText.titleLarge?.copyWith(fontSize: TypeScale.title),
    titleMedium: themedText.titleMedium?.copyWith(
      fontSize: TypeScale.bodyLarge,
    ),
    bodyLarge: themedText.bodyLarge?.copyWith(fontSize: TypeScale.bodyLarge),
    bodyMedium: themedText.bodyMedium?.copyWith(fontSize: TypeScale.body),
    bodySmall: themedText.bodySmall?.copyWith(fontSize: TypeScale.caption),
    labelLarge: themedText.labelLarge?.copyWith(fontSize: TypeScale.body),
    labelMedium: themedText.labelMedium?.copyWith(fontSize: TypeScale.caption),
    labelSmall: themedText.labelSmall?.copyWith(fontSize: TypeScale.overline),
  );

  return base.copyWith(
    // The default Android splash (InkSparkle) loads a shader; a plain ripple
    // keeps taps calm and does not depend on a shader asset, which also
    // fails to load under flutter_test on Flutter 3.47.
    splashFactory: InkRipple.splashFactory,
    scaffoldBackgroundColor: tokens.background,
    canvasColor: tokens.background,
    colorScheme: scheme,
    focusColor: accentOverlay,
    hoverColor: accentOverlay,
    highlightColor: accentOverlay,
    splashColor: accentOverlay,
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.background,
      foregroundColor: tokens.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: tokens.text,
        fontFamily: SynesterraFonts.serif(platform),
        fontFamilyFallback: SynesterraFonts.serifFallback(platform),
        fontSize: TypeScale.title,
        fontWeight: FontWeight.w600,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: tokens.accent,
      unselectedLabelColor: tokens.muted,
      indicatorColor: tokens.accent,
      dividerColor: tokens.border,
      overlayColor: WidgetStatePropertyAll(accentOverlay),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: tokens.text),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.controlBackground,
      selectedColor: tokens.controlSelectedBackground,
      disabledColor: tokens.controlBackground,
      color: WidgetStateProperty.resolveWith(
        (states) => selectedOr(
          states,
          tokens.controlSelectedBackground,
          tokens.controlBackground,
        ),
      ),
      side: WidgetStateBorderSide.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? selectedSide : hairline,
      ),
      shape: shape,
      labelStyle: TextStyle(color: tokens.text, fontSize: TypeScale.body),
      secondaryLabelStyle: TextStyle(
        color: tokens.accentText,
        fontSize: TypeScale.body,
      ),
      checkmarkColor: tokens.accent,
      deleteIconColor: tokens.muted,
      iconTheme: IconThemeData(color: tokens.text),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => selectedOr(
            states,
            tokens.controlSelectedBackground,
            Colors.transparent,
          ),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => selectedOr(states, tokens.accentText, tokens.text),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? selectedSide : hairline,
        ),
        shape: WidgetStatePropertyAll(shape),
        overlayColor: WidgetStatePropertyAll(accentOverlay),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: TypeScale.body, fontWeight: FontWeight.w500),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.surfaceHigh
              : tokens.accent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.muted
              : tokens.onAccent,
        ),
        shape: WidgetStatePropertyAll(shape),
        minimumSize: const WidgetStatePropertyAll(Size(Space.huge, 48)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.muted
              : tokens.accentText,
        ),
        overlayColor: WidgetStatePropertyAll(accentOverlay),
        shape: WidgetStatePropertyAll(shape),
        minimumSize: const WidgetStatePropertyAll(Size(Space.huge, 48)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(tokens.text),
        side: WidgetStatePropertyAll(hairline),
        shape: WidgetStatePropertyAll(shape),
        minimumSize: const WidgetStatePropertyAll(Size(Space.huge, 48)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: tokens.accent,
      inactiveTrackColor: tokens.border,
      thumbColor: tokens.accent,
      overlayColor: tokens.accent.withValues(alpha: .16),
      disabledActiveTrackColor: tokens.muted,
      disabledInactiveTrackColor: tokens.border,
      disabledThumbColor: tokens.muted,
      trackHeight: Space.xs,
    ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: TextStyle(color: tokens.muted),
      floatingLabelStyle: TextStyle(color: tokens.muted),
      hintStyle: TextStyle(color: tokens.muted),
      counterStyle: TextStyle(color: tokens.muted),
      errorStyle: const TextStyle(color: _error),
      enabledBorder: UnderlineInputBorder(borderSide: hairline),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: tokens.accent, width: 2),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: _error),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: _error, width: 2),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accent,
      selectionColor: tokens.accent.withValues(alpha: .3),
      selectionHandleColor: tokens.accent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: hairline,
      ),
      titleTextStyle: TextStyle(
        color: tokens.text,
        fontFamily: SynesterraFonts.serif(platform),
        fontFamilyFallback: SynesterraFonts.serifFallback(platform),
        fontSize: TypeScale.title,
      ),
      contentTextStyle: TextStyle(color: tokens.text, fontSize: TypeScale.body),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.surfaceHigh,
      contentTextStyle: TextStyle(color: tokens.text, fontSize: TypeScale.body),
      actionTextColor: tokens.accentText,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        side: hairline,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.fromBorderSide(hairline),
      ),
      textStyle: TextStyle(color: tokens.text, fontSize: TypeScale.caption),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        side: hairline,
      ),
      textStyle: TextStyle(color: tokens.text),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: tokens.accent),
    textTheme: textTheme,
    extensions: [tokens],
  );
}
