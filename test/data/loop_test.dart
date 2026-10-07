import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/library_item.dart';
import 'package:synesterra/data/repositories/loop.dart';

Map<String, dynamic> roundTripJson(Loop loop) =>
    jsonDecode(jsonEncode(loop.toJson())) as Map<String, dynamic>;

Loop sample({String id = 'loop-a', String name = 'Sample'}) => Loop(
  id: id,
  name: name,
  document: simpleLoopDocument(
    bpm: 90,
    cycleBeats: 2,
    layers: const [
      LoopLayerSpec(instrumentId: 'factory-wood', pitch: 69, hits: 3),
      LoopLayerSpec(instrumentId: 'factory-bell', pitch: 76, hits: 2),
    ],
  ),
);

void main() {
  group('Loop JSON', () {
    test('round trips through JSON text', () {
      final loop = sample();
      expect(Loop.fromJson(roundTripJson(loop)), loop);
    });

    test('writes a versioned wrapper around a v3 session', () {
      final json = roundTripJson(sample());
      expect(json.keys, ['format', 'version', 'id', 'name', 'session']);
      expect(json['format'], 'synesterra.loop');
      expect(json['version'], 1);
      expect((json['session'] as Map)['version'], 3);
    });

    test('scene B is a copy of scene A', () {
      final document = sample().document;
      expect(document.scenes[0].layers, document.scenes[1].layers);
    });

    void rejects(
      String reason,
      void Function(Map<String, dynamic> json) change,
      String path,
    ) {
      test('rejects $reason with the JSON path', () {
        final json = roundTripJson(sample());
        change(json);
        expect(
          () => Loop.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              startsWith(path),
            ),
          ),
        );
      });
    }

    rejects('a non-object', (json) => json.clear(), r'$.format');
    rejects('an unknown field', (json) => json['extra'] = 1, r'$.extra');
    rejects('a missing name', (json) => json.remove('name'), r'$.name');
    rejects('a wrong format', (json) => json['format'] = 'x', r'$.format');
    rejects(
      'an unsupported version',
      (json) => json['version'] = 2,
      r'$.version',
    );
    rejects('a bad id', (json) => json['id'] = 'a/b', r'$.id');
    rejects('a blank name', (json) => json['name'] = '  ', r'$.name');
    rejects('a long name', (json) => json['name'] = 'x' * 41, r'$.name');
    rejects(
      'a control character in the name',
      (json) => json['name'] = 'a\u0007',
      r'$.name',
    );
    rejects('a session that is not an object', (json) {
      json['session'] = 'nope';
    }, r'$.session');
    rejects('an invalid session', (json) {
      (json['session'] as Map)['transport']['bpm'] = 400;
    }, r'$.session');
    rejects('a fractional cycle', (json) {
      (json['session'] as Map)['transport']['practiceCycleBeats'] = {
        'numerator': 3,
        'denominator': 2,
      };
    }, r'$.session.transport.practiceCycleBeats');
    rejects('a layer whose period differs from the cycle', (json) {
      final scenes = (json['session'] as Map)['scenes'] as List;
      for (final scene in scenes) {
        ((scene as Map)['layers'] as List)[0]['pattern']['durationBeats'] = {
          'numerator': 4,
          'denominator': 1,
        };
      }
    }, r'$.session.scenes');

    test('a non-map input is rejected', () {
      expect(() => Loop.fromJson('x'), throwsFormatException);
      expect(() => Loop.fromJson(null), throwsFormatException);
    });
  });

  group('Loop values', () {
    test('summarises hits, layers and tempo', () {
      final loop = sample();
      expect(loop.hitsPerLayer, [3, 2]);
      expect(loop.layerCount, 2);
      expect(loop.bpm, 90);
      expect(loop.cycleBeats, 2);
    });

    test('the constructor validates id and name', () {
      expect(() => sample(id: ''), throwsArgumentError);
      expect(() => sample(name: ''), throwsArgumentError);
    });

    test('copyWith renames without touching the document', () {
      final loop = sample();
      final renamed = loop.copyWith(name: 'Other');
      expect(renamed.name, 'Other');
      expect(renamed.id, loop.id);
      expect(renamed.document, loop.document);
    });
  });

  group('factory loops', () {
    test('there are three: 3:2, 5:4 and one with three layers', () {
      expect(factoryLoops.map((l) => l.hitsPerLayer), [
        [3, 2],
        [5, 4],
        [4, 3, 2],
      ]);
      for (final loop in factoryLoops) {
        expect(isFactoryId(loop.id), isTrue, reason: loop.id);
        expect(Loop.fromJson(roundTripJson(loop)), loop);
      }
    });

    test('only use factory instruments', () {
      for (final loop in factoryLoops) {
        for (final layer in loop.document.scenes.first.layers) {
          expect(layer.instrumentId, startsWith('factory-'));
        }
      }
    });
  });

  group('library names and ids', () {
    test('a copy name stays within the limit', () {
      expect(copyName('Two'), 'Two copy');
      expect(copyName('x' * 40).length, lessThanOrEqualTo(40));
      expect(isValidLibraryName(copyName('x' * 40)), isTrue);
    });

    test('new ids follow the id rule and differ', () {
      final a = newLibraryId('loop');
      final b = newLibraryId('loop');
      expect(libraryIdPattern.hasMatch(a), isTrue);
      expect(a, startsWith('loop-'));
      expect(a, isNot(b));
      expect(isFactoryId(a), isFalse);
    });
  });
}
