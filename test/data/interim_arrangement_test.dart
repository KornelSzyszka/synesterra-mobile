import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synesterra/data/repositories/interim_arrangement.dart';

InterimArrangement sample({
  String id = 'arr-a',
  String name = 'Song',
  List<InterimArrangementSection>? sections,
}) => InterimArrangement(
  id: id,
  name: name,
  sections:
      sections ??
      [
        InterimArrangementSection(loopId: 'factory-loop-3-2', repeats: 4),
        InterimArrangementSection(loopId: 'loop-x', repeats: 2),
      ],
);

Map<String, dynamic> roundTripJson(InterimArrangement a) =>
    jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;

void main() {
  test('round trips and writes the DOM-089 shape', () {
    final arrangement = sample();
    final json = roundTripJson(arrangement);
    expect(json, {
      'version': 1,
      'id': 'arr-a',
      'name': 'Song',
      'sections': [
        {'loopId': 'factory-loop-3-2', 'repeats': 4},
        {'loopId': 'loop-x', 'repeats': 2},
      ],
    });
    expect(InterimArrangement.fromJson(json), arrangement);
  });

  test('counts sections and repeats', () {
    expect(sample().sections, hasLength(2));
    expect(sample().totalRepeats, 6);
  });

  test('the constructor enforces the limits', () {
    InterimArrangementSection section([int repeats = 1]) =>
        InterimArrangementSection(loopId: 'l', repeats: repeats);
    expect(() => section(0), throwsArgumentError);
    expect(() => section(33), throwsArgumentError);
    expect(section(32).repeats, 32);
    expect(
      () => InterimArrangementSection(loopId: 'a b', repeats: 1),
      throwsArgumentError,
    );
    expect(() => sample(sections: []), throwsArgumentError);
    expect(
      () => sample(sections: List.filled(17, section())),
      throwsArgumentError,
    );
    expect(
      sample(sections: List.filled(16, section())).sections,
      hasLength(16),
    );
    expect(() => sample(name: ' '), throwsArgumentError);
    expect(() => sample(id: ''), throwsArgumentError);
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
        () => InterimArrangement.fromJson(json),
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

  rejects('an unknown field', (json) => json['x'] = 1, r'$.x');
  rejects('a missing id', (json) => json.remove('id'), r'$.id');
  rejects('a wrong version', (json) => json['version'] = 2, r'$.version');
  rejects('a string version', (json) => json['version'] = '1', r'$.version');
  rejects('sections that are not a list', (json) {
    json['sections'] = {};
  }, r'$.sections');
  rejects('an empty section list', (json) {
    json['sections'] = [];
  }, r'$.sections');
  rejects('a fractional repeat', (json) {
    (json['sections'] as List)[1]['repeats'] = 1.5;
  }, r'$.sections[1].repeats');
  rejects('too many repeats', (json) {
    (json['sections'] as List)[0]['repeats'] = 33;
  }, r'$.sections[0].repeats');
  rejects('an unknown section field', (json) {
    (json['sections'] as List)[0]['gain'] = 1;
  }, r'$.sections[0].gain');
  rejects('a bad loop id', (json) {
    (json['sections'] as List)[0]['loopId'] = '';
  }, r'$.sections[0].loopId');

  test('a non-object is rejected', () {
    expect(() => InterimArrangement.fromJson([]), throwsFormatException);
  });
}
