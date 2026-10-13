import 'package:flutter/material.dart';
import 'package:synesterra_core/synesterra_core.dart';

import '../instrument_mist/mist_spec.dart';
import '../theme/ambient_scope.dart';
import '../theme/synesterra_theme.dart';
import 'radar_painter.dart';

/// A small, still radar of an instrument's traits for lists and cards: the
/// same painters as the editor's radar, without labels, handles or motion.
/// The traits are read with `traitsForInstrument`, so for a sound not made on
/// the radar the shape is approximate. Decorative: hidden from screen
/// readers (the card reads the name).
class InstrumentRadarThumbnail extends StatefulWidget {
  const InstrumentRadarThumbnail({
    super.key,
    required this.instrument,
    this.size = 56,
  });

  final Instrument instrument;
  final double size;

  @override
  State<InstrumentRadarThumbnail> createState() =>
      _InstrumentRadarThumbnailState();
}

class _InstrumentRadarThumbnailState extends State<InstrumentRadarThumbnail> {
  // Reading the traits back is a small search; do it once per instrument,
  // not on every rebuild.
  late List<double> _values = _read(widget.instrument);
  late int _colorIndex = buildMistSpec(widget.instrument).colorIndex;

  static List<double> _read(Instrument instrument) {
    final traits = traitsForInstrument(instrument);
    return [for (final d in traits.definitions) traits[d.id]];
  }

  @override
  void didUpdateWidget(InstrumentRadarThumbnail old) {
    super.didUpdateWidget(old);
    if (old.instrument != widget.instrument) {
      _values = _read(widget.instrument);
      _colorIndex = buildMistSpec(widget.instrument).colorIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    final color = SynesterraTokens.of(context).layerColors[_colorIndex];
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: RadarFieldPainter(
            palette: palette,
            count: _values.length,
            labelBox: Size.zero,
          ),
          foregroundPainter: RadarShapePainter(
            values: _values,
            palette: palette,
            color: color,
            handles: false,
            labelBox: Size.zero,
          ),
        ),
      ),
    );
  }
}
