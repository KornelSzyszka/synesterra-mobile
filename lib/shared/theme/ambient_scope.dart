import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ground_palette.dart';
import 'synesterra_theme.dart';
import 'tap_effect.dart';

/// What the round components of visual language v2 read from around them:
/// the ground palette, the slow drift that makes organic shapes breathe, and
/// optional overrides of the tap effect. Every value has a fallback, so the
/// components also work without a scope (dark ground, no breathing, the
/// token's tap strength, the app-wide flash gate).
class AmbientScope extends InheritedWidget {
  const AmbientScope({
    super.key,
    required this.palette,
    this.drift,
    this.tapStrength,
    this.gate,
    required super.child,
  });

  final GroundPalette palette;

  /// 0..1 over [driftPeriod], repeating. One controller for the whole screen
  /// keeps the number of animated layers low. Ignored under reduce motion.
  final Animation<double>? drift;

  /// Overrides `SynesterraTokens.tapEffect`.
  final GlitchStrength? tapStrength;

  /// Overrides [FlashGate.app].
  final FlashGate? gate;

  static AmbientScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmbientScope>();

  /// The palette in scope, or the dark ground of the current tokens.
  static GroundPalette paletteOf(BuildContext context) {
    final scope = maybeOf(context);
    if (scope != null) return scope.palette;
    final tokens = SynesterraTokens.of(context);
    return GroundPalette.of(tokens, GroundTone.dark, tokens.layerColors.first);
  }

  /// The drift to breathe with, or null under reduce motion or without one.
  static Animation<double>? driftOf(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return null;
    return maybeOf(context)?.drift;
  }

  /// The tap effect strength in scope.
  static GlitchStrength tapStrengthOf(BuildContext context) =>
      maybeOf(context)?.tapStrength ??
      Theme.of(context).extension<SynesterraTokens>()?.tapEffect ??
      GlitchStrength.subtle;

  /// The flash gate in scope.
  static FlashGate gateOf(BuildContext context) =>
      maybeOf(context)?.gate ?? FlashGate.app;

  @override
  bool updateShouldNotify(AmbientScope oldWidget) =>
      palette != oldWidget.palette ||
      drift != oldWidget.drift ||
      tapStrength != oldWidget.tapStrength ||
      gate != oldWidget.gate;
}

/// Drift (0..1) as a phase in radians.
double breathPhase(Animation<double>? drift) =>
    (drift?.value ?? 0) * 2 * math.pi;
