import 'dart:convert';

import '../harmony/drone.dart';
import '../rhythm/rhythm_values.dart';
import 'session_document.dart';

class ValidationError {
  const ValidationError(this.path, this.code, this.message);
  final String path;
  final String code;
  final String message;
  @override
  String toString() => '$path: $code: $message';
}

class ParseResult<T> {
  const ParseResult.success(this.value) : errors = const [];
  const ParseResult.failure(this.errors) : value = null;
  final T? value;
  final List<ValidationError> errors;
  bool get isSuccess => value != null;
}

class SessionExportEnvelope {
  SessionExportEnvelope({
    required this.exportedAt,
    required this.createdWithVersion,
    required this.session,
  }) {
    final timestamp = DateTime.tryParse(exportedAt);
    if (!_utcTimestamp.hasMatch(exportedAt) ||
        timestamp == null ||
        timestamp.year != int.parse(exportedAt.substring(0, 4)) ||
        timestamp.month != int.parse(exportedAt.substring(5, 7)) ||
        timestamp.day != int.parse(exportedAt.substring(8, 10)) ||
        timestamp.hour != int.parse(exportedAt.substring(11, 13)) ||
        timestamp.minute != int.parse(exportedAt.substring(14, 16)) ||
        timestamp.second != int.parse(exportedAt.substring(17, 19))) {
      throw ArgumentError.value(exportedAt, 'exportedAt');
    }
    if (createdWithVersion.isEmpty ||
        createdWithVersion.runes.length > 32 ||
        createdWithVersion.runes.any((rune) => rune > 0x7f)) {
      throw ArgumentError.value(createdWithVersion, 'createdWithVersion');
    }
    if (utf8.encode(jsonEncode(toJson())).length > 128 * 1024) {
      throw ArgumentError('Export exceeds 128 KiB');
    }
  }
  static final _utcTimestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|\+00:00)$',
  );
  final String exportedAt;
  final String createdWithVersion;
  final SessionDocument session;
  Map<String, Object> toJson() => {
    'format': 'polyrhythmer.session-export',
    'envelopeVersion': 1,
    'exportedAt': exportedAt,
    'createdWith': {'app': 'Polyrhythmer', 'version': createdWithVersion},
    'session': session.toJson(),
  };
  String serialize() {
    final json = jsonEncode(toJson());
    if (utf8.encode(json).length > 128 * 1024) {
      throw StateError('Export exceeds 128 KiB');
    }
    return json;
  }

  @override
  bool operator ==(Object other) =>
      other is SessionExportEnvelope &&
      exportedAt == other.exportedAt &&
      createdWithVersion == other.createdWithVersion &&
      session == other.session;
  @override
  int get hashCode => Object.hash(exportedAt, createdWithVersion, session);
}

class _Invalid implements Exception {
  _Invalid(this.error);
  final ValidationError error;
}

Never _fail(String path, String code, String message) =>
    throw _Invalid(ValidationError(path, code, message));

Map<String, dynamic> _object(Object? input, String path, Set<String> keys) {
  if (input is! Map<String, dynamic>) {
    _fail(path, 'validation_error', 'Expected object');
  }
  for (final key in input.keys) {
    if (!keys.contains(key)) {
      _fail('$path.$key', 'validation_error', 'Unknown field');
    }
  }
  for (final key in keys) {
    if (!input.containsKey(key)) {
      _fail('$path.$key', 'validation_error', 'Missing field');
    }
  }
  return input;
}

List<dynamic> _list(Object? value, String path) {
  if (value is! List<dynamic>) {
    _fail(path, 'validation_error', 'Expected array');
  }
  return value;
}

String _string(Object? value, String path) {
  if (value is! String) _fail(path, 'validation_error', 'Expected string');
  return value;
}

bool _bool(Object? value, String path) {
  if (value is! bool) _fail(path, 'validation_error', 'Expected boolean');
  return value;
}

int _int(Object? value, String path) {
  if (value is! num ||
      !value.isFinite ||
      value == 0 && value.isNegative ||
      value.abs() > 0xffffffff ||
      value % 1 != 0) {
    _fail(path, 'validation_error', 'Expected integer');
  }
  return value.toInt();
}

num _number(Object? value, String path) {
  if (value is! num || !value.isFinite || value == 0 && value.isNegative) {
    _fail(path, 'validation_error', 'Expected finite number');
  }
  return value;
}

T _construct<T>(String path, T Function() create) {
  try {
    return create();
  } on ArgumentError catch (error) {
    _fail(
      path,
      'validation_error',
      error.message?.toString() ?? 'Invalid value',
    );
  }
}

Rational _rational(Object? raw, String path) {
  final map = _object(raw, path, {'numerator', 'denominator'});
  return _construct(
    path,
    () => Rational(
      _int(map['numerator'], '$path.numerator'),
      _int(map['denominator'], '$path.denominator'),
    ),
  );
}

