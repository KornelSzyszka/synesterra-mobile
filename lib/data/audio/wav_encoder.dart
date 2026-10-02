import 'dart:typed_data';

/// Wraps mono samples (-1..1) in a 16-bit PCM WAV container, which is the
/// format audio engines accept for sounds generated in memory.
Uint8List encodeWav16(Float32List samples, {required int sampleRate}) {
  if (sampleRate <= 0) {
    throw ArgumentError.value(sampleRate, 'sampleRate', 'must be positive');
  }
  const headerSize = 44;
  final dataSize = samples.length * 2;
  final bytes = ByteData(headerSize + dataSize);

  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // size of the fmt chunk
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little); // bytes per second
  bytes.setUint16(32, 2, Endian.little); // block align
  bytes.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    bytes.setInt16(
      headerSize + i * 2,
      (clamped * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}
