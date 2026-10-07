import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:synesterra_core/synesterra_core.dart';

import 'library_item.dart';
import 'strict_json.dart';

/// One loop in the library: an id, a name and a `SessionDocument` v3.
///
/// Prototype v0 rules (docs/product/prototype-v0.md), checked here so a stored
/// loop is always one the Loop panel can show: the cycle,
/// `transport.practiceCycleBeats`, is a whole number of beats 1..16, and every
/// layer's `pattern.durationBeats` in both scenes equals it. The core already
/// checks 2..4 layers with the same ordered ids in scenes A and B.
@immutable
class Loop {
  /// Throws [ArgumentError] for an invalid id, name or document.
  Loop({required this.id, required this.name, required this.document}) {
    if (!libraryIdPattern.hasMatch(id)) throw ArgumentError.value(id, 'id');
    if (!isValidLibraryName(name)) throw ArgumentError.value(name, 'name');
    final cycle = document.transport.practiceCycleBeats;
    if (cycle.denominator != 1 ||
        cycle.numerator < minCycleBeats ||
        cycle.numerator > maxCycleBeats) {
      throw ArgumentError.value(
        cycle.value,
        'document.transport.practiceCycleBeats',
        'must be a whole number of beats $minCycleBeats..$maxCycleBeats',
      );
    }
    for (final scene in document.scenes) {
      for (final layer in scene.layers) {
        if (layer.pattern.durationBeats != cycle) {
          throw ArgumentError.value(
            layer.id,
            'document.scenes',
            'every layer must last exactly one cycle',
          );
        }
      }
    }
  }

  /// Parses a loop file. Throws only [FormatException], whose message starts
  /// with the JSON path. A v2 session is migrated in memory by the core
  /// parser; the file itself is never rewritten here.
  factory Loop.fromJson(Object? json) {
    try {
      if (json is! Map<String, dynamic>) failJson(r'$', 'expected an object');
      if (!json.containsKey('format')) failJson(r'$.format', 'missing field');
      if (json['format'] != fileFormat) {
        failJson(r'$.format', 'expected "$fileFormat"');
      }
      if (!json.containsKey('version')) failJson(r'$.version', 'missing field');
      if (json['version'] != schemaVersion) {
        failJson(r'$.version', 'unsupported version');
      }
      final map = jsonObject(json, r'$', _keys);
      final id = jsonString(map['id'], r'$.id');
      final name = jsonString(map['name'], r'$.name');
      final session = map['session'];
      if (session is! Map<String, dynamic>) {
        failJson(r'$.session', 'expected an object');
      }
      final parsed = parseSessionDocument(jsonEncode(session));
      if (!parsed.isSuccess) {
        final error = parsed.errors.first;
        failJson(
          '\$.session${error.path.substring(1)}',
          '${error.code}: ${error.message}',
        );
      }
      return Loop(id: id, name: name, document: parsed.value!);
    } on ArgumentError catch (error) {
      final name = (error.name ?? '').replaceFirst('document', 'session');
      throw FormatException('\$.$name: ${error.message ?? 'invalid value'}');
    }
  }

  static const fileFormat = 'synesterra.loop';
  static const schemaVersion = 1;
  static const minCycleBeats = 1;
  static const maxCycleBeats = 16;
  static const _keys = {'format', 'version', 'id', 'name', 'session'};

  final String id;
  final String name;
  final SessionDocument document;

  /// Scene A, which the prototype edits (scene B is always a copy of it).
  List<RhythmLayer> get _layers => document.scenes.first.layers;

  int get layerCount => _layers.length;

  /// Steps per layer in one cycle, such as `[3, 2]` for 3:2.
  List<int> get hitsPerLayer => [
    for (final layer in _layers) layer.pattern.steps.length,
  ];

  num get bpm => document.transport.bpm;

  int get cycleBeats => document.transport.practiceCycleBeats.numerator;

  Map<String, Object> toJson() => {
    'format': fileFormat,
    'version': schemaVersion,
    'id': id,
    'name': name,
    'session': document.toJson(),
  };

  Loop copyWith({String? id, String? name, SessionDocument? document}) => Loop(
    id: id ?? this.id,
    name: name ?? this.name,
    document: document ?? this.document,
  );

