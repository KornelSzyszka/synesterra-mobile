import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/instrument_mist/instrument_mist.dart';
import '../../shared/instrument_mist/mist_spec.dart';
import '../../shared/theme/ambient_scope.dart';
import '../../shared/theme/design_scale.dart';
import '../../shared/theme/round_shapes.dart';
import '../../shared/theme/surfaces.dart';
import '../../shared/theme/synesterra_theme.dart';
import '../../shared/widgets/round_components.dart';

/// The Blend: visual language v2 as one style, built from the shared round
/// components. Glass for what floats over the mist (the transport bar, the
/// sheet, the vessel of a card), organic for shapes (the pad, the card),
/// tactile for what you press (Play, chips, the segmented control, the
/// slider). Reads its palette, drift and tap effect from the [AmbientScope]
/// the lab puts around it.
class BlendCanvas extends StatelessWidget {
  const BlendCanvas({
    super.key,
    required this.instrument,
    required this.dot,
    required this.onDot,
    required this.view,
    required this.onView,
    required this.level,
    required this.onLevel,
    required this.tags,
    required this.onTag,
    required this.playing,
    required this.looping,
    required this.onPlay,
    required this.onStop,
    required this.onLoop,
    required this.onOpenSheet,
  });

  final Instrument instrument;
  final Offset dot;
  final ValueChanged<Offset> onDot;
  final String view;
  final ValueChanged<String> onView;
  final double level;
  final ValueChanged<double> onLevel;
  final Set<String> tags;
  final ValueChanged<String> onTag;
  final bool playing;
  final bool looping;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onLoop;
  final VoidCallback onOpenSheet;

  static const tagline =
      'Light that floats, forms that breathe, gold to touch.';

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    const gap = SizedBox(height: Space.xxl);
    const small = SizedBox(height: Space.lg);
    return LayoutBuilder(
      builder: (context, constraints) {
        final padSize = (constraints.maxWidth - 2 * Space.xxl).clamp(
          160.0,
          300.0,
        );
        return ListView(
          key: const Key('lab-canvas'),
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, 0),
          children: [
            Text(
              tagline,
              key: const Key('lab-tagline'),
              textAlign: TextAlign.center,
              style: roundText(
                context,
                color: palette.muted,
                size: TypeScale.bodyLarge,
                serif: true,
              ),
            ),
            gap,
            const BlendHeader('Instrument'),
            small,
            Center(
              child: BlendPad(
                key: const Key('lab-pad'),
                instrument: instrument,
                dot: dot,
                size: padSize,
                onChanged: onDot,
              ),
            ),
            const SizedBox(height: Space.xl),
            RoundSegmented<String>(
              key: const Key('lab-segmented'),
              options: const [
                ('Mist', 'Mist'),
                ('Figure', 'Figure'),
                ('Wave', 'Wave'),
              ],
              value: view,
              onChanged: onView,
            ),
            small,
            RoundSlider(
              key: const Key('lab-slider'),
              label: 'Level',
              value: level,
              onChanged: onLevel,
            ),
            small,
            Wrap(
              key: const Key('lab-chips'),
              spacing: Space.md,
              children: [
                for (final tag in const ['bell', 'metal', 'bright'])
                  TactileChip(
                    key: ValueKey('lab-chip-$tag'),
                    label: tag,
                    selected: tags.contains(tag),
                    onPressed: () => onTag(tag),
                  ),
              ],
            ),
            gap,
            const BlendHeader('Library'),
            small,
            _BlendCard(instrument: instrument),
            gap,
            const BlendHeader('Transport'),
            small,
            GlassPanel(
              key: const Key('lab-transport'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  RoundIconButton(
                    key: const Key('lab-loop'),
                    icon: Icons.repeat_rounded,
                    label: 'Loop',
                    selected: looping,
                    onPressed: onLoop,
                  ),
                  const SizedBox(width: Space.md),
                  RoundActionButton(
                    key: const Key('lab-play'),
                    icon: playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    label: playing ? 'Pause' : 'Play',
                    onPressed: onPlay,
                  ),
                  const SizedBox(width: Space.md),
                  RoundIconButton(
                    key: const Key('lab-stop'),
                    icon: Icons.stop_rounded,
                    label: 'Stop',
                    onPressed: onStop,
                  ),
                  const Spacer(),
                  ExcludeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '96',
                          style: roundText(
                            context,
                            color: textOn(context, SurfaceStyle.glass),
                            size: TypeScale.headline,
                            serif: true,
                          ),
                        ),
                        Text(
                          'bpm',
                          style: roundText(
                            context,
                            color: mutedTextOn(context, SurfaceStyle.glass),
                            size: TypeScale.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                ],
              ),
            ),
            gap,
            const BlendHeader('Sheet'),
            Align(
              alignment: Alignment.centerLeft,
              child: TactileChip(
                key: const Key('lab-open-sheet'),
                label: 'Open as sheet',
                onPressed: onOpenSheet,
              ),
            ),
            small,
            BlendSheet(
              key: const Key('lab-sheet'),
              inline: true,
              onKeep: () {},
              onDismiss: () {},
            ),
          ],
        );
      },
    );
  }
}

