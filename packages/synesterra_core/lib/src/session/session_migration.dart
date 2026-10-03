/// The instrument id a v2 `sound` id becomes in v3.
const v2SoundInstrumentIds = <String, String>{
  'wood': 'factory-wood',
  'sine': 'factory-sine',
  'bell': 'factory-bell',
};

/// The pitch given to every migrated layer: MIDI note 69, A4 (440 Hz), the
/// editor's default test note. v2 layers had no pitch of their own.
const defaultMigratedPitch = 69;

/// A v2 document that cannot be migrated; [path] is a JSON path.
class SessionMigrationException implements Exception {
  const SessionMigrationException(this.path, this.message);
  final String path;
  final String message;
  @override
  String toString() => '$path: $message';
}

/// Migrates a decoded session document from v2 to v3 without touching [json].
///
/// A v2 layer's `sound` becomes `instrumentId` (see [v2SoundInstrumentIds])
/// and the layer gets [defaultMigratedPitch]. A document that is not v2 is
/// returned unchanged, so the function is idempotent. Only the layer `sound`
/// is examined here; every other field is left for the strict parser.
/// Throws [SessionMigrationException] for an unknown or non-string `sound`,
/// a missing `sound`, or a v2 layer that already has v3 fields.
Map<String, dynamic> migrateSessionJson(Map<String, dynamic> json) {
  if (json['version'] != 2) return json;
  final scenes = json['scenes'];
  final migratedScenes = scenes is List
      ? [
          for (var s = 0; s < scenes.length; s++)
            _migrateScene(scenes[s], 'scenes[$s]'),
        ]
      : scenes;
  return {...json, 'version': 3, 'scenes': migratedScenes};
}

Object? _migrateScene(Object? scene, String path) {
  if (scene is! Map<String, dynamic> || scene['layers'] is! List) return scene;
  final layers = scene['layers'] as List;
  return {
    ...scene,
    'layers': [
      for (var l = 0; l < layers.length; l++)
        _migrateLayer(layers[l], '$path.layers[$l]'),
    ],
  };
}

Object? _migrateLayer(Object? layer, String path) {
  if (layer is! Map<String, dynamic>) return layer;
  for (final key in const ['instrumentId', 'pitch']) {
    if (layer.containsKey(key)) {
      throw SessionMigrationException('$path.$key', 'Unknown field');
    }
  }
  if (!layer.containsKey('sound')) {
    throw SessionMigrationException('$path.sound', 'Missing field');
  }
  final sound = layer['sound'];
  if (sound is! String) {
    throw SessionMigrationException('$path.sound', 'Expected string');
  }
  final instrumentId = v2SoundInstrumentIds[sound];
  if (instrumentId == null) {
    throw SessionMigrationException(
      '$path.sound',
      'Unknown v2 sound; expected wood, sine or bell',
    );
  }
  return {
    for (final entry in layer.entries)
      if (entry.key != 'sound') entry.key: entry.value,
    'instrumentId': instrumentId,
    'pitch': defaultMigratedPitch,
  };
}
