import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/shared/loop_view/position_source.dart';

void main() {
  group('LoopPosition', () {
    test('rejects a cycle position outside [0, 1) at runtime', () {
      // ArgumentError, not an assert: release builds must reject it too.
      for (final bad in [1.0, 1.5, -0.1, double.nan, double.infinity]) {
        expect(
          () => LoopPosition(cyclePosition: bad),
          throwsA(isA<ArgumentError>()),
          reason: '$bad',
        );
      }
      expect(LoopPosition(cyclePosition: 0).cyclePosition, 0);
      expect(LoopPosition(cyclePosition: 0.999).cyclePosition, 0.999);
    });

    test('rejects negative counters and section index', () {
      expect(() => LoopPosition(cycleIndex: -1), throwsArgumentError);
      expect(() => LoopPosition(generation: -1), throwsArgumentError);
      expect(() => LoopPosition(sectionIndex: -1), throwsArgumentError);
      expect(LoopPosition(sectionIndex: 0).sectionIndex, 0);
    });

    test('has value equality', () {
      expect(
        LoopPosition(playing: true, cyclePosition: 0.5, sectionIndex: 1),
        LoopPosition(playing: true, cyclePosition: 0.5, sectionIndex: 1),
      );
      expect(
        LoopPosition(cyclePosition: 0.5),
        isNot(LoopPosition(cyclePosition: 0.5, generation: 1)),
      );
    });

    test('stopped is not playing at the start of the cycle', () {
      expect(LoopPosition.stopped.playing, isFalse);
      expect(LoopPosition.stopped.cyclePosition, 0);
      expect(LoopPosition.stopped.sectionIndex, isNull);
    });
  });

  group('FakePositionSource', () {
    test('notifies listeners with the new position', () {
      final source = FakePositionSource();
      var calls = 0;
      source.addListener(() => calls++);
      expect(source.value, LoopPosition.stopped);

      source.set(playing: true, cyclePosition: 0.25, cycleIndex: 2);
      expect(source.value.playing, isTrue);
      expect(source.value.cyclePosition, 0.25);
      expect(source.value.cycleIndex, 2);
      expect(calls, 1);
    });

    test('is a PositionSource', () {
      expect(FakePositionSource(), isA<PositionSource>());
    });
  });

  group('TutorialClock.positionAt', () {
    const cycle = Duration(seconds: 2);

    test('is exact and half-open at the cycle boundary', () {
      expect(TutorialClock.positionAt(Duration.zero, cycle), (0.0, 0));
      expect(TutorialClock.positionAt(const Duration(seconds: 1), cycle), (
        0.5,
        0,
      ));
      expect(TutorialClock.positionAt(const Duration(seconds: 2), cycle), (
        0.0,
        1,
      ));
      expect(
        TutorialClock.positionAt(const Duration(milliseconds: 4500), cycle),
        (0.25, 2),
      );
    });

    test('is deterministic', () {
      const t = Duration(microseconds: 1234567);
      expect(
        TutorialClock.positionAt(t, cycle),
        TutorialClock.positionAt(t, cycle),
      );
    });
  });

  group('TutorialClock', () {
    testWidgets('rejects a cycle that is not positive', (tester) async {
      expect(
        () => TutorialClock(vsync: tester, cycleDuration: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => TutorialClock(
          vsync: tester,
          cycleDuration: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });

    testWidgets('runs from the ticker, stops and resets', (tester) async {
      final clock = TutorialClock(
        vsync: tester,
        cycleDuration: const Duration(seconds: 2),
      );
      addTearDown(clock.dispose);
      expect(clock.value.playing, isFalse);

      clock.start();
      expect(clock.value.playing, isTrue);
      final startGeneration = clock.value.generation;

      await tester.pump(); // first frame
      await tester.pump(const Duration(seconds: 1));
      expect(clock.value.cyclePosition, closeTo(0.5, 1e-6));
      await tester.pump(const Duration(seconds: 2));
      expect(clock.value.cycleIndex, 1);
      expect(clock.value.cyclePosition, closeTo(0.5, 1e-6));

      clock.stop();
      expect(clock.value.playing, isFalse);
      expect(clock.value.cyclePosition, 0);
      expect(clock.value.cycleIndex, 0);
      expect(clock.value.generation, greaterThan(startGeneration));
      await tester.pump(const Duration(seconds: 1));
      expect(clock.value.cyclePosition, 0);
    });

    testWidgets('is a PositionSource without a section', (tester) async {
      final clock = TutorialClock(
        vsync: tester,
        cycleDuration: const Duration(seconds: 1),
      )..start();
      expect(clock.value.sectionIndex, isNull);
      expect(clock, isA<PositionSource>());
      clock.dispose();
    });
  });
}