/// A section header: a small gold light and a tracked-out label.
class BlendHeader extends StatelessWidget {
  const BlendHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    return Semantics(
      header: true,
      label: title,
      excludeSemantics: true,
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

/// A library item: the instrument's mist in a glass vessel inside an organic
/// card, its name and kind, and a quiet Play.
class _BlendCard extends StatelessWidget {
  const _BlendCard({required this.instrument});

  final Instrument instrument;

  @override
  Widget build(BuildContext context) {
    return OrganicCard(
      key: const Key('lab-card'),
      label: 'Open ${instrument.name}. Instrument · 3 tags',
      onTap: () {},
      child: Row(
        children: [
          SizedBox.square(
            dimension: 64,
            child: RoundSurface(
              style: SurfaceStyle.glass,
              shape: RoundShape.circle,
              child: Center(
                child: InstrumentMist(instrument: instrument, size: 52),
              ),
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    instrument.name,
                    style: roundText(
                      context,
                      color: textOn(context, SurfaceStyle.organic),
                      size: TypeScale.title,
                      serif: true,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Instrument · 3 tags',
                    style: roundText(
                      context,
                      color: mutedTextOn(context, SurfaceStyle.organic),
                      size: TypeScale.caption,
                    ),
                  ),
                ],
              ),
            ),
          ),
          RoundIconButton(
            key: const Key('lab-card-play'),
            icon: Icons.play_arrow_rounded,
            label: 'Play ${instrument.name}',
            size: 44,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

/// The bottom sheet sample on glass with a lens top: a question with a quiet
/// and a gold answer. [inline] fades the preview's lower part into the
/// ground, so it does not end in a hard edge as a real sheet does at the
/// screen's bottom.
class BlendSheet extends StatelessWidget {
  const BlendSheet({
    super.key,
    required this.onKeep,
    required this.onDismiss,
    this.inline = false,
  });

  final VoidCallback onKeep;
  final VoidCallback onDismiss;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      Space.xl,
      Space.huge - Space.sm,
      Space.xl,
      inline ? Space.huge : Space.xl,
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Keep this sound?',
          style: roundText(
            context,
            color: textOn(context, SurfaceStyle.glass),
            size: TypeScale.title,
            serif: true,
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Bell goes to your library. You can shape it again later.',
          style: roundText(
            context,
            color: mutedTextOn(context, SurfaceStyle.glass),
          ),
        ),
        const SizedBox(height: Space.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TactileChip(
              key: const Key('lab-sheet-dismiss'),
              label: 'Not now',
              onPressed: onDismiss,
            ),
            const SizedBox(width: Space.md),
            TactileChip(
              key: const Key('lab-sheet-keep'),
              label: 'Keep',
              primary: true,
              onPressed: onKeep,
            ),
          ],
        ),
      ],
    );
    if (!inline) {
      return GlassPanel(
        shape: RoundShape.lens,
        padding: padding,
        child: content,
      );
    }
    // One static layer: the glass fades out over its bottom 30 %, the
    // content (above that) stays whole.
    return RepaintBoundary(
      child: CustomPaint(
        painter: _FadingGlassPainter(Surfaces(AmbientScope.paletteOf(context))),
        child: Padding(padding: padding, child: content),
      ),
    );
  }
}

class _FadingGlassPainter extends CustomPainter {
  const _FadingGlassPainter(this.surfaces);

  final Surfaces surfaces;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bounds = rect.inflate(24);
    canvas.saveLayer(bounds, Paint());
    surfaces.paint(
      canvas,
      RoundShape.lens.outline(rect),
      rect,
      SurfaceStyle.glass,
    );
    canvas
      ..drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0, .7, 1],
          ).createShader(rect),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_FadingGlassPainter old) =>
      old.surfaces.palette != surfaces.palette;
}

