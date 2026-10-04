import 'package:flutter/foundation.dart';

enum SpikeTransport { stopped, playing, paused }

final class AudioSpikeStatus {
  const AudioSpikeStatus({
    this.transport = SpikeTransport.stopped,
    this.scene = '3:2',
    this.bpm = 90,
    this.layers = 2,
    this.drone = false,
    this.busy = false,
    this.error,
    this.exportPath,
    this.activeVoices = 0,
    this.totalVoices = 0,
    this.maxVoices = 0,
    this.loadedBuffers = 0,
    this.rejected = 0,
    this.late = 0,
  });

  final SpikeTransport transport;
  final String scene;
  final int bpm;
  final int layers;
  final bool drone;
  final bool busy;
  final String? error;
  final String? exportPath;
  final int activeVoices;
  final int totalVoices;
  final int maxVoices;
  final int loadedBuffers;
  final int rejected;
  final int late;
}

abstract interface class AudioSpikeRepository {
  ValueListenable<AudioSpikeStatus> get status;
  Future<void> start();
  Future<void> pause();
  Future<void> stop();
  void setTempo(int bpm);
  void setScene(String scene);
  void setLayers(int layers);
  void setDrone(bool enabled);
  void setStress(bool enabled);
  Future<void> runInstrumentCheck();
  Future<String> exportDiagnostics();
  Future<void> dispose();
}
