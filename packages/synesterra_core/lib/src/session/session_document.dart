import 'dart:convert';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../harmony/drone.dart';
import '../rhythm/rhythm_values.dart';

class SessionTransport {
  SessionTransport({required this.bpm, required this.practiceCycleBeats}) {
    if (!bpm.isFinite || bpm < 20 || bpm > 300 || bpm == 0 && bpm.isNegative) {
      throw ArgumentError.value(bpm, 'bpm');
    }
  }
  final num bpm;
  final Rational practiceCycleBeats;
  Map<String, Object> toJson() => {
    'beatUnit': 'quarter-note',
    'bpm': bpm,
    'practiceCycleBeats': practiceCycleBeats.toJson(),
  };
  @override
  bool operator ==(Object other) =>
      other is SessionTransport &&
      bpm == other.bpm &&
      practiceCycleBeats == other.practiceCycleBeats;
  @override
  int get hashCode => Object.hash(bpm, practiceCycleBeats);
}

class ReferenceClick {
  ReferenceClick(this.subdivision) {
    if (subdivision < 0 || subdivision > 6) {
      throw ArgumentError.value(subdivision, 'subdivision');
    }
  }
  final int subdivision;
  Map<String, Object> toJson() => {'subdivision': subdivision};
  @override
  bool operator ==(Object other) =>
      other is ReferenceClick && subdivision == other.subdivision;
  @override
  int get hashCode => subdivision.hashCode;
}

class Presentation {
  Presentation(this.visualMode) {
    if (!const {'circle', 'timeline'}.contains(visualMode)) {
      throw ArgumentError.value(visualMode, 'visualMode');
    }
  }
  final String visualMode;
  Map<String, Object> toJson() => {'visualMode': visualMode};
  @override
  bool operator ==(Object other) =>
      other is Presentation && visualMode == other.visualMode;
  @override
  int get hashCode => visualMode.hashCode;
}

class Scene {
  Scene({
    required this.id,
    required List<RhythmLayer> layers,
    required this.masterGain,
    required this.drone,
  }) : layers = List.unmodifiable(layers) {
    if (!const {'A', 'B'}.contains(id)) throw ArgumentError.value(id, 'id');
    if (layers.length < 2 ||
        layers.length > 4 ||
        layers.map((layer) => layer.id).toSet().length != layers.length) {
      throw ArgumentError('Scene requires 2..4 unique layer IDs');
    }
    unitInterval(masterGain, 'masterGain');
  }
  final String id;
  final List<RhythmLayer> layers;
  final num masterGain;
  final Drone drone;
  Map<String, Object> toJson() => {
    'id': id,
    'layers': layers.map((layer) => layer.toJson()).toList(),
    'masterGain': masterGain,
    'drone': drone.toJson(),
  };
  @override
  bool operator ==(Object other) =>
      other is Scene &&
      id == other.id &&
      sameValues(layers, other.layers) &&
      masterGain == other.masterGain &&
      drone == other.drone;
  @override
  int get hashCode =>
      Object.hash(id, Object.hashAll(layers), masterGain, drone);
}

class SessionDocument {
  SessionDocument({
    required this.title,
    required this.transport,
    required this.referenceClick,
    required this.randomSeed,
    required List<Scene> scenes,
    required this.defaultSceneId,
    required this.presentation,
  }) : scenes = List.unmodifiable(scenes) {
    if (unorm.nfc(title).runes.length > 80 ||
        title.runes.any(
          (rune) => rune <= 0x1f || rune >= 0x7f && rune <= 0x9f,
        )) {
      throw ArgumentError.value(title, 'title');
    }
    if (randomSeed < 0 || randomSeed > 0xffffffff) {
      throw ArgumentError.value(randomSeed, 'randomSeed');
    }
    if (scenes.length != 2 || scenes[0].id != 'A' || scenes[1].id != 'B') {
      throw ArgumentError('Scenes must be A then B');
    }
    if (!const {'A', 'B'}.contains(defaultSceneId)) {
      throw ArgumentError.value(defaultSceneId, 'defaultSceneId');
    }
    if (scenes[0].layers.length != scenes[1].layers.length) {
      throw ArgumentError('Scene layer count differs');
    }
    for (var i = 0; i < scenes[0].layers.length; i++) {
      if (scenes[0].layers[i].id != scenes[1].layers[i].id) {
        throw ArgumentError('Scene layer IDs differ');
      }
    }
    if (scenes
            .expand((scene) => scene.layers)
            .fold<int>(0, (sum, layer) => sum + layer.pattern.steps.length) >
        256) {
      throw ArgumentError('Document exceeds 256 steps');
    }
    if (utf8.encode(jsonEncode(toJson())).length > 128 * 1024) {
      throw ArgumentError('Document exceeds 128 KiB');
    }
  }
  final String title;
  final SessionTransport transport;
  final ReferenceClick referenceClick;
  final int randomSeed;
  final List<Scene> scenes;
  final String defaultSceneId;
  final Presentation presentation;

  Map<String, Object> toJson() => {
    'format': 'polyrhythmer.session',
    'version': 2,
    'revision': 0,
    'title': title,
    'transport': transport.toJson(),
    'referenceClick': referenceClick.toJson(),
    'randomSeed': randomSeed,
    'scenes': scenes.map((scene) => scene.toJson()).toList(),
    'defaultSceneId': defaultSceneId,
    'presentation': presentation.toJson(),
  };
  String serialize() => jsonEncode(toJson());
  @override
  bool operator ==(Object other) =>
      other is SessionDocument &&
      title == other.title &&
      transport == other.transport &&
      referenceClick == other.referenceClick &&
      randomSeed == other.randomSeed &&
      sameValues(scenes, other.scenes) &&
      defaultSceneId == other.defaultSceneId &&
      presentation == other.presentation;
  @override
  int get hashCode => Object.hash(
    title,
    transport,
    referenceClick,
    randomSeed,
    Object.hashAll(scenes),
    defaultSceneId,
    presentation,
  );
}
