import 'dart:convert';

import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

ArrangementSection sec(String loopId, [int repeats = 1]) =>
    ArrangementSection(loopId: loopId, repeats: repeats);

Arrangement sample() => Arrangement(
  id: 'song-1',
  name: 'First song',
  sections: [sec('loop-a', 2), sec('loop-b', 4)],
);

Map<String, dynamic> json() =>
    jsonDecode(jsonEncode(sample().toJson())) as Map<String, dynamic>;

void expectPath(Object? input, String path) {
  expect(
    () => Arrangement.fromJson(input),
    throwsA(
      isA<FormatException>().having(
        (e) => e.message,
        'message',
        startsWith(path),
      ),
    ),
  );
}

void main() {
  group('construction', () {
    test('accepts boundary values', () {
      expect(
        () => Arrangement(
          id: 'a' * 64,
          name: 'n' * 40,
          sections: List.generate(16, (_) => sec('x' * 64, 32)),
        ),
        returnsNormally,
      );
      expect(
        () => Arrangement(id: 'a', name: 'n', sections: [sec('a')]),
        returnsNormally,
      );
    });

    test('rejects bad values', () {
      Arrangement make({
        String id = 'a',
        String name = 'n',
        List<ArrangementSection>? sections,
      }) => Arrangement(id: id, name: name, sections: sections ?? [sec('a')]);
      for (final id in ['', 'a b', 'a_b', 'a' * 65]) {
        expect(() => make(id: id), throwsArgumentError, reason: id);
      }
      for (final name in ['', '   ', 'n' * 41, 'a\nb']) {
        expect(() => make(name: name), throwsArgumentError, reason: name);
      }
      expect(() => make(sections: []), throwsArgumentError);
      expect(
        () => make(sections: List.generate(17, (_) => sec('a'))),
        throwsArgumentError,
      );
      for (final repeats in [0, 33, -1]) {
        expect(() => sec('a', repeats), throwsArgumentError);
      }
      expect(() => sec('a b'), throwsArgumentError);
      expect(() => sec(''), throwsArgumentError);
    });

    test('sections are copied and unmodifiable', () {
      final list = [sec('a')];
      final arrangement = Arrangement(id: 'a', name: 'n', sections: list);
      list.add(sec('b'));
      expect(arrangement.sections, hasLength(1));
      expect(() => arrangement.sections.add(sec('c')), throwsUnsupportedError);
    });
  });

  group('JSON', () {
    test('round trips and has the documented shape', () {
      expect(sample().toJson(), {
        'version': 1,
        'id': 'song-1',
        'name': 'First song',
        'sections': [
          {'loopId': 'loop-a', 'repeats': 2},
          {'loopId': 'loop-b', 'repeats': 4},
        ],
      });
      expect(Arrangement.fromJson(json()), sample());
      expect(Arrangement.fromJson(json()).hashCode, sample().hashCode);
    });

    test('equality compares every field and section order', () {
      final reordered = Arrangement(
        id: 'song-1',
        name: 'First song',
        sections: [sec('loop-b', 4), sec('loop-a', 2)],
      );
      expect(reordered, isNot(sample()));
      final otherId = Arrangement(
        id: 'song-2',
        name: 'First song',
        sections: sample().sections,
      );
      expect(otherId, isNot(sample()));
    });

    test('rejects non-objects and unknown or missing fields with a path', () {
      expectPath([], r'$: expected an object');
      expectPath(null, r'$: expected an object');
      expectPath({...json(), 'extra': 1}, r'$.extra: unknown field');
      for (final key in ['version', 'id', 'name', 'sections']) {
        expectPath(json()..remove(key), '\$.$key: missing field');
      }
      final bad = json();
      (bad['sections'] as List)[1]['extra'] = true;
      expectPath(bad, r'$.sections[1].extra: unknown field');
      final missing = json();
      (missing['sections'] as List)[0].remove('loopId');
      expectPath(missing, r'$.sections[0].loopId: missing field');
    });

    test('rejects wrong types and versions', () {
      expectPath(json()..['version'] = 2, r'$.version');
      expectPath(json()..['version'] = '1', r'$.version');
      expectPath(json()..['id'] = 5, r'$.id: expected a string');
      expectPath(json()..['name'] = null, r'$.name: expected a string');
      expectPath(json()..['sections'] = {}, r'$.sections: expected a list');
      expectPath(
        json()..['sections'] = [5],
        r'$.sections[0]: expected an object',
      );
      final repeats = json();
      (repeats['sections'] as List)[1]['repeats'] = 2.5;
      expectPath(repeats, r'$.sections[1].repeats: expected an integer');
      final loop = json();
      (loop['sections'] as List)[0]['loopId'] = 7;
      expectPath(loop, r'$.sections[0].loopId: expected a string');
    });

    test('rejects integral doubles where an integer is required', () {
      expectPath(json()..['version'] = 1.0, r'$.version');
      for (final r in [1.0, 2.0]) {
        final bad = json();
        (bad['sections'] as List)[0]['repeats'] = r;
        expectPath(bad, r'$.sections[0].repeats: expected an integer');
      }
      final parsed = jsonDecode(
        '{"version":1.0,"id":"a","name":"n","sections":[]}',
      );
      expectPath(parsed, r'$.version');
    });

    test('rejects out-of-range values with a path', () {
      expectPath(json()..['id'] = 'a b', r'$.id');
      expectPath(json()..['name'] = '  ', r'$.name');
      expectPath(json()..['sections'] = [], r'$.sections');
      expectPath(
        json()
          ..['sections'] = List.generate(
            17,
            (_) => {'loopId': 'a', 'repeats': 1},
          ),
        r'$.sections',
      );
      for (final r in [0, 33]) {
        final bad = json();
        (bad['sections'] as List)[1]['repeats'] = r;
        expectPath(bad, r'$.sections[1].repeats');
      }
      final loop = json();
      (loop['sections'] as List)[1]['loopId'] = 'a/b';
      expectPath(loop, r'$.sections[1].loopId');
    });
  });

  group('sequenceAt', () {
    SequencePosition at(
      List<ArrangementSection> sections,
      int cycle, {
      bool repeatAll = false,
      bool Function(ArrangementSection)? isSkipped,
    }) => sequenceAt(
      sections: sections,
      repeatAll: repeatAll,
      cycleIndex: cycle,
      isSkipped: isSkipped,
    );

    test('single section counts its repeats then is done', () {
      final s = [sec('a', 3)];
      expect(at(s, 0), const SequenceAt(sectionIndex: 0, cycleInSection: 0));
      expect(at(s, 2), const SequenceAt(sectionIndex: 0, cycleInSection: 2));
      expect(at(s, 3), const SequenceDone());
      expect(at(s, 1000), const SequenceDone());
    });

    test('changes section exactly on the cycle start', () {
      final s = [sec('a', 2), sec('b', 3)];
      expect(at(s, 1), const SequenceAt(sectionIndex: 0, cycleInSection: 1));
      expect(at(s, 2), const SequenceAt(sectionIndex: 1, cycleInSection: 0));
      expect(at(s, 4), const SequenceAt(sectionIndex: 1, cycleInSection: 2));
      expect(at(s, 5), const SequenceDone());
    });

    test('max sections of max repeats', () {
      final s = List.generate(16, (_) => sec('a', 32));
      expect(
        at(s, 511),
        const SequenceAt(sectionIndex: 15, cycleInSection: 31),
      );
      expect(at(s, 512), const SequenceDone());
      expect(
        at(s, 512, repeatAll: true),
        const SequenceAt(sectionIndex: 0, cycleInSection: 0),
      );
    });

    test('repeatAll wraps, also far beyond one pass', () {
      final s = [sec('a', 2), sec('b', 1)];
      expect(
        at(s, 3, repeatAll: true),
        const SequenceAt(sectionIndex: 0, cycleInSection: 0),
      );
      expect(
        at(s, 5, repeatAll: true),
        const SequenceAt(sectionIndex: 1, cycleInSection: 0),
      );
      expect(
        at(s, 3 * 1000000 + 1, repeatAll: true),
        const SequenceAt(sectionIndex: 0, cycleInSection: 1),
      );
    });

    test('skipped sections take no cycles and keep original indexes', () {
      final s = [sec('a', 2), sec('missing', 5), sec('c', 2)];
      bool skip(ArrangementSection x) => x.loopId == 'missing';
      expect(
        at(s, 1, isSkipped: skip),
        const SequenceAt(sectionIndex: 0, cycleInSection: 1),
      );
      expect(
        at(s, 2, isSkipped: skip),
        const SequenceAt(sectionIndex: 2, cycleInSection: 0),
      );
      expect(at(s, 4, isSkipped: skip), const SequenceDone());
      expect(
        at(s, 4, repeatAll: true, isSkipped: skip),
        const SequenceAt(sectionIndex: 0, cycleInSection: 0),
      );
    });

    test('a skipped first section is passed over', () {
      final s = [sec('missing', 3), sec('b', 1)];
      expect(
        at(s, 0, isSkipped: (x) => x.loopId == 'missing'),
        const SequenceAt(sectionIndex: 1, cycleInSection: 0),
      );
    });

    test('all skipped is done, with repeatAll too (no spin)', () {
      final s = [sec('a', 2), sec('b', 2)];
      expect(at(s, 0, isSkipped: (_) => true), const SequenceDone());
      expect(
        at(s, 7, repeatAll: true, isSkipped: (_) => true),
        const SequenceDone(),
      );
    });

    test('empty list is done and a negative cycle is an error', () {
      expect(at([], 0, repeatAll: true), const SequenceDone());
      expect(() => at([sec('a')], -1), throwsArgumentError);
    });
  });
}
