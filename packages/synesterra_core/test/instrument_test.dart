import 'dart:convert';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

Instrument sample({
  String id = 'inst-1',
  String name = 'Soft click',
  List<String> tags = const [],
  List<double> harmonics = const [1, 0.5, 0.25],
  int attackMs = 2,
  int decayMs = 200,
  InstrumentEq? eq,
}) => Instrument(
  id: id,
  name: name,
  tags: tags,
  harmonics: harmonics,
  attackMs: attackMs,
  decayMs: decayMs,
  eq: eq,
);

Map<String, dynamic> json() =>
    jsonDecode(jsonEncode(sample(tags: ['click']).toJson()))
        as Map<String, dynamic>;

/// A file as version 1 wrote it, when an instrument still had a pitch.
Map<String, dynamic> v1() => {
  'version': 1,
  'id': 'old-1',
  'name': 'Old click',
  'fundamentalHz': 800.0,
  'harmonics': [1.0, 0.5],
  'envelope': {'attackMs': 1, 'decayMs': 70},
  'eq': {'lowDb': -3.0, 'midDb': 2.0, 'highDb': 0.0},
};

void main() {
  group('construction', () {
    test('keeps its values, defaults the EQ to flat and the tags to none', () {
      final instrument = sample();
      expect(instrument.harmonics, [1, 0.5, 0.25]);
      expect(instrument.eq, InstrumentEq());
      expect(instrument.tags, isEmpty);
    });

    test('an instrument has no pitch of its own', () {
      expect(sample().toJson().containsKey('fundamentalHz'), isFalse);
    });

    test('the harmonic and tag lists cannot be changed from outside', () {
      final harmonics = [1.0, 0.5];
      final tags = ['click'];
      final instrument = sample(harmonics: harmonics, tags: tags);
      harmonics.add(0.1);
      tags.add('wood');
      expect(instrument.harmonics, [1, 0.5]);
      expect(instrument.tags, ['click']);
      expect(() => instrument.harmonics.add(0.1), throwsUnsupportedError);
      expect(() => instrument.tags.add('x'), throwsUnsupportedError);
    });

    final bounds = <String, List<Instrument Function()>>{
      'id': [
        () => sample(id: ''),
        () => sample(id: 'a b'),
        () => sample(id: 'a' * 65),
      ],
      'name': [
        () => sample(name: ''),
        () => sample(name: '   '),
        () => sample(name: 'x' * 41),
        () => sample(name: 'bad\nname'),
      ],
      'harmonics': [
        () => sample(harmonics: const []),
        () => sample(harmonics: List.filled(33, 0.5)),
        () => sample(harmonics: const [0, 0]),
        () => sample(harmonics: const [1, -0.1]),
        () => sample(harmonics: const [1, 1.1]),
        () => sample(harmonics: const [1, double.nan]),
      ],
      'attackMs': [() => sample(attackMs: -1), () => sample(attackMs: 501)],
      'decayMs': [() => sample(decayMs: 19), () => sample(decayMs: 5001)],
      'eq': [
        () => sample(eq: InstrumentEq(lowDb: -12.1)),
        () => sample(eq: InstrumentEq(midDb: 12.1)),
        () => sample(eq: InstrumentEq(highDb: double.nan)),
      ],
      'tags': [
        () => sample(tags: ['Click']),
        () => sample(tags: ['']),
        () => sample(tags: ['a' * 25]),
        () => sample(tags: [' click']),
        () => sample(tags: ['-click']),
        () => sample(tags: ['click_x']),
        () => sample(tags: ['ąę']),
        () => sample(tags: ['a', 'b', 'c', 'd', 'e', 'f', 'g']),
        () => sample(tags: ['click', 'click']),
      ],
    };
    for (final entry in bounds.entries) {
      test('${entry.key} rejects values outside its range', () {
        for (final build in entry.value) {
          expect(build, throwsArgumentError);
        }
      });
    }

    test('accepts both ends of every range', () {
      expect(sample(attackMs: 0, decayMs: 20), isNotNull);
      expect(
        sample(
          attackMs: 500,
          decayMs: 5000,
          harmonics: List.filled(32, 1.0),
          name: 'x' * 40,
          id: 'a' * 64,
          eq: InstrumentEq(lowDb: -12, midDb: 12, highDb: 12),
          tags: ['a' * 24, '0', 'big bell', 'a-b', 'c', 'd'],
        ),
        isNotNull,
      );
      expect(sample(harmonics: const [0, 0.0001]), isNotNull);
    });
  });

  group('tags', () {
    test('normalizeTag lowercases, trims and collapses spaces', () {
      expect(Instrument.normalizeTag('  Click '), 'click');
      expect(Instrument.normalizeTag('Big   Bell'), 'big bell');
      expect(Instrument.normalizeTag('a-b 2'), 'a-b 2');
    });

    test('normalizeTag returns null for anything that is not a tag', () {
      for (final raw in ['', '   ', 'x' * 25, 'ąę', 'a_b', '-a', 'a!']) {
        expect(Instrument.normalizeTag(raw), isNull, reason: raw);
      }
    });

    test('a normalized tag is always accepted', () {
      final tag = Instrument.normalizeTag('  Dark   Wood ')!;
      expect(sample(tags: [tag]).tags, ['dark wood']);
    });

    test('suggestions are all valid tags', () {
      expect(suggestedInstrumentTags, isNotEmpty);
      for (final tag in suggestedInstrumentTags) {
        expect(Instrument.normalizeTag(tag), tag);
      }
      expect(sample(tags: suggestedInstrumentTags.take(6).toList()), isNotNull);
    });
  });

  group('value semantics', () {
    test('equal recipes are equal and share a hash code', () {
      expect(sample(), sample());
      expect(sample().hashCode, sample().hashCode);
      expect(sample(tags: ['a', 'b']), sample(tags: ['a', 'b']));
    });

    test('every field takes part in equality', () {
      final base = sample();
      expect(base.copyWith(id: 'inst-2'), isNot(base));
      expect(base.copyWith(name: 'Other'), isNot(base));
      expect(base.copyWith(tags: ['click']), isNot(base));
      expect(base.copyWith(harmonics: [1, 0.5, 0.26]), isNot(base));
      expect(base.copyWith(attackMs: 3), isNot(base));
      expect(base.copyWith(decayMs: 201), isNot(base));
      expect(base.copyWith(eq: InstrumentEq(highDb: 1)), isNot(base));
    });

    test('tag order matters', () {
      expect(sample(tags: ['a', 'b']), isNot(sample(tags: ['b', 'a'])));
    });

    test('copyWith revalidates', () {
      expect(() => sample().copyWith(decayMs: 1), throwsArgumentError);
      expect(() => sample().copyWith(tags: ['Bad']), throwsArgumentError);
    });
  });

  group('JSON', () {
    test('writes version 2 with tags and no pitch', () {
      final map = sample(tags: ['click']).toJson();
      expect(map['version'], 2);
      expect(map['tags'], ['click']);
      expect(map.containsKey('fundamentalHz'), isFalse);
    });

    test('round trips through encoded text', () {
      final original = sample(
        tags: ['click', 'wood'],
        eq: InstrumentEq(lowDb: -3.5, highDb: 2),
      );
      final restored = Instrument.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored, original);
    });

    test('a version 1 file loads: the pitch is dropped and tags are empty', () {
      final instrument = Instrument.fromJson(v1());
      expect(instrument.id, 'old-1');
      expect(instrument.name, 'Old click');
      expect(instrument.tags, isEmpty);
      expect(instrument.harmonics, [1, 0.5]);
      expect(instrument.decayMs, 70);
      expect(instrument.eq, InstrumentEq(lowDb: -3, midDb: 2));
      expect(instrument.toJson()['version'], 2);
    });

    test('version 1 is still checked: a damaged pitch is rejected', () {
      final map = v1()..['fundamentalHz'] = 'high';
      expect(
        () => Instrument.fromJson(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith(r'$.fundamentalHz'),
          ),
        ),
      );
    });

    test('a version 1 file with tags, or a version 2 file with a pitch, is rejected', () {
      expect(
        () => Instrument.fromJson(v1()..['tags'] = []),
        throwsFormatException,
      );
      expect(
        () => Instrument.fromJson(json()..['fundamentalHz'] = 440.0),
        throwsFormatException,
      );
    });

    test('an unknown or missing version is reported', () {
      for (final version in [0, 3, '2', null]) {
        final map = json()..['version'] = version;
        expect(
          () => Instrument.fromJson(map),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              startsWith(r'$.version'),
            ),
          ),
          reason: '$version',
        );
      }
      final missing = json()..remove('version');
      expect(
        () => Instrument.fromJson(missing),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith(r'$.version'),
          ),
        ),
      );
    });

    final malformed = <String, void Function(Map<String, dynamic>)>{
      r'$.id': (m) => m['id'] = 5,
      r'$.name': (m) => m['name'] = null,
      r'$.tags': (m) => m['tags'] = 'click',
      r'$.tags[0]': (m) => m['tags'] = [5],
      r'$.harmonics': (m) => m['harmonics'] = 'x',
      r'$.harmonics[1]': (m) => m['harmonics'] = [1, 'x'],
      r'$.envelope': (m) => m['envelope'] = [],
      r'$.envelope.attackMs': (m) => (m['envelope'] as Map)['attackMs'] = 1.5,
      r'$.envelope.decayMs': (m) => (m['envelope'] as Map).remove('decayMs'),
      r'$.eq.lowDb': (m) => (m['eq'] as Map)['lowDb'] = 'loud',
      r'$.extra': (m) => m['extra'] = 1,
      r'$.eq.extra': (m) => (m['eq'] as Map)['extra'] = 1,
      r'$.eq': (m) => m.remove('eq'),
      r'$.tags ': (m) => m.remove('tags'),
    };
    for (final entry in malformed.entries) {
      test('names ${entry.key} when it is malformed', () {
        final map = json();
        entry.value(map);
        expect(
          () => Instrument.fromJson(map),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              startsWith(entry.key.trim()),
            ),
          ),
        );
      });
    }

    test('reports range violations as FormatException', () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (m) => m['harmonics'] = [0, 0],
        (m) => (m['envelope'] as Map)['decayMs'] = 1,
        (m) => (m['eq'] as Map)['midDb'] = 40.0,
        (m) => m['name'] = '',
        (m) => m['tags'] = ['Not Valid'],
        (m) => m['tags'] = ['a', 'a'],
      ]) {
        final map = json();
        change(map);
        expect(() => Instrument.fromJson(map), throwsFormatException);
      }
    });

    test('rejects input that is not an object', () {
      for (final input in <Object?>[null, 3, 'x', <Object?>[]]) {
        expect(() => Instrument.fromJson(input), throwsFormatException);
      }
    });
  });

  group('factory instruments', () {
    test('are valid, unique, tagged and survive a JSON round trip', () {
      expect(factoryInstruments.map((i) => i.id), [
        'factory-wood',
        'factory-sine',
        'factory-bell',
      ]);
      for (final instrument in factoryInstruments) {
        expect(instrument.tags, isNotEmpty);
        expect(
          Instrument.fromJson(jsonDecode(jsonEncode(instrument.toJson()))),
          instrument,
        );
      }
      expect(() => factoryInstruments.add(sample()), throwsUnsupportedError);
    });
  });
}
