import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/noop_microphone_repository.dart';
import 'package:synesterra/data/repositories/microphone_repository.dart';
import 'package:synesterra/features/training/training_view.dart';
import 'package:synesterra/features/tuner/tuner_model.dart';
import 'package:synesterra/features/tuner/tuner_view.dart';
import 'package:synesterra/shared/theme/synesterra_theme.dart';

import '../training/training_fakes.dart';

class FakeMicrophone implements MicrophoneRepository {
  MicrophoneAccess access = MicrophoneAccess.granted;
  bool failOpen = false;
  int requests = 0;
  int opens = 0;
  int closes = 0;
  StreamController<Float32List>? _controller;

  @override
  double get sampleRate => 22050;

  @override
  int get frameSize => 2048;

  @override
  Future<MicrophoneAccess> requestAccess() async {
    requests++;
    return access;
  }

  @override
  Stream<Float32List> frames() {
    final controller = StreamController<Float32List>(
      onListen: () => opens++,
      onCancel: () => closes++,
    );
    _controller = controller;
    if (failOpen) controller.addError(StateError('busy'));
    return controller.stream;
  }

  bool get open => _controller?.hasListener ?? false;

  void sine(double hz, {double amplitude = .5}) {
    _controller!.add(
      Float32List.fromList([
        for (var i = 0; i < frameSize; i++)
          amplitude * math.sin(2 * math.pi * hz * i / sampleRate),
      ]),
    );
  }

  void silence() => _controller!.add(Float32List(frameSize));
}

