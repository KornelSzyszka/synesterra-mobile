import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/impl/service_microphone_repository.dart';
import 'package:synesterra/data/repositories/microphone_repository.dart';
import 'package:synesterra/data/services/microphone_service.dart';
import 'package:synesterra/data/services/pcm_framer.dart';

Uint8List pcm(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

class FakeService implements MicrophoneService {
  bool allowed = true;
  bool throwsOnPermission = false;
  final controller = StreamController<Uint8List>();
  int starts = 0;
  int stops = 0;
  int? rate;

  @override
  Future<bool> hasPermission() async {
    if (throwsOnPermission) throw StateError('no plugin');
    return allowed;
  }

  @override
  Future<Stream<Uint8List>> startPcm({required int sampleRate}) async {
    starts++;
    rate = sampleRate;
    return controller.stream;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {}
}

void main() {
  group('PcmFramer', () {
    test('decodes signed little-endian 16-bit samples to -1..1', () {
      final framer = PcmFramer(frameSize: 4, hop: 4);
      final frames = framer.add(pcm([0, 16384, -16384, -32768]));
      expect(frames, hasLength(1));
      expect(frames.single, [0, 0.5, -0.5, -1]);
    });

    test('overlaps frames by the hop', () {
      final framer = PcmFramer(frameSize: 4);
      final frames = framer.add(pcm([1, 2, 3, 4, 5, 6])).map((f) => f.toList());
      // hop = 2: [1..4] then [3..6]
      expect(frames.map((f) => f.map((v) => (v * 32768).round()).toList()), [
        [1, 2, 3, 4],
        [3, 4, 5, 6],
      ]);
    });

    test('keeps a sample split across chunks', () {
      final framer = PcmFramer(frameSize: 2, hop: 2);
      final bytes = pcm([1000, -2000]);
      expect(framer.add(Uint8List.fromList(bytes.sublist(0, 1))), isEmpty);
      expect(framer.add(Uint8List.fromList(bytes.sublist(1, 3))), isEmpty);
      final frames = framer.add(Uint8List.fromList(bytes.sublist(3)));
      expect(frames.single.map((v) => (v * 32768).round()), [1000, -2000]);
    });

    test('rejects bad sizes', () {
      expect(() => PcmFramer(frameSize: 1), throwsArgumentError);
      expect(() => PcmFramer(frameSize: 4, hop: 0), throwsArgumentError);
      expect(() => PcmFramer(frameSize: 4, hop: 5), throwsArgumentError);
    });
  });

  group('ServiceMicrophoneRepository', () {
    test(
      'maps the permission answer, and a failing plugin to denied',
      () async {
        final service = FakeService();
        final repository = ServiceMicrophoneRepository(service);
        expect(await repository.requestAccess(), MicrophoneAccess.granted);
        service.allowed = false;
        expect(await repository.requestAccess(), MicrophoneAccess.denied);
        service.throwsOnPermission = true;
        expect(await repository.requestAccess(), MicrophoneAccess.denied);
        expect(service.starts, 0, reason: 'asking never opens the microphone');
      },
    );

    test('opens on listen, frames the PCM, closes on cancel', () async {
      final service = FakeService();
      final repository = ServiceMicrophoneRepository(service);
      final frames = <Float32List>[];
      final subscription = repository.frames().listen(frames.add);
      await pumpEventQueue();
      expect(service.starts, 1);
      expect(service.rate, 22050);

      service.controller.add(pcm(List.filled(repository.frameSize, 8192)));
      await pumpEventQueue();
      expect(frames, hasLength(1));
      expect(frames.single, hasLength(repository.frameSize));
      expect(frames.single.first, 0.25);

      await subscription.cancel();
      expect(service.stops, 1);
    });

    test('a failure to open is an error event', () async {
      final service = _FailingService();
      final repository = ServiceMicrophoneRepository(service);
      await expectLater(repository.frames(), emitsError(isA<StateError>()));
    });
  });
}

class _FailingService extends FakeService {
  @override
  Future<Stream<Uint8List>> startPcm({required int sampleRate}) async =>
      throw StateError('busy');
}
