import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';
import 'package:synesterra/shared/widgets/design_components.dart';

void main() {
  testWidgets('stepper respects range and has 48 dp targets', (tester) async {
    var value = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.forest),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => NumberStepper(
              value: value,
              min: 1,
              max: 2,
              label: 'beats',
              color: SynesterraTokens.of(context).accent,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byTooltip('Increase beats')).width,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byTooltip('Decrease beats'));
    await tester.pump();
    expect(value, 1);
    await tester.tap(find.byTooltip('Increase beats'));
    await tester.pump();
    expect(value, 2);
    await tester.tap(find.byTooltip('Increase beats'));
    await tester.pump();
    expect(value, 2);
  });

  testWidgets('layer toggle sends value and exposes switch semantics', (
    tester,
  ) async {
    var enabled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.forest),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LayerToggle(
              value: enabled,
              color: SynesterraTokens.of(context).layerColors[0],
              onChanged: (next) => setState(() => enabled = next),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(enabled, isTrue);
  });

  testWidgets('tempo tap changes one BPM and hold repeats until release', (
    tester,
  ) async {
    var value = 120;
    await tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.forest),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => NumberStepper(
              value: value,
              min: 20,
              max: 300,
              label: 'BPM',
              color: SynesterraTokens.of(context).text,
              repeatOnHold: true,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );

    final plus = find.byTooltip('Increase BPM');
    await tester.tap(plus);
    await tester.pump();
    expect(value, 121);

    final gesture = await tester.startGesture(tester.getCenter(plus));
    await tester.pump(const Duration(seconds: 1));
    final afterLongPress = value;
    expect(afterLongPress, greaterThan(121));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final earlyRepeatCount = value - afterLongPress;
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      value - afterLongPress - earlyRepeatCount,
      greaterThan(earlyRepeatCount),
    );
    await gesture.up();
    await tester.pump();
    final released = value;
    await tester.pump(const Duration(seconds: 2));
    expect(value, released);
  });
}
