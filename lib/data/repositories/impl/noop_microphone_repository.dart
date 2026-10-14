import 'dart:async';
import 'dart:typed_data';

import '../microphone_repository.dart';

/// Grants access and hears nothing. For views and tests without a
/// microphone.
class NoopMicrophoneRepository implements MicrophoneRepository {
  NoopMicrophoneRepository();

  @override
  double get sampleRate => 22050;

  @override
  int get frameSize => 2048;

  @override
  Future<MicrophoneAccess> requestAccess() async => MicrophoneAccess.granted;

  @override
  Stream<Float32List> frames() => StreamController<Float32List>().stream;
}
