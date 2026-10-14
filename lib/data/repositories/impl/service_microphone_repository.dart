import 'dart:typed_data';

import '../../services/microphone_service.dart';
import '../../services/pcm_framer.dart';
import '../microphone_repository.dart';

/// [MicrophoneRepository] over a [MicrophoneService]. Frames are 2048 samples
/// at 22.05 kHz (93 ms), a new one every 46 ms. That window holds about two
/// periods of E1 (41 Hz); latency to a new note is up to one window. Neither
/// is measured on a phone.
class ServiceMicrophoneRepository implements MicrophoneRepository {
  ServiceMicrophoneRepository(this._service);

  final MicrophoneService _service;

  @override
  double get sampleRate => 22050;

  @override
  int get frameSize => 2048;

  @override
  Future<MicrophoneAccess> requestAccess() async {
    try {
      return await _service.hasPermission()
          ? MicrophoneAccess.granted
          : MicrophoneAccess.denied;
    } catch (_) {
      return MicrophoneAccess.denied;
    }
  }

  @override
  Stream<Float32List> frames() async* {
    final framer = PcmFramer(frameSize: frameSize);
    final pcm = await _service.startPcm(sampleRate: sampleRate.round());
    try {
      await for (final chunk in pcm) {
        for (final frame in framer.add(chunk)) {
          yield frame;
        }
      }
    } finally {
      await _service.stop();
    }
  }
}
