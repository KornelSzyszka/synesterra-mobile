import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import 'curve_geometry.dart';
import 'immediate_pan.dart';

/// The EQ as a response graph with three handles, one per band, at the fixed
/// corner frequencies; dragging a handle up or down sets that band's gain.
/// The curve is the real response (`eqResponseDb`). Faint ticks mark where
/// the harmonics of the test note fall.
class EqEditor extends StatefulWidget {
  const EqEditor({
    super.key,
    required this.eq,
    required this.testHz,
    required this.color,
    required this.onChange,
    required this.onChangeEnd,
  });

  final InstrumentEq eq;

  /// The root of the test sound; its harmonics are marked on the graph.
  final double testHz;
  final Color color;

  /// A handle was dragged; the new EQ.
  final ValueChanged<InstrumentEq> onChange;

  /// The finger was lifted.
  final VoidCallback onChangeEnd;

  /// A golden rectangle (`width / φ`).
  static double graphHeightFor(double width) =>
      math.min(260.0, math.max(140.0, goldenHeight(width)));

  static const labelHeight = 22.0;

  @override
  State<EqEditor> createState() => _EqEditorState();
}

enum _Band { low, mid, high }

const _corners = {
  _Band.low: InstrumentEq.lowShelfHz,
  _Band.mid: InstrumentEq.midPeakHz,
  _Band.high: InstrumentEq.highShelfHz,
};

double _gain(InstrumentEq eq, _Band band) => switch (band) {
  _Band.low => eq.lowDb,
  _Band.mid => eq.midDb,
  _Band.high => eq.highDb,
};

class _EqEditorState extends State<EqEditor> {
  _Band? _active;

  List<Offset> _handles(double width, double height) => [
    for (final band in _Band.values)
      Offset(
        hzToX(_corners[band]!, width),
        dbToY(_gain(widget.eq, band), height),
      ),
  ];

  void _down(Offset position, double width, double height) {
    final picked = nearestHandle(position, _handles(width, height));
    _active = picked == null ? null : _Band.values[picked];
  }

  void _move(Offset position, double height) {
    final band = _active;
    if (band == null) return;
    final db = yToDb(position.dy, height);
    widget.onChange(switch (band) {
      _Band.low => widget.eq.copyWith(lowDb: db),
      _Band.mid => widget.eq.copyWith(midDb: db),
      _Band.high => widget.eq.copyWith(highDb: db),
    });
  }

  void _end() {
    final wasDragging = _active != null;
    _active = null;
    if (wasDragging) widget.onChangeEnd();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final eq = widget.eq;
    return Semantics(
      container: true,
      label:
          'EQ graph. Low ${eq.lowDb} decibels, mid ${eq.midDb}, high '
          '${eq.highDb}. Drag the three handles up or down, or use the '
          'sliders below.',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = EqEditor.graphHeightFor(width);
          return ImmediatePanDetector(
            onDown: (position) => _down(position, width, height),
            onUpdate: (position) => _move(position, height),
            onEnd: _end,
            child: CustomPaint(
              key: const Key('eq-graph'),
              size: Size(width, height + EqEditor.labelHeight),
              painter: _EqPainter(
                eq: eq,
                testHz: widget.testHz,
                color: widget.color,
                gridColor: tokens.border,
                labelColor: tokens.muted,
                handleFill: tokens.background,
                active: _active,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EqPainter extends CustomPainter {
  _EqPainter({
    required this.eq,
    required this.testHz,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.handleFill,
    required this.active,
  });

  final InstrumentEq eq;
  final double testHz;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final Color handleFill;
  final _Band? active;

  void _text(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: TypeScale.overline),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(at.dx - painter.width / 2, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final height = size.height - EqEditor.labelHeight;
    final width = size.width;

    // Gain grid: +12, 0 and -12 dB, with 0 dB the strongest.
    for (final db in const [12.0, 0.0, -12.0]) {
      final y = dbToY(db, height).clamp(0.5, height - 0.5);
      canvas.drawLine(
        Offset(0, y),
        Offset(width, y),
        Paint()
          ..color = db == 0 ? gridColor : gridColor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }

    // Where the harmonics of the test note fall.
    for (var n = 1; n <= Instrument.maxHarmonics; n++) {
      final hz = testHz * n;
      if (hz > eqMaxHz) break;
      final x = hzToX(hz, width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, height),
        Paint()
          ..color = color.withValues(alpha: n == 1 ? 0.5 : 0.18)
          ..strokeWidth = n == 1 ? 1.5 : 1,
      );
    }

    // Frequency labels.
    for (final (hz, label) in const [
      (100.0, '100'),
      (1000.0, '1k'),
      (10000.0, '10k'),
    ]) {
      _text(canvas, label, Offset(hzToX(hz, width), height + 5));
    }

    // The real response.
    const steps = 200;
    final curve = Path();
    for (var i = 0; i <= steps; i++) {
      final x = width * i / steps;
      final y = dbToY(eqResponseDb(eq, xToHz(x, width)), height);
      if (i == 0) {
        curve.moveTo(x, y);
      } else {
        curve.lineTo(x, y);
      }
    }
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    // One handle per band, at its corner frequency and gain.
    for (final band in _Band.values) {
      final gain = _gain(eq, band);
      final centre = Offset(hzToX(_corners[band]!, width), dbToY(gain, height));
      final zero = Offset(centre.dx, dbToY(0, height));
      canvas.drawLine(
        zero,
        centre,
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = 1.5,
      );
      final isActive = active == band;
      canvas.drawCircle(centre, isActive ? 12 : 9, Paint()..color = handleFill);
      canvas.drawCircle(
        centre,
        isActive ? 12 : 9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color,
      );
      final label =
          '${band.name[0].toUpperCase()}${band.name.substring(1)} '
          '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}';
      final above = gain < 6;
      _text(
        canvas,
        label,
        Offset(
          centre.dx.clamp(26.0, width - 26),
          above ? centre.dy - 24 : centre.dy + 12,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqPainter old) =>
      old.eq != eq ||
      old.testHz != testHz ||
      old.color != color ||
      old.active != active;
}
