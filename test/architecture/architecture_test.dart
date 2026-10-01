import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'architecture_scan.dart';

void main() {
  test('repository follows ADR 0001 rules R1-R9', () {
    final violations = scanArchitecture(Directory.current);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('valid sibling imports and pure Dart packages are allowed', () {
    final violations = scanArchitecture(
      Directory('test/architecture/fixtures/passing'),
    );
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('R8 does not blame an edge leading into a cycle', () {
    final violations = scanArchitecture(
      Directory('test/architecture/fixtures/r8'),
    ).where((violation) => violation.rule == 'R8');
    expect(violations, hasLength(2));
    expect(violations.any((v) => v.file.endsWith('lead_in.dart')), isFalse);
    expect(violations.map((v) => v.file), contains('lib/app/entry.dart'));
    expect(violations.map((v) => v.file), contains('lib/shared/helper.dart'));
  });

  for (var number = 1; number <= 9; number++) {
    final rule = 'R$number';
    test('$rule fixture reports its file and rule', () {
      final fixture = Directory('test/architecture/fixtures/r$number');
      final violations = scanArchitecture(fixture);
      expect(
        violations.where((violation) => violation.rule == rule),
        isNotEmpty,
        reason: '$rule fixture must fail',
      );
      expect(
        violations.any(
          (v) =>
              v.toString().contains('bad.dart') ||
              (number == 7 && v.toString().contains('main.dart')) ||
              (number == 8 && v.toString().contains('entry.dart')),
        ),
        isTrue,
      );
    });
  }
}