PatternStep _step(Object? raw, String path) {
  final map = _object(raw, path, {
    'enabled',
    'velocity',
    'accent',
    'probability',
  });
  return _construct(
    path,
    () => PatternStep(
      enabled: _bool(map['enabled'], '$path.enabled'),
      velocity: _number(map['velocity'], '$path.velocity'),
      accent: _bool(map['accent'], '$path.accent'),
      probability: _number(map['probability'], '$path.probability'),
    ),
  );
}

Pattern _pattern(Object? raw, String path) {
  final map = _object(raw, path, {'durationBeats', 'steps'});
  final list = _list(map['steps'], '$path.steps');
  if (list.isEmpty || list.length > 32) {
    _fail('$path.steps', 'validation_error', 'Expected 1..32 steps');
  }
  return _construct(
    path,
    () => Pattern(
      durationBeats: _rational(map['durationBeats'], '$path.durationBeats'),
      steps: [
        for (var i = 0; i < list.length; i++) _step(list[i], '$path.steps[$i]'),
      ],
    ),
  );
}

Swing _swing(Object? raw, String path) {
  final map = _object(raw, path, {'grid', 'amount'});
  return _construct(
    path,
    () => Swing(
      grid: _string(map['grid'], '$path.grid'),
      amount: _number(map['amount'], '$path.amount'),
    ),
  );
}

LayerMix _mix(Object? raw, String path) {
  final map = _object(raw, path, {'gain', 'pan', 'muted', 'solo'});
  return _construct(
    path,
    () => LayerMix(
      gain: _number(map['gain'], '$path.gain'),
      pan: _number(map['pan'], '$path.pan'),
      muted: _bool(map['muted'], '$path.muted'),
      solo: _bool(map['solo'], '$path.solo'),
    ),
  );
}

RhythmLayer _layer(Object? raw, String path) {
  final map = _object(raw, path, {
    'id',
    'sound',
    'pattern',
    'phaseSteps',
    'swing',
    'mix',
  });
  return _construct(
    path,
    () => RhythmLayer(
      id: _string(map['id'], '$path.id'),
      sound: _string(map['sound'], '$path.sound'),
      pattern: _pattern(map['pattern'], '$path.pattern'),
      phaseSteps: _int(map['phaseSteps'], '$path.phaseSteps'),
      swing: _swing(map['swing'], '$path.swing'),
      mix: _mix(map['mix'], '$path.mix'),
    ),
  );
}

Drone _drone(Object? raw, String path) {
  final map = _object(raw, path, {
    'enabled',
    'root',
    'octave',
    'mode',
    'chord',
    'gain',
    'filterHz',
    'spread',
  });
  return _construct(
    path,
    () => Drone(
      enabled: _bool(map['enabled'], '$path.enabled'),
      root: _int(map['root'], '$path.root'),
      octave: _int(map['octave'], '$path.octave'),
      mode: _string(map['mode'], '$path.mode'),
      chord: _string(map['chord'], '$path.chord'),
      gain: _number(map['gain'], '$path.gain'),
      filterHz: _number(map['filterHz'], '$path.filterHz'),
      spread: _number(map['spread'], '$path.spread'),
    ),
  );
}

Scene _scene(Object? raw, String path) {
  final map = _object(raw, path, {'id', 'layers', 'masterGain', 'drone'});
  final list = _list(map['layers'], '$path.layers');
  if (list.length < 2 || list.length > 4) {
    _fail('$path.layers', 'validation_error', 'Expected 2..4 layers');
  }
  return _construct(
    path,
    () => Scene(
      id: _string(map['id'], '$path.id'),
      layers: [
        for (var i = 0; i < list.length; i++)
          _layer(list[i], '$path.layers[$i]'),
      ],
      masterGain: _number(map['masterGain'], '$path.masterGain'),
      drone: _drone(map['drone'], '$path.drone'),
    ),
  );
}

