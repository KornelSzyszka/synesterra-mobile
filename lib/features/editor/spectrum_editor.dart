import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../shared/theme/synesterra_theme.dart';
import 'spectrum_geometry.dart';

/// A pan recognizer that wins the gesture at once, so touching the chart
/// draws instead of scrolling the page it sits in.
class _ImmediatePanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

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

  static const chartHeight = 150.0;
  static const labelHeight = 20.0;

  @override
  State<SpectrumEditor> createState() => _SpectrumEditorState();
}

class _SpectrumEditorState extends State<SpectrumEditor> {
  int? _lastIndex;
  double _lastAmplitude = 0;

  void _touch(Offset position, double width, {required bool stroke}) {
    final count = widget.amplitudes.length;
    final index = barIndexAt(position.dx, width, count);
    final amplitude = amplitudeAt(position.dy, SpectrumEditor.chartHeight);
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
          return RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _ImmediatePanRecognizer:
                  GestureRecognizerFactoryWithHandlers<_ImmediatePanRecognizer>(
                    _ImmediatePanRecognizer.new,
                    (recognizer) {
                      recognizer.onDown = (details) {
                        _touch(details.localPosition, width, stroke: false);
                      };
                      recognizer.onUpdate = (details) {
                        _touch(details.localPosition, width, stroke: true);
                      };
                      recognizer.onEnd = (_) => _end();
                      recognizer.onCancel = _end;
                    },
                  ),
            },
            child: CustomPaint(
              key: const Key('spectrum-chart'),
              size: Size(
                width,
                SpectrumEditor.chartHeight + SpectrumEditor.labelHeight,
              ),
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
    const chartHeight = SpectrumEditor.chartHeight;
    final count = amplitudes.length;
    final slot = size.width / count;
    final barWidth = slot * 0.7;

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
        const Radius.circular(2),
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
          style: TextStyle(color: labelColor, fontSize: 10),
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
