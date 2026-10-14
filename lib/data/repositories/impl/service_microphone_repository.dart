import 'dart:async';
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
  Stream<Float32List> frames() {
    final framer = PcmFramer(frameSize: frameSize);
    final controller = StreamController<Float32List>();
    StreamSubscription<Uint8List>? source;
    var started = false;
    var cancelled = false;

    Future<void> close() async {
      cancelled = true;
      await source?.cancel();
      source = null;
      if (started) {
        started = false;
        await _service.stop();
      }
    }

    controller.onListen = () async {
      try {
        final pcm = await _service.startPcm(sampleRate: sampleRate.round());
        started = true;
        if (cancelled) {
          await close();
          return;
        }
        source = pcm.listen(
          (chunk) {
            for (final frame in framer.add(chunk)) {
              controller.add(frame);
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      } catch (error, stack) {
        controller.addError(error, stack);
      }
    };
    // Closing the microphone does not wait for the next audio chunk.
    controller.onCancel = close;
    return controller.stream;
  }
}
