import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/features/editor/instrument_radar_view.dart';
import 'package:synesterra/shared/instrument_radar/radar_geometry.dart';
import 'package:synesterra/shared/instrument_radar/radar_painter.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

void main() {
  testWidgets('a cancelled drag stops without a sound', (tester) async {
    var traits = InstrumentTraits.neutral();
    var releases = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.graphite),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => InstrumentRadar(
              traits: traits,
              color: Colors.teal,
              onChanged: (id, value) =>
                  setState(() => traits = traits.withValues({id: value})),
              onRelease: () => releases++,
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(InstrumentRadar));
    final reach = radarReach(rect.size, 6);
    Offset at(double value) =>
        radarPoint(0, 6, value, rect.size, reach) + rect.topLeft;
    RadarShapePainter shape() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<RadarShapePainter>()
        .single;

    final gesture = await tester.startGesture(at(0.5));
    await gesture.moveTo(at(0.8));
    await tester.pump();
    expect(shape().active, 0);
    expect(traits[TraitIds.brightness], greaterThan(0.6));

    await gesture.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(releases, 0, reason: 'an interrupted drag stays silent');
    expect(shape().active, isNull, reason: 'the drag has stopped');

    // The next real lift plays as usual.
    await tester.tapAt(at(traits[TraitIds.brightness]));
    await tester.pump(const Duration(seconds: 1));
    expect(releases, 1);
  });
}
