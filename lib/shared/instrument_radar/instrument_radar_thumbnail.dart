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
class InstrumentRadarThumbnail extends StatelessWidget {
  const InstrumentRadarThumbnail({
    super.key,
    required this.instrument,
    this.size = 56,
  });

  final Instrument instrument;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AmbientScope.paletteOf(context);
    final color = SynesterraTokens.of(context)
        .layerColors[buildMistSpec(instrument).colorIndex];
    final traits = traitsForInstrument(instrument);
    final values = [for (final d in traits.definitions) traits[d.id]];
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: RadarFieldPainter(
            palette: palette,
            count: values.length,
            labelBox: Size.zero,
          ),
          foregroundPainter: RadarShapePainter(
            values: values,
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
