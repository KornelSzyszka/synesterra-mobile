import 'package:synesterra_core/synesterra_core.dart';
import 'package:test/test.dart';

void main() {
  test('public library exposes the core identity', () {
    expect(corePackageName, 'synesterra_core');
  });
}
