import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/app/step_feedback.dart';
import 'package:synesterra/app/synesterra_app.dart';
import 'package:synesterra/data/repositories/impl/in_memory_instrument_library_repository.dart';
import 'package:synesterra/data/repositories/impl/noop_instrument_audition_repository.dart';
import 'package:synesterra/features/editor/instrument_radar_view.dart';
import 'package:synesterra/shared/instrument_radar/radar_geometry.dart';

/// Drags spoke [index] from [from] to [to] in small moves, then lifts.
Future<void> drag(
  WidgetTester tester,
  int index,
  double from,
  double to,
) async {
  final rect = tester.getRect(find.byType(InstrumentRadar));
  final reach = WheelLayout.of(rect.size).reach;
  Offset at(double v) =>
      radarPoint(index, 6, v, rect.size, reach) + rect.topLeft;
  final gesture = await tester.startGesture(at(from));
  for (var i = 1; i <= 20; i++) {
    await gesture.moveTo(at(from + (to - from) * i / 20));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('the app gives the wheel its step tick: once per step crossed, '
      'never within a step', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    var ticks = 0;
    await tester.pumpWidget(
      SynesterraApp(
        instrumentLibrary: InMemoryInstrumentLibraryRepository(),
        instrumentAudition: NoopInstrumentAuditionRepository(),
        stepFeedback: () => ticks++,
      ),
    );
    await tester.tap(find.byKey(const Key('home-editor')));
    await tester.pumpAndSettle();

    // Within rank C (0.5): 0.47 .. 0.54 all snap to step 5.
    await drag(tester, 2, 0.5, 0.54);
    expect(ticks, 0, reason: 'a drag within one step does not tick');

    await drag(tester, 2, 0.5, 0.8);
    expect(ticks, 3, reason: 'C to C+, B and B+');
  });

  testWidgets('the app ticks with the platform selection click by default', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final app = SynesterraApp(
      instrumentLibrary: InMemoryInstrumentLibraryRepository(),
      instrumentAudition: NoopInstrumentAuditionRepository(),
    );
    expect(app.stepFeedback, same(hapticStepFeedback));

    hapticStepFeedback();
    await tester.pump();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'HapticFeedback.vibrate');
    expect(calls.single.arguments, 'HapticFeedbackType.selectionClick');
  });
}
