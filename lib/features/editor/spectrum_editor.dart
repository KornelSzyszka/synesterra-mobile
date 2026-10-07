import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/design_scale.dart';
import '../../shared/theme/synesterra_theme.dart';
import 'immediate_pan.dart';
import 'spectrum_geometry.dart';

/// One bar per harmonic, shaped with a finger: touch or drag across bars to
/// set their heights. Marks show each harmonic after the EQ.
class SpectrumEditor extends StatefulWidget {
  const SpectrumEditor({
    super.key,
    required this.amplitudes,
    required this.shaped,
    required this.selected,
    required this.color,
    required this.onChange,
    required this.onChangeEnd,
  });

  /// The recipe: 0..1 per harmonic.
  final List<double> amplitudes;

  /// Each harmonic after the EQ at the test note, drawn as a mark.
  final List<double> shaped;
  final int selected;
  final Color color;

  /// Bars changed by a touch or a stroke, with the bar to select.
  final void Function(Map<int, double> changes, int select) onChange;

  /// The finger was lifted.
  final VoidCallback onChangeEnd;

  /// A golden rectangle (`width / φ`) is a generous surface to draw on.
  static double chartHeightFor(double width) =>
      math.min(260.0, math.max(120.0, goldenHeight(width)));

  static const labelHeight = 20.0;

  @override
  State<SpectrumEditor> createState() => _SpectrumEditorState();
}

class _SpectrumEditorState extends State<SpectrumEditor> {
  int? _lastIndex;
  double _lastAmplitude = 0;

  void _touch(
    Offset position,
    double width,
    double height, {
    required bool stroke,
  }) {
    final count = widget.amplitudes.length;
    final index = barIndexAt(position.dx, width, count);
    final amplitude = amplitudeAt(position.dy, height);
    final last = _lastIndex;
    final changes = stroke && last != null
        ? strokeBetween(last, _lastAmplitude, index, amplitude)
        : {index: amplitude};
    _lastIndex = index;
    _lastAmplitude = amplitude;
    widget.onChange(changes, index);
  }

  void _end() {
    _lastIndex = null;
    widget.onChangeEnd();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SynesterraTokens.of(context);
    final count = widget.amplitudes.length;
    return Semantics(
      container: true,
      label:
          'Spectrum of $count harmonics. Drag across the bars to draw, or '
          'use the slider below for the selected harmonic.',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = SpectrumEditor.chartHeightFor(width);
          return ImmediatePanDetector(
            onDown: (position) =>
                _touch(position, width, height, stroke: false),
            onUpdate: (position) =>
                _touch(position, width, height, stroke: true),
            onEnd: _end,
            child: CustomPaint(
              key: const Key('spectrum-chart'),
              size: Size(width, height + SpectrumEditor.labelHeight),
              painter: _SpectrumPainter(
                amplitudes: widget.amplitudes,
                shaped: widget.shaped,
                selected: widget.selected,
                color: widget.color,
                gridColor: tokens.border,
                labelColor: tokens.muted,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required this.amplitudes,
    required this.shaped,
    required this.selected,
    required this.color,
    required this.gridColor,
    required this.labelColor,
  });

  final List<double> amplitudes;
  final List<double> shaped;
  final int selected;
  final Color color;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final chartHeight = size.height - SpectrumEditor.labelHeight;
    final count = amplitudes.length;
    final slot = size.width / count;
    // Bars have a limit, so a few harmonics are bars and not wide blocks.
    final barWidth = math.min(slot * 0.7, 28.0);

    for (final fraction in const [0.0, 0.5, 1.0]) {
      final y = chartHeight * (1 - fraction);
      canvas.drawLine(
        Offset(0, _clamp(y, 0.5, chartHeight - 0.5)),
        Offset(size.width, _clamp(y, 0.5, chartHeight - 0.5)),
        Paint()
          ..color = gridColor
          ..strokeWidth = 1,
      );
    }

    for (var i = 0; i < count; i++) {
      final left = slot * i + (slot - barWidth) / 2;
      final height = amplitudes[i] * chartHeight;
      final isSelected = i == selected;
      final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, chartHeight - height, barWidth, height),
        const Radius.circular(Radii.xs),
      );
      canvas.drawRRect(
        bar,
        Paint()..color = color.withValues(alpha: isSelected ? 0.95 : 0.6),
      );
      if (isSelected) {
        canvas.drawRRect(
          bar.inflate(1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color,
        );
      }
      // The harmonic after EQ, capped at the top of the chart.
      if (i < shaped.length) {
        final markY = chartHeight - _clamp(shaped[i], 0, 1) * chartHeight;
        canvas.drawLine(
          Offset(left - 1, markY),
          Offset(left + barWidth + 1, markY),
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: 0.85),
        );
      }
    }

    final everyBar = count <= 16;
    for (var i = 0; i < count; i++) {
      final number = i + 1;
      if (!everyBar && number != 1 && number % 8 != 0) continue;
      final text = TextPainter(
        text: TextSpan(
          text: '$number',
          style: TextStyle(color: labelColor, fontSize: TypeScale.overline),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset(slot * i + (slot - text.width) / 2, chartHeight + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) =>
      old.amplitudes != amplitudes ||
      old.shaped != shaped ||
      old.selected != selected ||
      old.color != color;
}

double _clamp(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);
