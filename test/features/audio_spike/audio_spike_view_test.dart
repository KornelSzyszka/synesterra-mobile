import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/audio_spike_repository.dart';
import 'package:synesterra/features/audio_spike/audio_spike_view.dart';

final class _FakeSpikeRepository implements AudioSpikeRepository {
  final current = ValueNotifier(const AudioSpikeStatus());
  int starts = 0;
  int pauses = 0;
  int stops = 0;

  @override
  ValueListenable<AudioSpikeStatus> get status => current;

  @override
  Future<void> start() async {
    starts++;
    current.value = const AudioSpikeStatus(transport: SpikeTransport.playing);
  }

  @override
  Future<void> pause() async {
    pauses++;
    current.value = const AudioSpikeStatus(transport: SpikeTransport.paused);
  }

  @override
  Future<void> stop() async {
    stops++;
    current.value = const AudioSpikeStatus();
  }

  @override
  void setTempo(int bpm) {}
  @override
  void setScene(String scene) {}
  @override
  void setLayers(int layers) {}
  @override
  void setDrone(bool enabled) {}
  @override
  void setStress(bool enabled) {}
  @override
  Future<void> runInstrumentCheck() async {}
  @override
  Future<String> exportDiagnostics() async => '/fake/diagnostics.json';
  @override
  Future<void> dispose() async {
    current.dispose();
  }
}

void main() {
  testWidgets(
    'spike requires explicit Start and pauses when app leaves foreground',
    (tester) async {
      final repo = _FakeSpikeRepository();
      await tester.pumpWidget(
        MaterialApp(home: AudioSpikeView(repository: repo)),
      );
      expect(repo.starts, 0);
      expect(find.text('Transport: stopped'), findsOneWidget);
      await tester.tap(find.byKey(const Key('spike-start')));
      await tester.pump();
      expect(repo.starts, 1);
      expect(find.text('Transport: playing'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(repo.pauses, 1);
      expect(find.text('Transport: paused'), findsOneWidget);
      await tester.tap(find.byKey(const Key('spike-stop')));
      await tester.pump();
      expect(repo.stops, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
