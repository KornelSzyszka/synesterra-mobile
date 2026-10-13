import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/ambient_scope.dart';
import '../theme/design_scale.dart';
import '../theme/ground_palette.dart';
import '../theme/synesterra_theme.dart';
import '../theme/tap_effect.dart';
import 'round_components.dart';

// The frame of a screen in visual language v2: the dark ground with a very
// slow mist, one drift for everything on the screen, and a quiet header with
// a round Back button. Screens put their content in [RoundScreen.child].

/// A screen of the app: a [Scaffold] on the ground of the current palette,
/// an [AmbientScope] for the round components, the one slow drift of the
/// screen (stopped under reduce motion) and a round header.
///
/// A screen with [drifts] moves its mist and breathing shapes in one breath: a
/// single pass over [driftPeriod] that ends where it began, so it rests
/// without a jump. It runs when the screen appears and again whenever the
/// screen is touched (never under reduce motion). A screen at rest schedules
/// no frames, which saves battery and lets `pumpAndSettle` finish in tests.
/// Screens without [drifts] are still: no ticker at all.
///
/// Cost: one animation controller and one repainted layer (the mist, behind
/// a [RepaintBoundary]); the content never repaints with the drift.
class RoundScreen extends StatefulWidget {
  const RoundScreen({
    super.key,
    required this.child,
    this.title,
    this.actions = const [],
    this.below,
    this.showHeader = true,
    this.drifts = false,
  });

  /// The screen's content, below the header.
  final Widget child;

  /// The header's title, set as a heading. Null shows only the Back button.
  final String? title;

  /// Round buttons at the right end of the header.
  final List<Widget> actions;

  /// Fixed content between the header and [child] (a tab strip).
  final Widget? below;

  /// False for a screen that draws its own top (the Start screen).
  final bool showHeader;

  /// True only where the drift is part of the picture (the Start screen).
  final bool drifts;

  @override
  State<RoundScreen> createState() => _RoundScreenState();
}

class _RoundScreenState extends State<RoundScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: driftPeriod,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.drifts) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_started) {
      _started = true;
      _drift.forward(from: 0);
    }
  }

  bool _started = false;

  /// A touch wakes the drift for one more breath.
  void _wake() {
    if (widget.drifts &&
        !_drift.isAnimating &&
        !MediaQuery.disableAnimationsOf(context)) {
      _drift.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final palette = GroundPalette.of(
      tokens,
      GroundTone.dark,
      tokens.layerColors.first,
    );
    return AmbientScope(
      palette: palette,
      drift: widget.drifts ? _drift : null,
      child: Scaffold(
        backgroundColor: palette.ground,
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _wake(),
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: MistGroundPainter(
                      palette: palette,
                      drift: widget.drifts ? _drift : null,
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    if (widget.showHeader)
                      _Header(title: widget.title, actions: widget.actions),
                    if (widget.below != null) widget.below!,
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ground and two very faint lights that drift slowly: a gold one at the
/// top and a cool one at the bottom. The strongest light is a 9 % gold, so
/// text on the ground keeps its contrast (tested).
class MistGroundPainter extends CustomPainter {
  MistGroundPainter({required this.palette, this.drift})
    : super(repaint: drift);

  /// The strongest alpha of the gold light; the contrast test uses it.
  static const goldAlpha = .09;

  /// The strongest alpha of the cool light.
  static const coolAlpha = .05;

  final GroundPalette palette;
  final Animation<double>? drift;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = breathPhase(drift);
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.ground);
    void light(Offset center, double radius, Color color) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    light(
      Offset(
        size.width * (.2 + .07 * math.sin(phase)),
        size.height * (.1 + .04 * math.cos(phase)),
      ),
      size.width * .95,
      palette.accent.withValues(alpha: goldAlpha),
    );
    light(
      Offset(
        size.width * (.88 - .06 * math.cos(phase)),
        size.height * (.9 - .03 * math.sin(phase)),
      ),
      size.width * .85,
      palette.text.withValues(alpha: coolAlpha),
    );
  }

  @override
  bool shouldRepaint(MistGroundPainter old) =>
      old.palette != palette || old.drift != drift;
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.actions});

  final String? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    final canPop = Navigator.canPop(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
      child: Row(
        children: [
          if (canPop)
            Tooltip(
              message: 'Back',
              excludeFromSemantics: true,
              child: RoundIconButton(
                icon: Icons.arrow_back_rounded,
                label: 'Back',
                onPressed: () => Navigator.maybePop(context),
              ),
            )
          else
            const SizedBox(width: Space.md),
          const SizedBox(width: Space.md),
          Expanded(
            child: title == null
                ? const SizedBox.shrink()
                : Semantics(
                    header: true,
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: roundText(
                        context,
                        color: palette.text,
                        size: TypeScale.title,
                        serif: true,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A section header: a small gold light and a tracked-out label, on the
/// ground.
class RoundSectionHeader extends StatelessWidget {
  const RoundSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    return Semantics(
      header: true,
      label: title,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            CustomPaint(
              size: const Size.square(14),
              painter: _MarkPainter(palette.accent),
            ),
            const SizedBox(width: Space.md),
            Text(
              title.toUpperCase(),
              style: roundText(
                context,
                color: palette.muted,
                size: TypeScale.caption,
                weight: FontWeight.w600,
                spacing: 2.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas
      ..drawCircle(
        c,
        6,
        Paint()
          ..color = accent.withValues(alpha: .4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawCircle(c, 3, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.accent != accent;
}
