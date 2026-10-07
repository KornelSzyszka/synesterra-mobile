import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import 'curve_geometry.dart';
import 'immediate_pan.dart';

/// The envelope as a graph with two handles: the peak sets the attack, the
/// end sets the decay. The curve is the real envelope (`envelopeLevel`).
class EnvelopeEditor extends StatefulWidget {
  const EnvelopeEditor({
    super.key,
    required this.attackMs,
    required this.decayMs,
    required this.color,
    required this.onChange,
    required this.onChangeEnd,
  });

  final int attackMs;
  final int decayMs;
  final Color color;

  /// A handle was dragged; the new attack and decay in milliseconds.
  final void Function(int attackMs, int decayMs) onChange;

  /// The finger was lifted.
  final VoidCallback onChangeEnd;

  /// A flat golden rectangle (`width / φ²`).
  static double graphHeightFor(double width) =>
      math.min(200.0, math.max(96.0, flatGoldenHeight(width)));

  static const labelHeight = 22.0;

  @override
  State<EnvelopeEditor> createState() => _EnvelopeEditorState();
}

enum _Handle { peak, end }

class _EnvelopeEditorState extends State<EnvelopeEditor> {
  _Handle? _active;

  List<Offset> _handles(double width, double height) {
    final attack = widget.attackMs / 1000;
    final end = attack + widget.decayMs / 1000;
    return [
      Offset(envelopeTimeToX(attack, width), 0),
      Offset(envelopeTimeToX(end, width), height * (1 - envelopeFloor)),
    ];
  }

  void _down(Offset position, double width, double height) {
    final picked = nearestHandle(position, _handles(width, height));
    _active = picked == null ? null : _Handle.values[picked];
  }

  void _move(Offset position, double width) {
    final handle = _active;
    if (handle == null) return;
    final seconds = envelopeXToTime(position.dx, width);
    switch (handle) {
      case _Handle.peak:
        final attack = (seconds * 1000).round().clamp(
          0,
          Instrument.maxAttackMs,
        );
        widget.onChange(attack, widget.decayMs);
      case _Handle.end:
        final decay = (seconds * 1000).round() - widget.attackMs;
        widget.onChange(
          widget.attackMs,
          decay.clamp(Instrument.minDecayMs, Instrument.maxDecayMs),
        );
    }
  }

  void _end() {
    final wasDragging = _active != null;
    _active = null;
    if (wasDragging) widget.onChangeEnd();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    return Semantics(
      container: true,
      label:
          'Envelope graph. Attack ${widget.attackMs} milliseconds, decay '
          '${widget.decayMs} milliseconds. Drag the two handles, or use the '
          'sliders below.',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = EnvelopeEditor.graphHeightFor(width);
          return ImmediatePanDetector(
            onDown: (position) => _down(position, width, height),
            onUpdate: (position) => _move(position, width),
            onEnd: _end,
            child: CustomPaint(
              key: const Key('envelope-graph'),
              size: Size(width, height + EnvelopeEditor.labelHeight),
              painter: _EnvelopePainter(
                attackMs: widget.attackMs,
                decayMs: widget.decayMs,
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

class _EnvelopePainter extends CustomPainter {
  _EnvelopePainter({
    required this.attackMs,
    required this.decayMs,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.handleFill,
    required this.active,
  });

  final int attackMs;
  final int decayMs;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final Color handleFill;
  final _Handle? active;

  void _text(Canvas canvas, String text, Offset at, {bool centred = true}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: TypeScale.overline),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(centred ? at.dx - painter.width / 2 : at.dx, at.dy),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final height = size.height - EnvelopeEditor.labelHeight;
    final width = size.width;

    // Time ticks on the square-root axis.
    for (final (seconds, label) in const [
      (0.01, '10 ms'),
      (0.1, '100 ms'),
      (1.0, '1 s'),
      (5.0, '5 s'),
    ]) {
      final x = envelopeTimeToX(seconds, width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, height),
        Paint()
          ..color = gridColor.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      _text(canvas, label, Offset(_clamp(x, 14, width - 14), height + 5));
    }
    canvas.drawLine(
      Offset(0, height - 0.5),
      Offset(width, height - 0.5),
      Paint()
        ..color = gridColor
        ..strokeWidth = 1,
    );

    // The real envelope.
    const steps = 160;
    final curve = Path();
    for (var i = 0; i <= steps; i++) {
      final x = width * i / steps;
      final level = envelopeLevel(
        attackMs: attackMs,
        decayMs: decayMs,
        seconds: envelopeXToTime(x, width),
      );
      final y = height * (1 - level);
      if (i == 0) {
        curve.moveTo(x, y);
      } else {
        curve.lineTo(x, y);
      }
    }
    final fill = Path.from(curve)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    // Handles and their values.
    final attack = attackMs / 1000;
    final end = attack + decayMs / 1000;
    final peak = Offset(envelopeTimeToX(attack, width), 0);
    final tail = Offset(
      envelopeTimeToX(end, width),
      height * (1 - envelopeFloor),
    );
    for (final (handle, centre) in [
      (_Handle.peak, peak),
      (_Handle.end, tail),
    ]) {
      final isActive = active == handle;
      canvas.drawCircle(centre, isActive ? 12 : 9, Paint()..color = handleFill);
      canvas.drawCircle(
        centre,
        isActive ? 12 : 9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color,
      );
    }
    _text(
      canvas,
      '$attackMs ms',
      Offset(_clamp(peak.dx + 14, 0, width - 44), 6),
      centred: false,
    );
    _text(
      canvas,
      '$decayMs ms',
      Offset(_clamp(tail.dx - 50, 0, width - 44), height - 26),
      centred: false,
    );
  }

  @override
  bool shouldRepaint(covariant _EnvelopePainter old) =>
      old.attackMs != attackMs ||
      old.decayMs != decayMs ||
      old.color != color ||
      old.active != active;
}

double _clamp(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);