/// The Blend's circular instrument pad (the lab's own painter, not the real
/// pad): an organic pond that breathes slowly, the instrument mist inside,
/// a glass rim over it, and a gold light at [dot] with a glass glint.
class BlendPad extends StatelessWidget {
  const BlendPad({
    super.key,
    required this.instrument,
    required this.dot,
    required this.onChanged,
    this.size = 280,
  });

  final Instrument instrument;

  /// -1..1 in both axes, inside the unit circle.
  final Offset dot;
  final ValueChanged<Offset> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final spec = buildMistSpec(instrument);
    final color = tokens.layerColors[spec.colorIndex];
    void set(Offset local) {
      var p = (local - Offset(size / 2, size / 2)) / (size / 2 * .8);
      if (p.distance > 1) p = p / p.distance;
      onChanged(p);
    }

    final brightness = ((dot.dx + 1) / 2 * 100).round();
    final hardness = ((1 - dot.dy) / 2 * 100).round();
    return Semantics(
      label: 'Sound pad',
      value: 'Brightness $brightness %, hardness $hardness %',
      hint: 'Drag the light to shape the sound',
      excludeSemantics: true,
      child: GestureDetector(
        onPanDown: (details) => set(details.localPosition),
        onPanUpdate: (details) => set(details.localPosition),
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(size),
            painter: _BlendPadPainter(
              surfaces: Surfaces(AmbientScope.paletteOf(context)),
              dot: dot,
              drift: AmbientScope.driftOf(context),
              mist: MistPainter(spec: spec, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlendPadPainter extends CustomPainter {
  _BlendPadPainter({
    required this.surfaces,
    required this.dot,
    required this.mist,
    this.drift,
  }) : super(repaint: drift);

  final Surfaces surfaces;
  final Offset dot;
  final MistPainter mist;
  final Animation<double>? drift;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = surfaces.palette;
    final rect = Offset.zero & size;
    final breath = breathPhase(drift);
    final pond = blobPath(
      rect,
      seed: 5,
      amount: BlobAmount.still * .6,
      phase: breath,
    );
    surfaces.paint(canvas, pond, rect, SurfaceStyle.organic);
    final square = rect.deflate(rect.width * .04);
    canvas
      ..save()
      ..clipPath(pond)
      ..translate(square.left, square.top);
    mist.paint(canvas, square.size);
    canvas.restore();
    surfaces
      ..paintHighlight(canvas, pond, rect)
      ..paintRim(canvas, pond, rect);

    final at = rect.center + Offset(dot.dx, dot.dy) * (rect.width / 2 * .8);
    canvas
      ..drawCircle(
        at,
        22,
        Paint()
          ..color = palette.accent.withValues(
            alpha: .34 + .14 * math.sin(breath),
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      ..drawCircle(
        at,
        19,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.accent.withValues(alpha: .26),
      );
    final light = Rect.fromCircle(center: at, radius: 9);
    canvas
      ..drawCircle(
        at,
        9,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.3, -.3),
            colors: [
              Color.lerp(palette.accent, palette.light, .4)!,
              palette.accent,
            ],
          ).createShader(light),
      )
      ..drawCircle(
        at + const Offset(-2.5, -2.5),
        2.2,
        Paint()..color = palette.light.withValues(alpha: .85),
      );
  }

  @override
  bool shouldRepaint(_BlendPadPainter old) =>
      old.dot != dot ||
      old.drift != drift ||
      old.surfaces.palette != surfaces.palette ||
      old.mist.spec != mist.spec ||
      old.mist.color != mist.color;
}
