import 'dart:convert';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> fixture() {
  Map<String, dynamic> layer(String id) => {
    'id': id,
    'instrumentId': 'factory-wood',
    'pitch': 69,
    'pattern': {
      'durationBeats': {'numerator': 4, 'denominator': 1},
      'steps': [
        {'enabled': true, 'velocity': 1, 'accent': true, 'probability': 1},
        {'enabled': true, 'velocity': 0, 'accent': false, 'probability': 0},
      ],
    },
    'phaseSteps': 0,
    'swing': {'grid': 'off', 'amount': 0},
    'mix': {'gain': 1, 'pan': 0, 'muted': false, 'solo': false},
  };
  Map<String, dynamic> scene(String id) => {
    'id': id,
    'layers': [layer('one'), layer('two')],
    'masterGain': 1,
    'drone': {
      'enabled': false,
      'root': 0,
      'octave': 1,
      'mode': '',
      'chord': 'root',
      'gain': 0,
      'filterHz': 100,
      'spread': 0,
    },
  };
  return {
    'format': 'polyrhythmer.session',
    'version': 3,
    'revision': 0,
    'title': '',
    'transport': {
      'beatUnit': 'quarter-note',
      'bpm': 20,
      'practiceCycleBeats': {'numerator': 1, 'denominator': 16},
    },
    'referenceClick': {'subdivision': 0},
    'randomSeed': 0,
    'scenes': [scene('A'), scene('B')],
    'defaultSceneId': 'A',
    'presentation': {'visualMode': 'circle'},
  };
}

/// The same document as stored by v2: layers carry a `sound` id.
Map<String, dynamic> v2Fixture([String sound = 'wood']) {
  final doc = jsonDecode(jsonEncode(fixture())) as Map<String, dynamic>;
  doc['version'] = 2;
  for (final scene in doc['scenes'] as List) {
    for (final layer in scene['layers'] as List) {
      (layer as Map<String, dynamic>)
        ..remove('instrumentId')
        ..remove('pitch')
        ..['sound'] = sound;
    }
  }
  return doc;
}

Map<String, dynamic> sceneAt(Map<String, dynamic> doc, int index) =>
    (doc['scenes'] as List)[index] as Map<String, dynamic>;
Map<String, dynamic> layerAt(Map<String, dynamic> doc, int scene, int layer) =>
    (sceneAt(doc, scene)['layers'] as List)[layer] as Map<String, dynamic>;
Map<String, dynamic> droneAt(Map<String, dynamic> doc) =>
    sceneAt(doc, 0)['drone'] as Map<String, dynamic>;
Map<String, dynamic> mixAt(Map<String, dynamic> doc) =>
    layerAt(doc, 0, 0)['mix'] as Map<String, dynamic>;
Map<String, dynamic> stepAt(Map<String, dynamic> doc) =>
    ((layerAt(doc, 0, 0)['pattern'] as Map<String, dynamic>)['steps']
            as List)[0]
        as Map<String, dynamic>;

