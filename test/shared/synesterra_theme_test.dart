import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';

double _linear(int value) {
  final channel = value / 255;
  return channel <= .04045
      ? channel / 12.92
      : math.pow((channel + .055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) =>
    .2126 * _linear((color.r * 255).round()) +
    .7152 * _linear((color.g * 255).round()) +
    .0722 * _linear((color.b * 255).round());

double _contrast(Color a, Color b) {
  final aa = _luminance(a);
  final bb = _luminance(b);
  return (aa > bb ? aa + .05 : bb + .05) / (aa > bb ? bb + .05 : aa + .05);
}

void main() {
  test('all palette text roles and layer labels meet 4.5:1 contrast', () {
    for (final palette in SynesterraPalette.values) {
      final tokens = SynesterraTokens.forPalette(palette);
      for (final foreground in [
        tokens.text,
        tokens.muted,
        tokens.accent,
        ...tokens.layerColors,
      ]) {
        expect(
          _contrast(foreground, tokens.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$palette $foreground on surface',
        );
      }
      for (final layerColor in tokens.layerColors) {
        final disabled = tokens.disabledLayerText(layerColor);
        final chipBackground = Color.alphaBlend(
          disabled.withValues(alpha: .12),
          tokens.surface,
        );
        expect(
          _contrast(disabled, chipBackground),
          greaterThanOrEqualTo(4.5),
          reason: '$palette disabled $layerColor on chip',
        );
        expect(disabled, isNot(tokens.muted));
      }
      expect(
        _contrast(tokens.text, tokens.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(tokens.onAccent, tokens.accent),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(SynesterraTokens.layerPalette, hasLength(12));
  });

  test('selected controls, dialogs and snack bars meet 4.5:1 contrast', () {
    for (final palette in SynesterraPalette.values) {
      final tokens = SynesterraTokens.forPalette(palette);
      final theme = synesterraTheme(palette);
      final scheme = theme.colorScheme;
      const selected = {WidgetState.selected};
      const enabled = <WidgetState>{};
      final segment = theme.segmentedButtonTheme.style!;
      final pairs = <String, (Color, Color)>{
        'segment selected': (
          segment.foregroundColor!.resolve(selected)!,
          segment.backgroundColor!.resolve(selected)!,
        ),
        'segment unselected on surface': (
          segment.foregroundColor!.resolve(enabled)!,
          tokens.surface,
        ),
        'chip selected label': (
          theme.chipTheme.secondaryLabelStyle!.color!,
          theme.chipTheme.selectedColor!,
        ),
        'chip unselected label': (
          theme.chipTheme.labelStyle!.color!,
          theme.chipTheme.backgroundColor!,
        ),
        'primary container': (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        'secondary container': (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
        ),
        'tertiary container': (
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
        ),
        'dialog action': (
          theme.textButtonTheme.style!.foregroundColor!.resolve(enabled)!,
          theme.dialogTheme.backgroundColor!,
        ),
        'snack bar action': (
          theme.snackBarTheme.actionTextColor!,
          theme.snackBarTheme.backgroundColor!,
        ),
        'dialog text': (tokens.text, tokens.surfaceHigh),
        'muted on surfaceHigh': (tokens.muted, tokens.surfaceHigh),
        'error on surfaceHigh': (scheme.error, tokens.surfaceHigh),
        'error on surface': (scheme.error, tokens.surface),
        'onError on error': (scheme.onError, scheme.error),
        'onAccent on accent': (tokens.onAccent, tokens.accent),
        'accentText on surface': (tokens.accentText, tokens.surface),
      };
      for (final MapEntry(:key, :value) in pairs.entries) {
        expect(
          _contrast(value.$1, value.$2),
          greaterThanOrEqualTo(4.5),
          reason: '$palette $key',
        );
      }
    }
  });

  test('every ColorScheme role comes from the tokens', () {
    for (final palette in SynesterraPalette.values) {
      final tokens = SynesterraTokens.forPalette(palette);
      final scheme = synesterraTheme(palette).colorScheme;
      final allowed = <Color>{
        tokens.background,
        tokens.surface,
        tokens.surfaceHigh,
        tokens.text,
        tokens.muted,
        tokens.border,
        tokens.accent,
        tokens.accentText,
        tokens.onAccent,
        tokens.controlBorder,
        tokens.controlSelectedBackground,
        scheme.error,
        scheme.errorContainer,
        Colors.black,
        Colors.transparent,
      };
      final roles = <String, Color>{
        'primary': scheme.primary,
        'onPrimary': scheme.onPrimary,
        'primaryContainer': scheme.primaryContainer,
        'onPrimaryContainer': scheme.onPrimaryContainer,
        'primaryFixed': scheme.primaryFixed,
        'primaryFixedDim': scheme.primaryFixedDim,
        'onPrimaryFixed': scheme.onPrimaryFixed,
        'onPrimaryFixedVariant': scheme.onPrimaryFixedVariant,
        'secondary': scheme.secondary,
        'onSecondary': scheme.onSecondary,
        'secondaryContainer': scheme.secondaryContainer,
        'onSecondaryContainer': scheme.onSecondaryContainer,
        'secondaryFixed': scheme.secondaryFixed,
        'secondaryFixedDim': scheme.secondaryFixedDim,
        'onSecondaryFixed': scheme.onSecondaryFixed,
        'onSecondaryFixedVariant': scheme.onSecondaryFixedVariant,
        'tertiary': scheme.tertiary,
        'onTertiary': scheme.onTertiary,
        'tertiaryContainer': scheme.tertiaryContainer,
        'onTertiaryContainer': scheme.onTertiaryContainer,
        'tertiaryFixed': scheme.tertiaryFixed,
        'tertiaryFixedDim': scheme.tertiaryFixedDim,
        'onTertiaryFixed': scheme.onTertiaryFixed,
        'onTertiaryFixedVariant': scheme.onTertiaryFixedVariant,
        'error': scheme.error,
        'onError': scheme.onError,
        'errorContainer': scheme.errorContainer,
        'onErrorContainer': scheme.onErrorContainer,
        'surface': scheme.surface,
        'onSurface': scheme.onSurface,
        'surfaceDim': scheme.surfaceDim,
        'surfaceBright': scheme.surfaceBright,
        'surfaceContainerLowest': scheme.surfaceContainerLowest,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHigh': scheme.surfaceContainerHigh,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
        'onSurfaceVariant': scheme.onSurfaceVariant,
        'outline': scheme.outline,
        'outlineVariant': scheme.outlineVariant,
        'shadow': scheme.shadow,
        'scrim': scheme.scrim,
        'inverseSurface': scheme.inverseSurface,
        'onInverseSurface': scheme.onInverseSurface,
        'inversePrimary': scheme.inversePrimary,
        'surfaceTint': scheme.surfaceTint,
      };
      for (final MapEntry(:key, :value) in roles.entries) {
        expect(allowed, contains(value), reason: '$palette $key $value');
      }
      expect(scheme.primary, tokens.accent);
      expect(scheme.secondary, tokens.accent);
      expect(scheme.tertiary, tokens.accent);
    }
  });

  group('selected and unselected controls in a widget tree', () {
    for (final palette in SynesterraPalette.values) {
      testWidgets('$palette chip and segmented button', (tester) async {
        final tokens = SynesterraTokens.forPalette(palette);
        await tester.pumpWidget(
          MaterialApp(
            theme: synesterraTheme(palette),
            home: Scaffold(
              body: Column(
                children: [
                  ChoiceChip(
                    label: const Text('on-chip'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  ChoiceChip(
                    label: const Text('off-chip'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('on-seg')),
                      ButtonSegment(value: 2, label: Text('off-seg')),
                    ],
                    selected: const {1},
                    onSelectionChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Color labelColor(String text) =>
            (tester.renderObject<RenderParagraph>(find.text(text)).text
                    as TextSpan)
                .style!
                .color!;

        // The Material closest to the label is the segment's own.
        Material segmentMaterial(String text) => tester.widget(
          find
              .ancestor(of: find.text(text), matching: find.byType(Material))
              .first,
        );

        ShapeDecoration chipFill(String text) =>
            tester
                    .widget<Ink>(
                      find
                          .descendant(
                            of: find.ancestor(
                              of: find.text(text),
                              matching: find.byType(ChoiceChip),
                            ),
                            matching: find.byType(Ink),
                          )
                          .first,
                    )
                    .decoration!
                as ShapeDecoration;

        final chipOn = chipFill('on-chip');
        final chipOff = chipFill('off-chip');
        expect(chipOn.color, tokens.controlSelectedBackground);
        expect(chipOff.color, tokens.controlBackground);
        expect(
          (chipOn.shape as RoundedRectangleBorder).side.color,
          tokens.controlSelectedBorder,
        );
        expect(
          (chipOff.shape as RoundedRectangleBorder).side.color,
          tokens.controlBorder,
        );
        expect(labelColor('on-chip'), tokens.accentText);
        expect(labelColor('off-chip'), tokens.text);

        final segOn = segmentMaterial('on-seg');
        final segOff = segmentMaterial('off-seg');
        expect(segOn.color, tokens.controlSelectedBackground);
        expect(segOff.color, anyOf(isNull, Colors.transparent));
        expect(labelColor('on-seg'), tokens.accentText);
        expect(labelColor('off-seg'), tokens.text);
        expect(
          _contrast(labelColor('on-seg'), segOn.color!),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  test('platform font families have explicit fallbacks', () {
    expect(SynesterraFonts.serif(TargetPlatform.iOS), 'Georgia');
    expect(SynesterraFonts.monospace(TargetPlatform.iOS), 'Menlo');
    expect(SynesterraFonts.serif(TargetPlatform.android), 'serif');
    expect(SynesterraFonts.monospace(TargetPlatform.android), 'monospace');
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      expect(SynesterraFonts.uiFallback(platform), isNotEmpty);
      expect(SynesterraFonts.serifFallback(platform), isNotEmpty);
      expect(SynesterraFonts.monospaceFallback(platform), isNotEmpty);
    }
  });

  test('taps use a plain ripple, not the shader-based sparkle', () {
    for (final palette in SynesterraPalette.values) {
      expect(synesterraTheme(palette).splashFactory, InkRipple.splashFactory);
    }
  });
}
