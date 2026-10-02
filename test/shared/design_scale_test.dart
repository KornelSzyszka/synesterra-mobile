import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/theme/design_scale.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';

void main() {
  test('phi is the golden ratio', () {
    expect(phi, closeTo((1 + math.sqrt(5)) / 2, 1e-12));
    expect(phi * phi, closeTo(phi + 1, 1e-12));
  });

  test('spacing steps grow by about phi', () {
    const steps = [
      Space.xs,
      Space.sm,
      Space.md,
      Space.lg,
      Space.xl,
      Space.xxl,
      Space.huge,
    ];
    for (var i = 1; i < steps.length; i++) {
      expect(
        steps[i] / steps[i - 1],
        inInclusiveRange(1.4, 1.7),
        reason: 'step $i',
      );
    }
  });

  test('radii grow monotonically', () {
    const radii = [Radii.xs, Radii.sm, Radii.md, Radii.lg];
    for (var i = 1; i < radii.length; i++) {
      expect(radii[i], greaterThan(radii[i - 1]));
    }
  });

  test('the type scale follows 16 * phi^(n/4) to half a point', () {
    expect(typeStep(0), 16);
    expect(typeStep(4), closeTo(16 * phi, 1e-9));
    final sizes = <(double, int)>[
      (TypeScale.overline, -4),
      (TypeScale.caption, -3),
      (TypeScale.body, -2),
      (TypeScale.bodyLarge, 0),
      (TypeScale.title, 2),
      (TypeScale.headline, 4),
      (TypeScale.display, 8),
    ];
    // The named sizes sit near the scale; they are not required to be exact.
    for (final (size, step) in sizes) {
      expect((size - typeStep(step)).abs(), lessThan(1.5), reason: '$size');
    }
  });

  test('golden heights are width over phi and phi squared', () {
    expect(goldenHeight(phi * 100), closeTo(100, 1e-9));
    expect(flatGoldenHeight(phi * phi * 100), closeTo(100, 1e-9));
  });

  test('the graph editors are golden rectangles within their limits', () {
    // 360 dp phone width minus the page padding.
    const width = 328.0;
    expect(goldenHeight(width), closeTo(202.7, 0.1));
    expect(flatGoldenHeight(width), closeTo(125.3, 0.1));
  });

  test('accent is the 10 percent role and differs from the neutral text', () {
    for (final palette in SynesterraPalette.values) {
      final tokens = SynesterraTokens.forPalette(palette);
      expect(tokens.accent, isNot(tokens.text), reason: '$palette');
      expect(tokens.accent, isNot(tokens.background), reason: '$palette');
      final theme = synesterraTheme(palette);
      expect(theme.colorScheme.primary, tokens.accent, reason: '$palette');
      expect(theme.colorScheme.secondary, tokens.accent, reason: '$palette');
      expect(theme.colorScheme.surface, tokens.surface, reason: '$palette');
    }
  });
}