void main() {
  ParseResult<SessionDocument> parse(Map<String, dynamic> doc) =>
      parseSessionDocument(jsonEncode(doc));
  void valid(void Function(Map<String, dynamic>) change) {
    final doc = jsonDecode(jsonEncode(fixture())) as Map<String, dynamic>;
    change(doc);
    expect(parse(doc).isSuccess, true, reason: jsonEncode(doc));
  }

  void invalid(void Function(Map<String, dynamic>) change, [String? path]) {
    final doc = jsonDecode(jsonEncode(fixture())) as Map<String, dynamic>;
    change(doc);
    final result = parse(doc);
    expect(result.isSuccess, false, reason: jsonEncode(doc));
    expect(result.errors, isNotEmpty);
    if (path != null) expect(result.errors.first.path, contains(path));
  }

  test('document and envelope serialize and parse with value equality', () {
    final doc = parse(fixture()).value!;
    expect(parseSessionDocument(doc.serialize()).value, doc);
    final envelope = SessionExportEnvelope(
      exportedAt: '2026-10-02T12:00:00Z',
      createdWithVersion: '1.0',
      session: doc,
    );
    expect(parseSessionEnvelope(envelope.serialize()).value, envelope);
    expect(doc.scenes[0].layers, isA<List<RhythmLayer>>());
    expect(() => doc.scenes.add(doc.scenes[0]), throwsUnsupportedError);
    expect(() => doc.scenes[0].layers.clear(), throwsUnsupportedError);
    expect(
      () => doc.scenes[0].layers[0].pattern.steps.clear(),
      throwsUnsupportedError,
    );
  });

  test('numeric boundaries and rejected adjacent values', () {
    for (final n in [20, 300]) {
      valid((d) => (d['transport'] as Map)['bpm'] = n);
    }
    for (final n in [19.99, 300.01, '20']) {
      invalid((d) => (d['transport'] as Map)['bpm'] = n);
    }
    for (final n in [0, 4294967295]) {
      valid((d) => d['randomSeed'] = n);
    }
    valid((d) => d['randomSeed'] = 1.0);
    for (final n in [-1, 4294967296, 0.5]) {
      invalid((d) => d['randomSeed'] = n);
    }
    for (final n in [0, 6]) {
      valid((d) => (d['referenceClick'] as Map)['subdivision'] = n);
    }
    for (final n in [-1, 7, 1.5]) {
      invalid((d) => (d['referenceClick'] as Map)['subdivision'] = n);
    }
    for (final n in [0, 1]) {
      valid((d) => stepAt(d)['velocity'] = n);
      valid((d) => stepAt(d)['probability'] = n);
      valid((d) => mixAt(d)['gain'] = n);
      valid((d) => droneAt(d)['spread'] = n);
    }
    for (final n in [-0.001, 1.001]) {
      invalid((d) => stepAt(d)['velocity'] = n);
      invalid((d) => stepAt(d)['probability'] = n);
      invalid((d) => mixAt(d)['gain'] = n);
      invalid((d) => droneAt(d)['spread'] = n);
    }
    for (final n in [-1, 1]) {
      valid((d) => mixAt(d)['pan'] = n);
    }
    for (final n in [-1.01, 1.01]) {
      invalid((d) => mixAt(d)['pan'] = n);
    }
    for (final n in [0, 11]) {
      valid((d) => droneAt(d)['root'] = n);
    }
    for (final n in [-1, 12]) {
      invalid((d) => droneAt(d)['root'] = n);
    }
    for (final n in [1, 5]) {
      valid((d) => droneAt(d)['octave'] = n);
    }
    for (final n in [0, 6]) {
      invalid((d) => droneAt(d)['octave'] = n);
    }
    for (final n in [100, 8000]) {
      valid((d) => droneAt(d)['filterHz'] = n);
    }
    for (final n in [99, 8001]) {
      invalid((d) => droneAt(d)['filterHz'] = n);
    }
  });

  test('rational bounds, canonical form and density', () {
    valid(
      (d) => (d['transport'] as Map)['practiceCycleBeats'] = {
        'numerator': 32,
        'denominator': 1,
      },
    );
    valid(
      (d) => (layerAt(d, 0, 0)['pattern'] as Map)['durationBeats'] = {
        'numerator': 1,
        'denominator': 1,
      },
    );
    for (final pair in [
      {'numerator': 1, 'denominator': 17},
      {'numerator': 33, 'denominator': 1},
      {'numerator': 2, 'denominator': 2},
      {'numerator': 0, 'denominator': 1},
      {'numerator': 1, 'denominator': 0},
      {'numerator': -1, 'denominator': 1},
      {'numerator': 1025, 'denominator': 32},
      {'numerator': 1, 'denominator': 33},
    ]) {
      invalid((d) => (d['transport'] as Map)['practiceCycleBeats'] = pair);
    }
    invalid((d) {
      (layerAt(d, 0, 0)['pattern'] as Map)['durationBeats'] = {
        'numerator': 1,
        'denominator': 16,
      };
    });
  });

  test('scene, layer, step and phase invariants', () {
    invalid((d) => d['scenes'] = [sceneAt(d, 0)]);
    invalid((d) => d['scenes'] = [...(d['scenes'] as List), sceneAt(d, 0)]);
    invalid((d) => (sceneAt(d, 0)['layers'] as List).removeLast());
    valid((d) {
      for (final s in d['scenes'] as List) {
        for (final id in ['three', 'four']) {
          (s['layers'] as List).add(
            jsonDecode(jsonEncode((s['layers'] as List).first))..['id'] = id,
          );
        }
      }
    });
    invalid((d) {
      for (final s in d['scenes'] as List) {
        for (final id in ['three', 'four', 'five']) {
          (s['layers'] as List).add(
            jsonDecode(jsonEncode((s['layers'] as List).first))..['id'] = id,
          );
        }
      }
    });
    valid((d) {
      for (final s in d['scenes'] as List) {
        (s['layers'] as List).add(
          jsonDecode(jsonEncode((s['layers'] as List).first))..['id'] = 'three',
        );
      }
    });
    invalid((d) => (sceneAt(d, 0)['layers'] as List).add(layerAt(d, 0, 0)));
    invalid((d) => layerAt(d, 1, 1)['id'] = 'different');
    invalid((d) => layerAt(d, 0, 0)['id'] = 'bad_id');
    valid((d) {
      for (final s in d['scenes'] as List) {
        (s['layers'] as List)[0]['id'] = 'a' * 64;
      }
    });
    invalid((d) => layerAt(d, 0, 0)['id'] = 'a' * 65);
    valid((d) => layerAt(d, 0, 0)['phaseSteps'] = 1);
    invalid((d) => layerAt(d, 0, 0)['phaseSteps'] = 2);
    invalid((d) => layerAt(d, 0, 0)['phaseSteps'] = -1);
    invalid((d) => (layerAt(d, 0, 0)['pattern'] as Map)['steps'] = []);
    valid((d) => (layerAt(d, 0, 0)['pattern'] as Map)['steps'] = [stepAt(d)]);
    invalid(
      (d) => (layerAt(d, 0, 0)['pattern'] as Map)['steps'] = List.filled(
        33,
        stepAt(d),
      ),
    );
    valid((d) {
      for (final s in d['scenes'] as List) {
        for (final l in s['layers'] as List) {
          (l['pattern'] as Map)['steps'] = List.filled(32, stepAt(d));
        }
      }
    });
  });

  test('swing grid requires every enabled step on grid', () {
    valid((d) => layerAt(d, 0, 0)['swing'] = {'grid': 'eighth', 'amount': 1});
    invalid((d) => layerAt(d, 0, 0)['swing'] = {'grid': 'off', 'amount': 0.1});
    invalid((d) {
      (layerAt(d, 0, 0)['pattern'] as Map)['durationBeats'] = {
        'numerator': 1,
        'denominator': 1,
      };
      (layerAt(d, 0, 0)['pattern'] as Map)['steps'] = List.filled(4, stepAt(d));
      layerAt(d, 0, 0)['swing'] = {'grid': 'eighth', 'amount': 0.5};
    });
  });

  test('untrusted JSON fails with typed errors and paths', () {
    for (final raw in [
      '',
      '{',
      '[]',
      'null',
      'NaN',
      'Infinity',
      '{"x":-0}',
      '{"x":-0.0}',
    ]) {
      expect(parseSessionDocument(raw).isSuccess, false, reason: raw);
    }
    invalid((d) => d['unknown'] = 1, 'unknown');
    invalid((d) => mixAt(d)['unexpected'] = true, 'unexpected');
    invalid((d) => stepAt(d)['constructor'] = 1, 'constructor');
    invalid((d) => d['title'] = 'a' * 81, 'title');
    invalid((d) => d['title'] = 'bad\nname', 'title');
    final negativeZero = jsonEncode(fixture())
        .replaceFirst('"bpm":20', '"bpm":-0');
    expect(parseSessionDocument(negativeZero).isSuccess, false);
    invalid((d) => d['version'] = 4, 'version');
    expect(
      parse({...fixture(), 'version': 4}).errors.first.code,
      'unsupported_version',
    );
    final deep = '${'[' * 17}0${']' * 17}';
    expect(parseSessionDocument(deep).errors.first.message, contains('depth'));
    expect(
      parseSessionDocument(' ' * (128 * 1024 + 1)).errors.first.message,
      contains('128 KiB'),
    );
    // Raw code-point counting can reject a decomposed title accepted after NFC.
    invalid((d) => d['title'] = 'e\u0301' * 41, 'title');
    valid((d) => d['title'] = 'é' * 80);
  });

  test('envelope requires exact fields and supported versions', () {
    final base = SessionExportEnvelope(
      exportedAt: '2026-10-02T12:00:00Z',
      createdWithVersion: '1.0',
      session: parse(fixture()).value!,
    ).toJson();
    Map<String, dynamic> copy() =>
        jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    final wrongVersion = copy()..['envelopeVersion'] = 2;
    expect(
      parseSessionEnvelope(jsonEncode(wrongVersion)).errors.first.code,
      'unsupported_version',
    );
    final extra = copy()..['owner'] = 'x';
    expect(
      parseSessionEnvelope(jsonEncode(extra)).errors.first.path,
      contains('owner'),
    );
    final badTime = copy()..['exportedAt'] = 'not UTC';
    expect(parseSessionEnvelope(jsonEncode(badTime)).isSuccess, false);
    final utcOffset = copy()..['exportedAt'] = '2026-10-02T12:00:00+00:00';
    expect(parseSessionEnvelope(jsonEncode(utcOffset)).isSuccess, true);
    final rolledDate = copy()..['exportedAt'] = '2026-02-30T12:00:00Z';
    expect(parseSessionEnvelope(jsonEncode(rolledDate)).isSuccess, false);
    final longVersion = copy();
    (longVersion['createdWith'] as Map)['version'] = 'a' * 33;
    expect(parseSessionEnvelope(jsonEncode(longVersion)).isSuccess, false);
    final badApp = copy();
    (badApp['createdWith'] as Map)['app'] = 'Other';
    expect(parseSessionEnvelope(jsonEncode(badApp)).isSuccess, false);
  });

  test('constructor validation reports the exact field path', () {
    final bpm = fixture();
    (bpm['transport'] as Map)['bpm'] = 500;
    expect(parse(bpm).errors.single.path, r'$.transport.bpm');

    final subdivision = fixture();
    (subdivision['referenceClick'] as Map)['subdivision'] = 7;
    expect(
      parse(subdivision).errors.single.path,
      r'$.referenceClick.subdivision',
    );

    final visualMode = fixture();
    (visualMode['presentation'] as Map)['visualMode'] = 'unknown';
    expect(parse(visualMode).errors.single.path, r'$.presentation.visualMode');

    final velocity = jsonDecode(jsonEncode(fixture())) as Map<String, dynamic>;
    stepAt(velocity)['velocity'] = 1.1;
    expect(
      parse(velocity).errors.single.path,
      r'$.scenes[0].layers[0].pattern.steps[0].velocity',
    );

    final envelope = SessionExportEnvelope(
      exportedAt: '2026-10-02T12:00:00Z',
      createdWithVersion: '1.0',
      session: parse(fixture()).value!,
    ).toJson();
    final badTime = jsonDecode(jsonEncode(envelope)) as Map<String, dynamic>;
    badTime['exportedAt'] = 'invalid';
    expect(
      parseSessionEnvelope(jsonEncode(badTime)).errors.single.path,
      r'$.exportedAt',
    );
    final badVersion = jsonDecode(jsonEncode(envelope)) as Map<String, dynamic>;
    (badVersion['createdWith'] as Map)['version'] = 'a' * 33;
    expect(
      parseSessionEnvelope(jsonEncode(badVersion)).errors.single.path,
      r'$.createdWith.version',
    );
  });

  test('unsupported versions take priority over unknown fields', () {
    final document = fixture()
      ..['version'] = 4
      ..['futureField'] = true;
    final documentError = parse(document).errors.single;
    expect(documentError.code, 'unsupported_version');
    expect(documentError.path, r'$.version');

    final envelope = SessionExportEnvelope(
      exportedAt: '2026-10-02T12:00:00Z',
      createdWithVersion: '1.0',
      session: parse(fixture()).value!,
    ).toJson();
    final newerEnvelope =
        jsonDecode(jsonEncode(envelope)) as Map<String, dynamic>;
    newerEnvelope['envelopeVersion'] = 2;
    newerEnvelope['futureField'] = true;
    final envelopeError = parseSessionEnvelope(jsonEncode(newerEnvelope))
        .errors
        .single;
    expect(envelopeError.code, 'unsupported_version');
    expect(envelopeError.path, r'$.envelopeVersion');

    final newerSession =
        jsonDecode(jsonEncode(envelope)) as Map<String, dynamic>;
    (newerSession['session'] as Map)['version'] = 4;
    newerSession['futureField'] = true;
    final sessionError = parseSessionEnvelope(jsonEncode(newerSession))
        .errors
        .single;
    expect(sessionError.code, 'unsupported_version');
    expect(sessionError.path, r'$.session.version');
  });

  group('v3 layer instrument reference', () {
    test('v3 document keeps instrumentId and pitch and round-trips', () {
      final doc = parse(fixture()).value!;
      final layer = doc.scenes[0].layers[0];
      expect((layer.instrumentId, layer.pitch), ('factory-wood', 69));
      final json = jsonDecode(doc.serialize()) as Map<String, dynamic>;
      expect(json['version'], 3);
      expect(layerAt(json, 0, 0).containsKey('sound'), false);
      expect(layerAt(json, 0, 0)['instrumentId'], 'factory-wood');
      expect(layerAt(json, 0, 0)['pitch'], 69);
      expect(parseSessionDocument(doc.serialize()).value, doc);
    });

    test('an instrument id the core cannot resolve is accepted', () {
      valid((d) => layerAt(d, 0, 0)['instrumentId'] = 'my-missing-1');
    });

    test('instrumentId follows the library id rule', () {
      valid((d) => layerAt(d, 0, 0)['instrumentId'] = 'a' * 64);
      for (final id in ['', 'a' * 65, 'bad_id', 'has space', 'zażółć', 7]) {
        invalid((d) => layerAt(d, 0, 0)['instrumentId'] = id, 'instrumentId');
      }
      final bad = fixture();
      layerAt(bad, 0, 1)['instrumentId'] = 'bad_id';
      expect(
        parse(bad).errors.single.path,
        r'$.scenes[0].layers[1].instrumentId',
      );
    });

    test('pitch is an integer MIDI note 24..107', () {
      for (final n in [24, 69, 107]) {
        valid((d) => layerAt(d, 0, 0)['pitch'] = n);
      }
      valid((d) => layerAt(d, 0, 0)['pitch'] = 60.0);
      for (final n in [23, 108, -1, 0, 60.5, '60', null]) {
        invalid((d) => layerAt(d, 0, 0)['pitch'] = n, 'pitch');
      }
      final bad = fixture();
      layerAt(bad, 1, 0)['pitch'] = 108;
      expect(parse(bad).errors.single.path, r'$.scenes[1].layers[0].pitch');
    });

    test('layers of the two scenes may differ in instrument and pitch', () {
      valid((d) {
        layerAt(d, 1, 0)['instrumentId'] = 'factory-bell';
        layerAt(d, 1, 0)['pitch'] = 84;
      });
    });

    test('v3 rejects the old sound field and missing new fields', () {
      invalid((d) => layerAt(d, 0, 0)['sound'] = 'wood', 'sound');
      invalid((d) => layerAt(d, 0, 0).remove('instrumentId'), 'instrumentId');
      invalid((d) => layerAt(d, 0, 0).remove('pitch'), 'pitch');
    });
  });

  group('v2 to v3 migration', () {
    const expected = {
      'wood': 'factory-wood',
      'sine': 'factory-sine',
      'bell': 'factory-bell',
    };

    test('every v2 sound maps to a factory instrument and default pitch', () {
      for (final entry in expected.entries) {
        final result = parse(v2Fixture(entry.key));
        expect(result.isSuccess, true, reason: '${result.errors}');
        for (final scene in result.value!.scenes) {
          for (final layer in scene.layers) {
            expect(layer.instrumentId, entry.value);
            expect(layer.pitch, defaultMigratedPitch);
          }
        }
      }
      expect(defaultMigratedPitch, 69);
    });

    test('everything except the sound is unchanged in meaning', () {
      final migrated = parse(v2Fixture()).value!;
      final native = parse(fixture()).value!;
      expect(migrated, native);
      expect(migrated.serialize(), native.serialize());
    });

    test('parsing never changes the source; the next save writes v3', () {
      final source = jsonEncode(v2Fixture());
      final doc = parseSessionDocument(source).value!;
      expect((jsonDecode(source) as Map)['version'], 2);
      expect((jsonDecode(doc.serialize()) as Map)['version'], 3);
    });

    test('migration is idempotent', () {
      final once = parse(v2Fixture()).value!;
      final twice = parseSessionDocument(once.serialize()).value!;
      expect(twice, once);
      expect(twice.serialize(), once.serialize());
      final json = migrateSessionJson(v2Fixture());
      expect(migrateSessionJson(json), json);
      expect(json['version'], 3);
    });

    test('migrateSessionJson does not mutate its input', () {
      final input = v2Fixture();
      final snapshot = jsonEncode(input);
      migrateSessionJson(input);
      expect(jsonEncode(input), snapshot);
    });

    test('unknown or malformed v2 sound ids are rejected with the path', () {
      for (final sound in ['drum', '', 'Wood', 'factory-wood']) {
        final result = parse(v2Fixture(sound));
        expect(result.isSuccess, false, reason: sound);
        expect(result.errors.single.path, r'$.scenes[0].layers[0].sound');
        expect(result.errors.single.code, 'validation_error');
      }
      final notString = v2Fixture();
      layerAt(notString, 0, 0)['sound'] = 3;
      expect(parse(notString).errors.single.path, endsWith('.sound'));
    });

    test('a v2 layer may not carry v3 fields or lack a sound', () {
      final extra = v2Fixture();
      layerAt(extra, 0, 0)['pitch'] = 60;
      expect(parse(extra).errors.single.path, endsWith('.pitch'));
      final missing = v2Fixture();
      layerAt(missing, 0, 0).remove('sound');
      expect(parse(missing).errors.single.path, endsWith('.sound'));
    });

    test('v2 documents inside an export envelope load too', () {
      final envelope = {
        'format': 'polyrhythmer.session-export',
        'envelopeVersion': 1,
        'exportedAt': '2026-10-02T12:00:00Z',
        'createdWith': {'app': 'Polyrhythmer', 'version': '1.0'},
        'session': v2Fixture('bell'),
      };
      final result = parseSessionEnvelope(jsonEncode(envelope));
      expect(result.isSuccess, true, reason: '${result.errors}');
      expect(
        result.value!.session.scenes[0].layers[0].instrumentId,
        'factory-bell',
      );
      expect((result.value!.toJson()['session'] as Map)['version'], 3);
    });

    test('other v2 validation errors keep their paths', () {
      final doc = v2Fixture();
      (doc['transport'] as Map)['bpm'] = 500;
      expect(parse(doc).errors.single.path, r'$.transport.bpm');
    });
  });
}
