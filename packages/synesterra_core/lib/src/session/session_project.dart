import '../rhythm/rhythm_values.dart';
import 'session_document.dart';

/// A resolved, immutable scene view for pure beat planning.
final class SessionProject {
  SessionProject(SessionDocument document, {String? sceneId})
    : transport = document.transport,
      randomSeed = document.randomSeed,
      scene = _resolveScene(document, sceneId ?? document.defaultSceneId);

  final SessionTransport transport;
  final int randomSeed;
  final Scene scene;

  String get sceneId => scene.id;
  List<RhythmLayer> get layers => scene.layers;
  num get masterGain => scene.masterGain;

  static Scene _resolveScene(SessionDocument document, String sceneId) {
    for (final scene in document.scenes) {
      if (scene.id == sceneId) return scene;
    }
    throw ArgumentError.value(sceneId, 'sceneId', 'unknown scene');
  }
}
