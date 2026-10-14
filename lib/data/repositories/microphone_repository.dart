import 'dart:typed_data';

/// Whether the app may use the microphone.
enum MicrophoneAccess { granted, denied }

/// The microphone as the Tuner needs it: mono sample frames, no recording and
/// nothing stored. The port is the only place the UI reaches the platform
/// (R5); the plugin sits behind `services/microphone_service.dart`.
abstract interface class MicrophoneRepository {
  /// Samples per second of every frame.
  double get sampleRate;

  /// Samples in each frame; consecutive frames overlap by half.
  int get frameSize;

  /// Asks for the microphone permission when it is not decided yet. Never
  /// opens the microphone.
  Future<MicrophoneAccess> requestAccess();

  /// Opens the microphone when listened to and closes it when the
  /// subscription is cancelled. Samples are -1..1. A failure to open it is an
  /// error event. Call [requestAccess] first.
  Stream<Float32List> frames();
}
