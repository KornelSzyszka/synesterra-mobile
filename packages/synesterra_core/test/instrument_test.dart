import 'dart:convert';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

Instrument sample({
  String id = 'inst-1',
  String name = 'Soft click',
  double fundamentalHz = 440,
  List<double> harmonics = const [1, 0.5, 0.25],
  int attackMs = 2,
  int decayMs = 200,
  InstrumentEq? eq,
}) => Instrument(
  id: id,
  name: name,
  fundamentalHz: fundamentalHz,
  harmonics: harmonics,
  attackMs: attackMs,
  decayMs: decayMs,
  eq: eq,
);

Map<String, dynamic> json() =>
    jsonDecode(jsonEncode(sample().toJson())) as Map<String, dynamic>;

void main() {
  group('construction', () {
    test('keeps its values and defaults the EQ to flat', () {
      final instrument = sample();
      expect(instrument.harmonics, [1, 0.5, 0.25]);
      expect(instrument.eq, InstrumentEq());
    });

    test('the harmonic list cannot be changed from outside', () {
      final source = [1.0, 0.5];
      final instrument = sample(harmonics: source);
      source.add(0.1);
      expect(instrument.harmonics, [1, 0.5]);
      expect(() => instrument.harmonics.add(0.1), throwsUnsupportedError);
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
      'fundamentalHz': [
        () => sample(fundamentalHz: 39.9),
        () => sample(fundamentalHz: 2000.1),
        () => sample(fundamentalHz: double.nan),
        () => sample(fundamentalHz: double.infinity),
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
    };
    for (final entry in bounds.entries) {
      test('${entry.key} rejects values outside its range', () {
        for (final build in entry.value) {
          expect(build, throwsArgumentError);
        }
      });
    }

    test('accepts both ends of every range', () {
      expect(sample(fundamentalHz: 40, attackMs: 0, decayMs: 20), isNotNull);
      expect(
        sample(
          fundamentalHz: 2000,
          attackMs: 500,
          decayMs: 5000,
          harmonics: List.filled(32, 1.0),
          name: 'x' * 40,
          id: 'a' * 64,
          eq: InstrumentEq(lowDb: -12, midDb: 12, highDb: 12),
        ),
        isNotNull,
      );
      expect(sample(harmonics: const [0, 0.0001]), isNotNull);
    });
  });

  group('value semantics', () {
    test('equal recipes are equal and share a hash code', () {
      expect(sample(), sample());
      expect(sample().hashCode, sample().hashCode);
    });

    test('every field takes part in equality', () {
      final base = sample();
      expect(base.copyWith(id: 'inst-2'), isNot(base));
      expect(base.copyWith(name: 'Other'), isNot(base));
      expect(base.copyWith(fundamentalHz: 441), isNot(base));
      expect(base.copyWith(harmonics: [1, 0.5, 0.26]), isNot(base));
      expect(base.copyWith(attackMs: 3), isNot(base));
      expect(base.copyWith(decayMs: 201), isNot(base));
      expect(base.copyWith(eq: InstrumentEq(highDb: 1)), isNot(base));
    });

    test('copyWith revalidates', () {
      expect(() => sample().copyWith(decayMs: 1), throwsArgumentError);
    });
  });

  group('JSON', () {
    test('round trips through encoded text', () {
      final original = sample(eq: InstrumentEq(lowDb: -3.5, highDb: 2));
      final restored = Instrument.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored, original);
    });

    test('accepts whole numbers where doubles are expected', () {
      final map = json()..['fundamentalHz'] = 440;
      expect(Instrument.fromJson(map).fundamentalHz, 440);
    });

    final malformed = <String, void Function(Map<String, dynamic>)>{
      r'$.version': (m) => m['version'] = 2,
      r'$.id': (m) => m['id'] = 5,
      r'$.name': (m) => m['name'] = null,
      r'$.fundamentalHz': (m) => m['fundamentalHz'] = '440',
      r'$.harmonics': (m) => m['harmonics'] = 'x',
      r'$.harmonics[1]': (m) => m['harmonics'] = [1, 'x'],
      r'$.envelope': (m) => m['envelope'] = [],
      r'$.envelope.attackMs': (m) => (m['envelope'] as Map)['attackMs'] = 1.5,
      r'$.envelope.decayMs': (m) => (m['envelope'] as Map).remove('decayMs'),
      r'$.eq.lowDb': (m) => (m['eq'] as Map)['lowDb'] = 'loud',
      r'$.extra': (m) => m['extra'] = 1,
      r'$.eq.extra': (m) => (m['eq'] as Map)['extra'] = 1,
      r'$.eq': (m) => m.remove('eq'),
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
              startsWith(entry.key),
            ),
          ),
        );
      });
    }

    test('reports range violations as FormatException', () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (m) => m['fundamentalHz'] = 5000.0,
        (m) => m['harmonics'] = [0, 0],
        (m) => (m['envelope'] as Map)['decayMs'] = 1,
        (m) => (m['eq'] as Map)['midDb'] = 40.0,
        (m) => m['name'] = '',
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
    test('are valid, unique and survive a JSON round trip', () {
      expect(factoryInstruments.map((i) => i.id), [
        'factory-wood',
        'factory-sine',
        'factory-bell',
      ]);
      for (final instrument in factoryInstruments) {
        expect(
          Instrument.fromJson(jsonDecode(jsonEncode(instrument.toJson()))),
          instrument,
        );
      }
      expect(() => factoryInstruments.add(sample()), throwsUnsupportedError);
    });
  });
}