Future<(FakeMicrophone, ScriptedPlayback)> pumpTuner(
  WidgetTester tester, {
  double width = 412,
  double textScale = 1,
  bool reduceMotion = false,
  FakeMicrophone? microphone,
}) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final mic = microphone ?? FakeMicrophone();
  final playback = ScriptedPlayback();
  await tester.pumpWidget(
    MaterialApp(
      theme: synesterraTheme(SynesterraPalette.graphite),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: TunerView(microphone: mic, playback: playback),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (mic, playback);
}

/// Lets queued stream events and awaited futures run (stream cancellation
/// completes on the real event loop), then paints.
Future<void> tick(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('listens on open, shows the note and cents, stops on close', (
    tester,
  ) async {
    final (mic, playback) = await pumpTuner(tester);
    expect(playback.stops, greaterThan(0), reason: 'playback stops first');
    expect(mic.open, isTrue);
    expect(find.text('--'), findsOneWidget);
    expect(find.text('Play a note'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      mic.sine(440);
      await tick(tester);
    }
    expect(find.byKey(const Key('tuner-note')), findsOneWidget);
    expect(find.text('A4'), findsOneWidget);
    expect(find.text('In tune'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(mic.closes, 1);
  });

  testWidgets('reports a flat note in cents', (tester) async {
    final (mic, _) = await pumpTuner(tester);
    // 20 cents flat of A4.
    final hz = 440 * math.pow(2, -20 / 1200).toDouble();
    for (var i = 0; i < 3; i++) {
      mic.sine(hz);
      await tick(tester);
    }
    expect(find.text('A4'), findsOneWidget);
    expect(find.textContaining('-20 cents'), findsOneWidget);
  });

  testWidgets('goes back to no note on silence', (tester) async {
    final (mic, _) = await pumpTuner(tester);
    mic.sine(440);
    await tick(tester);
    expect(find.text('A4'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      mic.silence();
      await tick(tester);
    }
    expect(find.text('--'), findsOneWidget);
  });

  testWidgets('a denied microphone shows the denied state and can retry', (
    tester,
  ) async {
    final mic = FakeMicrophone()..access = MicrophoneAccess.denied;
    await pumpTuner(tester, microphone: mic);
    expect(mic.opens, 0);
    expect(find.textContaining('Microphone access is off'), findsOneWidget);
    expect(find.bySemanticsLabel('Try again'), findsOneWidget);

    mic.access = MicrophoneAccess.granted;
    await tester.tap(find.byKey(const Key('tuner-listen')));
    await tick(tester);
    await tick(tester);
    expect(mic.opens, 1);
    expect(find.textContaining('Microphone access is off'), findsNothing);
  });

  testWidgets('a microphone that fails to open shows the failed state', (
    tester,
  ) async {
    final mic = FakeMicrophone()..failOpen = true;
    await pumpTuner(tester, microphone: mic);
    await tick(tester);
    expect(find.textContaining('could not be opened'), findsOneWidget);
  });

  testWidgets('the reference pitch moves the cents and is bounded', (
    tester,
  ) async {
    final (mic, _) = await pumpTuner(tester);
    expect(find.text('A4 = 440 Hz'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byKey(const Key('tuner-ref-down')));
      await tick(tester);
    }
    expect(find.text('A4 = 432 Hz'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      mic.sine(432);
      await tick(tester);
    }
    expect(find.text('A4'), findsOneWidget);
    expect(find.text('In tune'), findsOneWidget);
    expect(
      find.byKey(const Key('tuner-tone')),
      findsNothing,
      reason: 'the tone is A4 = 440 Hz only',
    );
  });

  testWidgets('the reference tone stops listening, and listening stops it', (
    tester,
  ) async {
    final (mic, playback) = await pumpTuner(tester);
    expect(mic.open, isTrue);

    await tester.tap(find.byKey(const Key('tuner-tone')));
    await tick(tester);
    await tick(tester);
    expect(mic.open, isFalse, reason: 'no feedback loop');
    expect(playback.documents, hasLength(1));
    expect(find.text('Stop tone'), findsOneWidget);

    final stopsBefore = playback.stops;
    await tester.tap(find.byKey(const Key('tuner-listen')));
    await tick(tester);
    await tick(tester);
    expect(playback.stops, greaterThan(stopsBefore));
    expect(mic.open, isTrue);
    expect(find.text('Play A4'), findsOneWidget);
  });

  testWidgets('leaving the app stops the microphone and returning resumes', (
    tester,
  ) async {
    final (mic, _) = await pumpTuner(tester);
    expect(mic.open, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tick(tester);
    expect(mic.open, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tick(tester);
    await tick(tester);
    expect(mic.open, isTrue);
  });

  testWidgets('fits 320 dp wide at large text and under reduce motion', (
    tester,
  ) async {
    final (mic, _) = await pumpTuner(
      tester,
      width: 320,
      textScale: 2,
      reduceMotion: true,
    );
    for (var i = 0; i < 3; i++) {
      mic.sine(440);
      await tick(tester);
    }
    expect(tester.takeException(), isNull);
    expect(find.text('A4'), findsOneWidget);
    // Nothing is left animating under reduce motion.
    await tester.pumpAndSettle();
  });

  group('TunerModel', () {
    test('the reference is whole Hz inside 400..480', () {
      final model = TunerModel(
        microphone: FakeMicrophone(),
        playback: ScriptedPlayback(),
      );
      model.setReference(431.6);
      expect(model.referenceA4, 432);
      model.setReference(900);
      expect(model.referenceA4, 480);
      model.setReference(10);
      expect(model.referenceA4, 400);
      model.dispose();
    });
  });

  testWidgets('Training offers the Tuner only when the app wires it', (
    tester,
  ) async {
    Future<void> pump({VoidCallback? onOpenTuner}) => tester.pumpWidget(
      MaterialApp(
        theme: synesterraTheme(SynesterraPalette.graphite),
        home: TrainingView(
          playback: ScriptedPlayback(),
          onOpenTuner: onOpenTuner,
        ),
      ),
    );
    await pump();
    expect(find.byKey(const Key('training-tuner')), findsNothing);
    var opened = 0;
    await pump(onOpenTuner: () => opened++);
    await tester.tap(find.byKey(const Key('training-tuner')));
    expect(opened, 1);
  });

  test('the silent microphone grants access and never emits', () async {
    final mic = NoopMicrophoneRepository();
    expect(await mic.requestAccess(), MicrophoneAccess.granted);
  });
}
