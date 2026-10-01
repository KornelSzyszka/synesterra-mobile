import 'dart:math' as math;

import 'package:flutter/material.dart';
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
}
