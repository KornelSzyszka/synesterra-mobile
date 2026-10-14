import 'dart:typed_data';

/// Turns a stream of little-endian 16-bit mono PCM chunks into overlapping
/// frames of floats in -1..1. Chunks may split a sample; a leftover byte is
/// kept for the next chunk.
class PcmFramer {
  PcmFramer({required this.frameSize, int? hop}) : hop = hop ?? frameSize ~/ 2 {
    if (frameSize < 2) throw ArgumentError.value(frameSize, 'frameSize');
    if (this.hop < 1 || this.hop > frameSize) {
      throw ArgumentError.value(this.hop, 'hop', 'between 1 and frameSize');
    }
  }

  final int frameSize;

  /// New samples between two frames.
  final int hop;

  final List<double> _samples = [];
  int? _pendingByte;

  /// Adds [chunk]; returns the frames that are complete now.
  List<Float32List> add(Uint8List chunk) {
    var i = 0;
    if (_pendingByte != null && chunk.isNotEmpty) {
      _push(_pendingByte!, chunk[0]);
      _pendingByte = null;
      i = 1;
    }
    for (; i + 1 < chunk.length; i += 2) {
      _push(chunk[i], chunk[i + 1]);
    }
    if (i < chunk.length) _pendingByte = chunk[i];

    final frames = <Float32List>[];
    while (_samples.length >= frameSize) {
      frames.add(Float32List.fromList(_samples.sublist(0, frameSize)));
      _samples.removeRange(0, hop);
    }
    return frames;
  }

  void _push(int low, int high) {
    var value = (high << 8) | low;
    if (value >= 0x8000) value -= 0x10000;
    _samples.add(value / 32768);
  }
}
