// Strict JSON readers for library files. Every failure is a FormatException
// whose message starts with the JSON path, as `Instrument.fromJson` does.

Never failJson(String path, String message) =>
    throw FormatException('$path: $message');

/// Returns [value] as an object with exactly [keys]: no unknown and no
/// missing fields.
Map<String, dynamic> jsonObject(Object? value, String path, Set<String> keys) {
  if (value is! Map<String, dynamic>) failJson(path, 'expected an object');
  for (final key in value.keys) {
    if (!keys.contains(key)) failJson('$path.$key', 'unknown field');
  }
  for (final key in keys) {
    if (!value.containsKey(key)) failJson('$path.$key', 'missing field');
  }
  return value;
}

String jsonString(Object? value, String path) =>
    value is String ? value : failJson(path, 'expected a string');

/// A JSON integer; any number written with a fraction or exponent is
/// rejected.
int jsonInt(Object? value, String path) =>
    value is int ? value : failJson(path, 'expected an integer');

List<dynamic> jsonList(Object? value, String path) =>
    value is List<dynamic> ? value : failJson(path, 'expected a list');
