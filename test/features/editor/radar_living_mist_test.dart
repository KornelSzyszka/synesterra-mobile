import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/instrument_radar/radar_painter.dart';

import 'instrument_radar_screen_test.dart'
    show at, open, painter, radarKey, audition;

void main() {
  testWidgets('the mist leans toward the dragging finger, pulses on the '
      'audition after the release, then comes to rest', (tester) async {
    await open(tester);
    final mist = painter<RadarGlowPainter>(tester).motion!;
    expect(mist.resting, isTrue, reason: 'a settled editor is still');

    final gesture = await tester.startGesture(at(tester, 0, .5));
    await gesture.moveTo(at(tester, 0, .9));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final centre = tester.getCenter(find.byKey(radarKey));
    final toward = at(tester, 0, .9) - centre;
    final lean = mist.lean;
    expect(lean.dx * toward.dx + lean.dy * toward.dy, greaterThan(0));
    expect(mist.hold, greaterThan(.5));

    final played = audition.played.length;
    await gesture.up();
    await tester.pump();
    expect(audition.played.length, greaterThan(played));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(mist.pulse, greaterThan(0), reason: 'the audition pulses it');

    await tester.pumpAndSettle();
    expect(mist.resting, isTrue);
    expect(mist.lean, Offset.zero);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('under reduce motion the mist does not move', (tester) async {
    await open(tester, reduceMotion: true);
    expect(painter<RadarGlowPainter>(tester).motion, isNull);
    await tester.tapAt(at(tester, 0, .5));
    await tester.pumpAndSettle();
    expect(painter<RadarGlowPainter>(tester).motion, isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
