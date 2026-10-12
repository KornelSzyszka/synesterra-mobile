import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/design_lab/lab_components.dart';
import 'package:synesterra/features/design_lab/lab_palette.dart';
import 'package:synesterra/features/design_lab/lab_skin.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';

void main() {
  test('contrast ratio matches the WCAG reference values', () {
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21, .01));
    expect(contrastRatio(Colors.white, Colors.white), closeTo(1, .001));
    // #767676 on white is the classic 4.54:1 boundary grey.
    expect(
      contrastRatio(const Color(0xff767676), Colors.white),
      closeTo(4.54, .01),
    );
  });

  test('every lab text colour meets 4.5:1 on every surface it is drawn on, '
      'in every variant, tone, palette and instrument colour', () {
    final failures = <String>[];
    var checked = 0;
    for (final palette in SynesterraPalette.values) {
      final tokens = SynesterraTokens.forPalette(palette);
      for (final aura in tokens.layerColors) {
        for (final tone in LabTone.values) {
          final labPalette = LabPalette.of(tokens, tone, aura);
          for (final variant in LabVariant.values) {
            for (final pair in skinFor(variant, labPalette).textPairs()) {
              checked++;
              final worst = pair.worstContrast;
              if (worst < 4.5) {
                failures.add(
                  '${palette.name} aura ${aura.toARGB32().toRadixString(16)} '
                  '${pair.name}: ${worst.toStringAsFixed(2)}',
                );
              }
            }
          }
        }
      }
    }
    expect(checked, greaterThan(1000));
    expect(failures, isEmpty, reason: failures.take(20).join('\n'));
  });

  test('translucent glass samples include the mist under it', () {
    final tokens = SynesterraTokens.forest;
    final palette = LabPalette.of(tokens, LabTone.dark, tokens.layerColors[2]);
    final samples = skinFor(
      LabVariant.glass,
      palette,
    ).fillSamples(LabKind.plain);
    // Four ground samples x two gradient stops, then the same under the
    // highlight.
    expect(samples, hasLength(16));
    expect(samples.toSet(), hasLength(greaterThan(8)));
  });
}
