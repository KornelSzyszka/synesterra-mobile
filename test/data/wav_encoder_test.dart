import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/audio/wav_encoder.dart';

String ascii(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));

void main() {
  final samples = Float32List.fromList([0, 1, -1, 0.5, 2, -2]);
  final wav = encodeWav16(samples, sampleRate: 48000);
  final data = ByteData.sublistView(wav);

  test('writes a canonical mono 16-bit PCM header', () {
    expect(ascii(wav, 0, 4), 'RIFF');
    expect(ascii(wav, 8, 4), 'WAVE');
    expect(ascii(wav, 12, 4), 'fmt ');
    expect(ascii(wav, 36, 4), 'data');
    expect(data.getUint32(16, Endian.little), 16, reason: 'fmt chunk size');
    expect(data.getUint16(20, Endian.little), 1, reason: 'PCM');
    expect(data.getUint16(22, Endian.little), 1, reason: 'mono');
    expect(data.getUint32(24, Endian.little), 48000);
    expect(data.getUint32(28, Endian.little), 96000, reason: 'byte rate');
    expect(data.getUint16(32, Endian.little), 2, reason: 'block align');
    expect(data.getUint16(34, Endian.little), 16, reason: 'bits per sample');
  });

  test('sizes match the sample count', () {
    expect(wav.length, 44 + samples.length * 2);
    expect(data.getUint32(40, Endian.little), samples.length * 2);
    expect(data.getUint32(4, Endian.little), wav.length - 8);
  });

  test('converts samples to signed 16-bit and clamps out-of-range values', () {
    int sample(int i) => data.getInt16(44 + i * 2, Endian.little);
    expect(sample(0), 0);
    expect(sample(1), 32767);
    expect(sample(2), -32767);
    expect(sample(3), 16384, reason: '0.5 rounds to the nearest step');
    expect(sample(4), 32767, reason: '2.0 is clamped');
    expect(sample(5), -32767, reason: '-2.0 is clamped');
  });

  test('an empty buffer is a valid file with no data', () {
    final empty = encodeWav16(Float32List(0), sampleRate: 44100);
    expect(empty.length, 44);
    expect(ByteData.sublistView(empty).getUint32(40, Endian.little), 0);
  });

  test('rejects a non-positive sample rate', () {
    expect(
      () => encodeWav16(Float32List(1), sampleRate: 0),
      throwsArgumentError,
    );
  });
}
