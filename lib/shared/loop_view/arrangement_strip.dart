import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/design_scale.dart';
import '../theme/synesterra_theme.dart';
import 'position_source.dart';
import 'source_semantics.dart';

/// One section of the arrangement as the strip shows it.
@immutable
class StripSection {
  StripSection({
    required this.label,
    required this.repeats,
    this.missing = false,
  }) {
    if (repeats < 1 || repeats > 32) {
      throw ArgumentError.value(repeats, 'repeats', 'must be in 1..32');
    }
  }

  final String label;

  /// Cycles the section plays, 1..32.
  final int repeats;

  /// The section's loop is gone: shown and marked, never played.
  final bool missing;

  @override
  bool operator ==(Object other) =>
      other is StripSection &&
      label == other.label &&
      repeats == other.repeats &&
      missing == other.missing;

  @override
  int get hashCode => Object.hash(label, repeats, missing);
}

/// How far through a section of [repeats] cycles the position is, in 0..1.
/// [LoopPosition.cycleIndex] counts cycles since the section began; taking it
/// modulo [repeats] also keeps a restarted section sane.
double sectionProgress(LoopPosition position, int repeats) {
  if (!position.playing || repeats < 1) return 0;
  return ((position.cycleIndex % repeats) + position.cyclePosition) / repeats;
}

/// A strip of sections with the current one (`sectionIndex` of the source)
/// highlighted and its progress through its repeats filled in.
class ArrangementStrip extends StatelessWidget {
  const ArrangementStrip({
    super.key,
    required this.sections,
    required this.source,
  });

  final List<StripSection> sections;
  final PositionSource source;

  String _label(LoopPosition p) {
    final count = sections.length;
    final index = p.sectionIndex;
    if (!p.playing || index == null || index < 0 || index >= count) {
      return 'Arrangement of $count sections, ${p.playing ? 'playing' : 'not playing'}.';
    }
    final section = sections[index];
    return 'Section ${index + 1} of $count, ${section.label}, '
        'cycle ${(p.cycleIndex % section.repeats) + 1} of ${section.repeats}.';
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    return SourceSemantics(
      source: source,
      label: _label,
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('arrangement-strip-canvas'),
          size: const Size.fromHeight(Space.xxl + Space.md),
          painter: ArrangementStripPainter(
            sections: sections,
            source: source,
            tokens: SynesterraTokens.of(context),
            labelStyle: TextStyle(
              fontFamily: SynesterraFonts.monospace(platform),
              fontFamilyFallback: SynesterraFonts.monospaceFallback(platform),
              fontSize: TypeScale.caption,
            ),
          ),
          child: const SizedBox(
            width: double.infinity,
            height: Space.xxl + Space.md,
          ),
        ),
      ),
    );
  }
}

class ArrangementStripPainter extends CustomPainter {
  ArrangementStripPainter({
    required this.sections,
    required this.source,
    required this.tokens,
    required this.labelStyle,
  }) : super(repaint: source);

  final List<StripSection> sections;
  final PositionSource source;
  final SynesterraTokens tokens;
  final TextStyle labelStyle;

  /// The top and bottom of a section's capsule.
  static (Color, Color) capsuleStops(SynesterraTokens tokens) => (
    Color.lerp(tokens.surface, Colors.white, .045)!,
    Color.lerp(tokens.surface, Colors.black, .18)!,
  );

  /// Alpha of the gold progress over the current section.
  static const progressAlpha = .24;

  /// Every opaque colour a section's label can sit on: the capsule's
  /// gradient and, for the [current] section, also the gold progress over
  /// it. A missing section is skipped, so it is never current.
  static List<Color> labelGrounds(
    SynesterraTokens tokens, {
    required bool current,
  }) {
    final (top, bottom) = capsuleStops(tokens);
    final plain = [top, Color.lerp(top, bottom, .5)!, bottom];
    return [
      ...plain,
      if (current)
        for (final c in plain)
          Color.alphaBlend(tokens.accent.withValues(alpha: progressAlpha), c),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (sections.isEmpty) return;
    final (top, bottom) = capsuleStops(tokens);
    final position = source.value;
    final totalRepeats = sections.fold<int>(0, (sum, s) => sum + s.repeats);
    final room = size.width - Space.xs * (sections.length - 1);
    var x = 0.0;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final width = room * section.repeats / totalRepeats;
      final rect = Rect.fromLTWH(x, 0, width, size.height);
      // A capsule per section (a circle when narrow), lit from the top.
      final capsule = RRect.fromRectAndRadius(
        rect,
        Radius.circular(math.min(rect.width, rect.height) / 2),
      );
      final current = position.playing && position.sectionIndex == i;
      if (current) {
        canvas.drawRRect(
          capsule,
          Paint()
            ..color = tokens.accent.withValues(alpha: .28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      canvas.drawRRect(
        capsule,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ).createShader(rect),
      );
      if (current) {
        canvas.save();
        canvas.clipRRect(capsule);
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            0,
            width * sectionProgress(position, section.repeats),
            size.height,
          ),
          Paint()..color = tokens.accent.withValues(alpha: progressAlpha),
        );
        canvas.restore();
      }
      canvas.drawRRect(
        capsule,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = current ? 1.6 : 1
          ..color = current
              ? tokens.accent
              : Colors.white.withValues(alpha: .08),
      );
      final inset = math.max(Space.md, math.min(capsule.tlRadiusX * .62, 18.0));
      final text = TextPainter(
        text: TextSpan(
          text:
              '${(i + 1).toString().padLeft(2, '0')} ${section.label}'
              '${section.missing ? ' (missing)' : ''}\n×${section.repeats}',
          style: labelStyle.copyWith(
            // The current section shows by its gold rim, fill and glow; its
            // label stays in the text colour (gold text on the gold fill
            // fell to 3.9:1 on Autumn).
            color: section.missing ? tokens.muted : tokens.text,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: math.max(1, width - inset * 2));
      text.paint(canvas, Offset(x + inset, (size.height - text.height) / 2));
      x += width + Space.xs;
    }
  }

  @override
  bool shouldRepaint(covariant ArrangementStripPainter oldDelegate) =>
      !listEquals(oldDelegate.sections, sections) ||
      oldDelegate.source != source ||
      oldDelegate.tokens != tokens ||
      oldDelegate.labelStyle != labelStyle;
}
