import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'audition_engine.dart';

class _Source implements AuditionSource {
  _Source(this.source);

  final AudioSource source;
}

class _Voice implements AuditionVoice {
  _Voice(this.handle);

  final SoundHandle handle;
}

/// [AuditionEngine] on top of `flutter_soloud`. The engine is started on the
/// first use, never at app launch.
class SoloudAuditionEngine implements AuditionEngine {
  Future<void>? _starting;

  SoLoud get _soloud => SoLoud.instance;

  @override
  Future<void> start() {
    if (_soloud.isInitialized) return Future.value();
    // A failed start is not remembered, so a later tap can try again.
    return _starting ??= _soloud.init().whenComplete(() => _starting = null);
  }

  @override
  Future<AuditionSource> load(String id, Uint8List wav) async =>
      _Source(await _soloud.loadMem(id, wav));

  @override
  AuditionVoice play(AuditionSource source, {double volume = 1}) =>
      _Voice(_soloud.play((source as _Source).source, volume: volume));

  @override
  Future<void> stop(AuditionVoice voice) =>
      _soloud.stop((voice as _Voice).handle);

  @override
  Future<void> unload(AuditionSource source) =>
      _soloud.disposeSource((source as _Source).source);

  @override
  Future<void> dispose() async {
    if (_soloud.isInitialized) await _soloud.deinitAsync();
  }
}
