import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/instrument_figure/instrument_sound_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra_core/synesterra_core.dart';

Future<void> pump(
  WidgetTester tester, {
  VoidCallback? onTap,
  int token = 0,
  Instrument? instrument,
  SynesterraPalette palette = SynesterraPalette.forest,
  bool reduceMotion = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: synesterraTheme(palette),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Center(
          child: InstrumentSoundView(
            instrument: instrument ?? factoryInstruments.last,
            testHz: 440,
            onTap: onTap,
            pulseToken: token,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('offers Mist, Figure and Wave and starts on Mist', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Mist'), findsOneWidget);
    expect(find.text('Figure'), findsOneWidget);
    expect(find.text('Wave'), findsOneWidget);
    expect(find.byKey(const Key('instrument-preview-mist')), findsOneWidget);
    expect(find.byKey(const Key('instrument-preview-figure')), findsNothing);
  });

  testWidgets('the switch segments are at least 48 dp tall', (tester) async {
    await pump(tester);
    final box = tester.getSize(find.byType(SegmentedButton<SoundView>));
    expect(box.height, greaterThanOrEqualTo(48));
  });

  testWidgets('switching shows the chosen view', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Figure'));
    await tester.pump();
    expect(find.byKey(const Key('instrument-preview-figure')), findsOneWidget);
    expect(find.byKey(const Key('instrument-preview-mist')), findsNothing);

    await tester.tap(find.text('Wave'));
    await tester.pump();
    expect(find.byKey(const Key('instrument-preview-wave')), findsOneWidget);

    await tester.tap(find.text('Mist'));
    await tester.pump();
    expect(find.byKey(const Key('instrument-preview-mist')), findsOneWidget);
  });

  testWidgets('tapping the preview calls onTap in every view', (tester) async {
    var taps = 0;
    await pump(tester, onTap: () => taps++);

    for (final view in ['Mist', 'Figure', 'Wave']) {
      await tester.tap(find.text(view));
      await tester.pump();
      await tester.tap(
        find.byKey(Key('instrument-preview-${view.toLowerCase()}')),
      );
    }
    expect(taps, 3);
  });

  testWidgets('without onTap a tap plays the pulse itself', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('instrument-preview-mist')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a new pulse token plays the pulse in each view', (tester) async {
    await pump(tester);
    var token = 0;
    for (final view in ['Mist', 'Figure', 'Wave']) {
      await tester.tap(find.text(view));
      await tester.pump();
      await pump(tester, token: ++token);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('with reduced motion nothing animates', (tester) async {
    await pump(tester, reduceMotion: true);
    await pump(tester, token: 1, reduceMotion: true);
    // Would time out in pumpAndSettle if an animation were running forever;
    // here it must settle immediately.
    await tester.pumpAndSettle(const Duration(milliseconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every view paints in every palette without errors', (
    tester,
  ) async {
    for (final palette in SynesterraPalette.values) {
      await pump(tester, palette: palette);
      for (final view in ['Figure', 'Wave', 'Mist']) {
        await tester.tap(find.text(view));
        await tester.pump();
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed recipe redraws the figure', (tester) async {
    await pump(tester, instrument: factoryInstruments[1]);
    await tester.tap(find.text('Figure'));
    await tester.pump();

    await pump(tester, instrument: factoryInstruments.last);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('instrument-preview-figure')), findsOneWidget);
  });

  testWidgets('the preview is announced as a button with its view name', (
    tester,
  ) async {
    await pump(tester);
    expect(
      find.bySemanticsLabel(RegExp(r'^Mist view of Bell')),
      findsOneWidget,
    );
  });
}