SessionDocument _document(Object? raw, String path) {
  final map = _object(raw, path, {
    'format',
    'version',
    'revision',
    'title',
    'transport',
    'referenceClick',
    'randomSeed',
    'scenes',
    'defaultSceneId',
    'presentation',
  });
  if (map['format'] != 'polyrhythmer.session') {
    _fail('$path.format', 'validation_error', 'Unsupported format');
  }
  if (map['version'] != 2) {
    _fail(
      '$path.version',
      'unsupported_version',
      'Unsupported document version',
    );
  }
  if (map['revision'] != 0) {
    _fail(
      '$path.revision',
      'unsupported_version',
      'Unsupported document revision',
    );
  }
  final transport = _object(map['transport'], '$path.transport', {
    'beatUnit',
    'bpm',
    'practiceCycleBeats',
  });
  if (transport['beatUnit'] != 'quarter-note') {
    _fail(
      '$path.transport.beatUnit',
      'validation_error',
      'Expected quarter-note',
    );
  }
  final click = _object(map['referenceClick'], '$path.referenceClick', {
    'subdivision',
  });
  final presentation = _object(map['presentation'], '$path.presentation', {
    'visualMode',
  });
  final scenes = _list(map['scenes'], '$path.scenes');
  if (scenes.length != 2) {
    _fail('$path.scenes', 'validation_error', 'Expected exactly two scenes');
  }
  final title = _string(map['title'], '$path.title');
  if (title.runes.length > 80 ||
      title.runes.any((rune) => rune <= 0x1f || rune >= 0x7f && rune <= 0x9f)) {
    _fail(
      '$path.title',
      'validation_error',
      'Title exceeds 80 code points or contains controls',
    );
  }
  return _construct(
    path,
    () => SessionDocument(
      title: title,
      transport: SessionTransport(
        bpm: _number(transport['bpm'], '$path.transport.bpm'),
        practiceCycleBeats: _rational(
          transport['practiceCycleBeats'],
          '$path.transport.practiceCycleBeats',
        ),
      ),
      referenceClick: ReferenceClick(
        _int(click['subdivision'], '$path.referenceClick.subdivision'),
      ),
      randomSeed: _int(map['randomSeed'], '$path.randomSeed'),
      scenes: [
        for (var i = 0; i < scenes.length; i++)
          _scene(scenes[i], '$path.scenes[$i]'),
      ],
      defaultSceneId: _string(map['defaultSceneId'], '$path.defaultSceneId'),
      presentation: Presentation(
        _string(presentation['visualMode'], '$path.presentation.visualMode'),
      ),
    ),
  );
}

/// Checks size, nesting and numeric spelling before JSON decoding.
void _scan(String source) {
  if (utf8.encode(source).length > 128 * 1024) {
    _fail(r'$', 'validation_error', 'JSON exceeds 128 KiB');
  }
  var inString = false;
  var escaped = false;
  var depth = 0;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
      continue;
    }
    if (char == '{' || char == '[') {
      depth++;
      if (depth > 16) _fail(r'$', 'validation_error', 'JSON depth exceeds 16');
    } else if (char == '}' || char == ']') {
      depth--;
    }
    if (char == '-' && i + 1 < source.length && source[i + 1] == '0') {
      final match = RegExp(
        r'^-0(?:\.\d+)?(?:[eE][+-]?\d+)?',
      ).firstMatch(source.substring(i));
      if (match != null) {
        final number = match.group(0)!;
        if (num.tryParse(number) == 0) {
          _fail(r'$', 'validation_error', 'Negative zero is forbidden');
        }
      }
    }
  }
}

void _inspect(Object? value, String path, int depth) {
  if (value is Map) {
    if (depth > 16) _fail(path, 'validation_error', 'JSON depth exceeds 16');
    for (final entry in value.entries) {
      if (entry.key == '__proto__' ||
          entry.key == 'prototype' ||
          entry.key == 'constructor') {
        _fail('$path.${entry.key}', 'validation_error', 'Unsafe key');
      }
      _inspect(entry.value, '$path.${entry.key}', depth + 1);
    }
  } else if (value is List) {
    if (depth > 16) _fail(path, 'validation_error', 'JSON depth exceeds 16');
    for (var i = 0; i < value.length; i++) {
      _inspect(value[i], '$path[$i]', depth + 1);
    }
  }
}

ParseResult<T> _parse<T>(String source, T Function(Object?) read) {
  try {
    _scan(source);
    final value = jsonDecode(source);
    _inspect(value, r'$', 1);
    return ParseResult.success(read(value));
  } on _Invalid catch (error) {
    return ParseResult.failure([error.error]);
  } on FormatException catch (error) {
    return ParseResult.failure([
      ValidationError(r'$', 'malformed_json', error.message),
    ]);
  } on ArgumentError catch (error) {
    return ParseResult.failure([
      ValidationError(
        r'$',
        'validation_error',
        error.message?.toString() ?? 'Invalid value',
      ),
    ]);
  }
}

ParseResult<SessionDocument> parseSessionDocument(String source) =>
    _parse(source, (raw) => _document(raw, r'$'));

ParseResult<SessionExportEnvelope> parseSessionEnvelope(String source) =>
    _parse(source, (raw) {
      final map = _object(raw, r'$', {
        'format',
        'envelopeVersion',
        'exportedAt',
        'createdWith',
        'session',
      });
      if (map['format'] != 'polyrhythmer.session-export') {
        _fail(r'$.format', 'validation_error', 'Unsupported format');
      }
      if (map['envelopeVersion'] != 1) {
        _fail(
          r'$.envelopeVersion',
          'unsupported_version',
          'Unsupported envelope version',
        );
      }
      final created = _object(map['createdWith'], r'$.createdWith', {
        'app',
        'version',
      });
      if (created['app'] != 'Polyrhythmer') {
        _fail(r'$.createdWith.app', 'validation_error', 'Unsupported app');
      }
      return _construct(
        r'$',
        () => SessionExportEnvelope(
          exportedAt: _string(map['exportedAt'], r'$.exportedAt'),
          createdWithVersion: _string(
            created['version'],
            r'$.createdWith.version',
          ),
          session: _document(map['session'], r'$.session'),
        ),
      );
    });