  /// An editable copy for the user's library: a new id and `<name> copy`.
  /// This is how a read-only factory loop is edited.
  Loop copyAsNew() => copyWith(id: newLibraryId('loop'), name: copyName(name));

  @override
  bool operator ==(Object other) =>
      other is Loop &&
      id == other.id &&
      name == other.name &&
      document == other.document;

  @override
  int get hashCode => Object.hash(id, name, document);

  @override
  String toString() => 'Loop($id, $name)';
}

int compareLoops(Loop a, Loop b) =>
    compareLibraryNames(a.name, a.id, b.name, b.id);

/// One layer of [simpleLoopDocument]: an instrument, a pitch and how many
/// evenly spaced hits it plays per cycle.
class LoopLayerSpec {
  const LoopLayerSpec({
    required this.instrumentId,
    required this.pitch,
    required this.hits,
  });

  final String instrumentId;

  /// MIDI note, [minLayerPitch]..[maxLayerPitch].
  final int pitch;

  /// Steps in the cycle, all enabled, the first one accented.
  final int hits;
}

/// Builds a valid loop document: one cycle of [cycleBeats], one layer per
/// spec (ids `layer-1`, `layer-2`, …), scene B a copy of scene A, no drone.
SessionDocument simpleLoopDocument({
  String title = '',
  required num bpm,
  required int cycleBeats,
  required List<LoopLayerSpec> layers,
}) {
  final cycle = Rational(cycleBeats, 1);
  final built = [
    for (var i = 0; i < layers.length; i++)
      RhythmLayer(
        id: 'layer-${i + 1}',
        instrumentId: layers[i].instrumentId,
        pitch: layers[i].pitch,
        pattern: Pattern(
          durationBeats: cycle,
          steps: [
            for (var step = 0; step < layers[i].hits; step++)
              PatternStep(
                enabled: true,
                velocity: step == 0 ? 1 : 0.8,
                accent: step == 0,
                probability: 1,
              ),
          ],
        ),
        phaseSteps: 0,
        swing: Swing(grid: 'off', amount: 0),
        mix: LayerMix(gain: 0.8, pan: 0, muted: false, solo: false),
      ),
  ];
  Scene scene(String id) => Scene(
    id: id,
    layers: built,
    masterGain: 0.8,
    drone: Drone(
      enabled: false,
      root: 0,
      octave: 3,
      mode: '',
      chord: 'root',
      gain: 0,
      filterHz: 1000,
      spread: 0,
    ),
  );
  return SessionDocument(
    title: title,
    transport: SessionTransport(bpm: bpm, practiceCycleBeats: cycle),
    referenceClick: ReferenceClick(0),
    randomSeed: 0,
    scenes: [scene('A'), scene('B')],
    defaultSceneId: 'A',
    presentation: Presentation('circle'),
  );
}

/// The three factory loops: always present, read-only (copy to edit). Tempo,
/// instruments and pitches are placeholders until the Founder's `musical`
/// gate.
final List<Loop> factoryLoops = List.unmodifiable([
  Loop(
    id: 'factory-loop-3-2',
    name: 'Three against two',
    document: simpleLoopDocument(
      title: 'Three against two',
      bpm: 90,
      cycleBeats: 2,
      layers: const [
        LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: 3),
        LoopLayerSpec(instrumentId: 'factory-bell', pitch: 76, hits: 2),
      ],
    ),
  ),
  Loop(
    id: 'factory-loop-5-4',
    name: 'Five against four',
    document: simpleLoopDocument(
      title: 'Five against four',
      bpm: 80,
      cycleBeats: 4,
      layers: const [
        LoopLayerSpec(instrumentId: 'factory-wood', pitch: 72, hits: 5),
        LoopLayerSpec(instrumentId: 'factory-sine', pitch: 64, hits: 4),
      ],
    ),
  ),
  Loop(
    id: 'factory-loop-4-3-2',
    name: 'Three layers',
    document: simpleLoopDocument(
      title: 'Three layers',
      bpm: 90,
      cycleBeats: 4,
      layers: const [
        LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: 4),
        LoopLayerSpec(instrumentId: 'factory-bell', pitch: 76, hits: 3),
        LoopLayerSpec(instrumentId: 'factory-sine', pitch: 57, hits: 2),
      ],
    ),
  ),
]);
