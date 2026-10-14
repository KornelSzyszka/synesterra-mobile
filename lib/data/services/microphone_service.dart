import 'dart:typed_data';

import 'package:record/record.dart';

/// The platform microphone: permission and a raw PCM stream.
abstract interface class MicrophoneService {
  /// True when allowed; asks the user when not decided yet.
  Future<bool> hasPermission();

  /// Starts capture: little-endian 16-bit mono PCM at [sampleRate].
  Future<Stream<Uint8List>> startPcm({required int sampleRate});

  Future<void> stop();

  Future<void> dispose();
}

/// [MicrophoneService] on the `record` plugin. Gain control, echo
/// cancellation and noise suppression are off, so the tuner hears the
/// instrument as it is.
class RecordMicrophoneService implements MicrophoneService {
  RecordMicrophoneService() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startPcm({required int sampleRate}) =>
      _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
