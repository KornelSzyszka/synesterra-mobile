import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/theme/ground_palette.dart';
import 'package:synesterra/shared/theme/round_shapes.dart';
import 'package:synesterra/shared/theme/surfaces.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/theme/tap_effect.dart';

void main() {
  test('every text colour meets 4.5:1 on every surface style, for every '
      'palette, tone and instrument colour', () {
    final failures = <String>[];
    final kinds = <SurfaceKind>{};
    var checked = 0;
    for (final palette in SynesterraPalette.values) {
      final tokens = SynesterraTokens.forPalette(palette);
      for (final aura in tokens.layerColors) {
        for (final tone in GroundTone.values) {
          final surfaces = Surfaces(GroundPalette.of(tokens, tone, aura));
          for (final pair in surfaces.textPairs()) {
            checked++;
            if (pair.worstContrast < 4.5) {
              failures.add(
                '${palette.name} aura ${aura.toARGB32().toRadixString(16)} '
                '${pair.name}: ${pair.worstContrast.toStringAsFixed(2)}',
              );
            }
          }
          for (final style in SurfaceStyle.values) {
            kinds.add(style.kind);
            expect(surfaces.fillSamples(style), isNotEmpty);
          }
        }
      }
    }
    expect(kinds, SurfaceKind.values.toSet());
    // 4 palettes x 12 colours x 2 tones x (3 ground + 6 styles x 2 roles).
    expect(checked, 4 * 12 * 2 * 15);
    expect(failures, isEmpty, reason: failures.take(20).join('\n'));
  });

  test('glass samples include the mist under the translucent fill', () {
    final tokens = SynesterraTokens.graphite;
    final palette = GroundPalette.of(
      tokens,
      GroundTone.dark,
      tokens.layerColors[2],
    );
    final samples = Surfaces(palette).fillSamples(SurfaceStyle.glass);
    // Four ground samples x two gradient stops, then the same under the
    // highlight.
    expect(samples, hasLength(16));
    expect(samples.toSet().length, greaterThan(8));
  });

  test('round shapes stay round and inside their rectangle', () {
    const rect = Rect.fromLTWH(10, 20, 200, 80);
    for (final shape in <RoundShape>[
      RoundShape.circle,
      RoundShape.capsule,
      const BlobShape(seed: 3, amount: BlobAmount.wide),
      const PebbleShape(seed: 1),
    ]) {
      final bounds = shape.outline(rect).getBounds();
      // Blobs may wander outward by their amount of the half height.
      expect(
        rect.inflate(80 / 2 * BlobAmount.wide + .5).contains(bounds.topLeft),
        isTrue,
        reason: '$shape',
      );
      expect(
        rect
            .inflate(80 / 2 * BlobAmount.wide + .5)
            .contains(bounds.bottomRight - const Offset(.01, .01)),
        isTrue,
        reason: '$shape',
      );
    }
    // No straight corner: the top-left corner point is outside every shape.
    for (final shape in <RoundShape>[
      RoundShape.circle,
      RoundShape.capsule,
      const PebbleShape(),
    ]) {
      expect(
        shape.outline(rect).contains(rect.topLeft + const Offset(1, 1)),
        isFalse,
      );
    }
    // The lens rises from its sides to the top edge in the middle and is
    // straight at the bottom (getBounds is not tight for arcs).
    final lens = RoundShape.lens.outline(rect);
    expect(lens.contains(Offset(rect.center.dx, rect.top + 1)), isTrue);
    expect(lens.contains(Offset(rect.center.dx, rect.top - 1)), isFalse);
    expect(lens.contains(rect.topLeft + const Offset(1, 1)), isFalse);
    expect(lens.contains(rect.bottomLeft + const Offset(1, -1)), isTrue);
    expect(
      const BlobShape(seed: 3),
      const BlobShape(seed: 3, amount: BlobAmount.round),
    );
    expect(const BlobShape(seed: 3), isNot(const BlobShape(seed: 4)));
  });

  group('SynesterraTokens.tapEffect', () {
    test('is optional and defaults to subtle for every palette', () {
      const custom = SynesterraTokens(
        background: Colors.black,
        surface: Colors.black,
        text: Colors.white,
        muted: Colors.white,
        border: Colors.white,
        accent: Colors.yellow,
        layerColors: SynesterraTokens.layerPalette,
      );
      expect(custom.tapEffect, GlitchStrength.subtle);
      for (final palette in SynesterraPalette.values) {
        expect(
          SynesterraTokens.forPalette(palette).tapEffect,
          GlitchStrength.subtle,
        );
      }
    });

    test('copyWith and lerp carry it', () {
      final strong = SynesterraTokens.graphite.copyWith(
        tapEffect: GlitchStrength.strong,
      );
      expect(strong.tapEffect, GlitchStrength.strong);
      expect(strong.copyWith().tapEffect, GlitchStrength.strong);
      expect(strong.background, SynesterraTokens.graphite.background);
      expect(
        strong.lerp(SynesterraTokens.forest, .2).tapEffect,
        GlitchStrength.strong,
      );
      expect(
        strong.lerp(SynesterraTokens.forest, .8).tapEffect,
        GlitchStrength.subtle,
      );
    });

    test('the theme carries the tokens unchanged', () {
      for (final palette in SynesterraPalette.values) {
        final theme = synesterraTheme(palette);
        expect(
          theme.extension<SynesterraTokens>(),
          SynesterraTokens.forPalette(palette),
        );
      }
    });
  });

  group('FlashGate clock', () {
    test('tryFlashNow uses the gate clock', () {
      var now = Duration.zero;
      final gate = FlashGate(clock: () => now);
      expect(gate.tryFlashNow(), isTrue);
      now = const Duration(milliseconds: 200);
      expect(gate.tryFlashNow(), isFalse);
      now = const Duration(milliseconds: 340);
      expect(gate.tryFlashNow(), isTrue);
    });
  });
}
