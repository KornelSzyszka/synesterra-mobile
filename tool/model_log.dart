// Validates and summarizes the model outcome log in logs/outcomes/*.json
// (one file per task). Rules mirror docs/agents/model-routing.md.
//
//   dart run tool/model_log.dart check [dir]    validate (used in CI)
//   dart run tool/model_log.dart summary [dir]  success rate per class x size x risk
import 'dart:convert';
import 'dart:io';

const _defaultDir = 'logs/outcomes';
const _minSample = 5;

const _classRank = {'S': 1, 'M': 2, 'L': 3, 'X': 4};

const _modelClass = {
  'claude-haiku-4-5': 'S',
  'gpt-5.6-luna': 'S',
  'claude-sonnet-5-5': 'M',
  'gpt-5.6-terra': 'M',
  'claude-opus-5-5': 'L',
  'gpt-6-sol': 'L',
  'gpt-6.1-sol': 'L',
  'claude-fable-5-1': 'X',
  'gpt-6-astra': 'X',
};

// Minimum model class by failure cost (risk) and size; mirrors the hard-floor
// table in docs/agents/model-routing.md. Risks not listed use the low row.
const _floor = {
  'low': {'S': 'S', 'M': 'M', 'L': 'M'},
  'risk-platform': {'S': 'M', 'M': 'M', 'L': 'L'},
  'risk-audio': {'S': 'L', 'M': 'L', 'L': 'L'},
};

// Error types that count against the model's success rate.
const _modelFaults = {'misread-task', 'missing-context', 'model-limit'};

const _required = {
  'date',
  'task',
  'prefix',
  'size',
  'risk',
  'agent',
  'model',
  'success',
  'attempts',
  'evidence',
  'notes',
};

const _nullable = {
  'reasoning',
  'escalation',
  'error_type',
  'review',
  'ci',
  'failure_cost',
  'minutes',
  'tokens',
};

const _enums = {
  'prefix': {'AGT', 'DOM', 'AUD', 'UX', 'MOB', 'QA', 'REL'},
  'size': {'S', 'M', 'L'},
  'risk': {'none', 'risk-ux', 'risk-scope', 'risk-platform', 'risk-audio'},
  'agent': {'claude', 'codex'},
  'reasoning': {'low', 'medium', 'high'},
  'error_type': {
    'random',
    'misread-task',
    'missing-context',
    'model-limit',
    'environment',
  },
  'review': {'ok', 'changes', 'blocked'},
  'ci': {'green', 'red-green', 'red'},
  'evidence': {'static', 'unit', 'widget', 'emulator', 'device'},
  'failure_cost': {'L', 'M', 'H'},
};

void main(List<String> args) {
  final command = args.isEmpty ? 'check' : args.first;
  final dir = args.length > 1 ? args[1] : _defaultDir;
  final errors = <String>[];
  final rows = _load(dir, errors);

  if (command == 'check') {
    if (errors.isNotEmpty) _fail(errors);
    stdout.writeln('OK: ${rows.length} outcome files in $dir');
  } else if (command == 'summary') {
    if (errors.isNotEmpty) _fail(errors);
    _summary(rows);
  } else {
    _fail(['unknown command "$command"; use check or summary']);
  }
}

List<Map<String, Object?>> _load(String dir, List<String> errors) {
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    errors.add('$dir: directory not found');
    return [];
  }
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final rows = <Map<String, Object?>>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      errors.add('$name: invalid JSON (${e.message})');
      continue;
    }
    if (decoded is! Map<String, Object?>) {
      errors.add('$name: top level must be an object');
      continue;
    }
    final before = errors.length;
    _validate(name, decoded, errors);
    if (errors.length == before) rows.add(decoded);
  }
  return rows;
}

void _validate(String name, Map<String, Object?> v, List<String> errors) {
  void err(String message) => errors.add('$name: $message');

  final unknown = v.keys.toSet().difference({..._required, ..._nullable});
  if (unknown.isNotEmpty) err('unknown fields: ${unknown.join(', ')}');
  for (final key in _required) {
    if (v[key] == null) err('missing required field "$key"');
  }

  final task = v['task'];
  if (task is! String || !RegExp(r'^[A-Z]+-\d{3}$').hasMatch(task)) {
    err('task must look like PREFIX-###');
  } else {
    if (name != '$task.json') err('file name must be $task.json');
    if (task.split('-').first != v['prefix']) err('prefix does not match task');
  }
  final date = v['date'];
  if (date is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
    err('date must be YYYY-MM-DD');
  }

  for (final entry in _enums.entries) {
    final value = v[entry.key];
    if (value == null) continue; // presence handled above
    if (!entry.value.contains(value)) {
      err('${entry.key} "$value" not in ${entry.value.join(', ')}');
    }
  }

  final success = v['success'];
  if (success is! bool) err('success must be true or false');
  final attempts = v['attempts'];
  if (attempts is! int || attempts < 1) err('attempts must be an integer >= 1');
  for (final key in ['minutes', 'tokens']) {
    final value = v[key];
    if (value != null && (value is! int || value < 0)) {
      err('$key must be null or a non-negative integer');
    }
  }
  for (final key in ['escalation', 'notes']) {
    final value = v[key];
    if (value != null && value is! String) err('$key must be a string');
  }

  final failed = success == false;
  final needsErrorType = failed || (attempts is int && attempts > 1);
  if (needsErrorType && v['error_type'] == null) {
    err('error_type required when success is false or attempts > 1');
  }
  if (!needsErrorType && v['error_type'] != null) {
    err('error_type must be null for a clean success');
  }
  if (failed && v['failure_cost'] == null) {
    err('failure_cost required when success is false');
  }
  if (success == true && v['failure_cost'] != null) {
    err('failure_cost must be null when success is true');
  }

  final model = v['model'];
  final cls = _modelClass[model];
  if (model != null && cls == null) {
    err('unknown model "$model"; add it to _modelClass');
  } else if (cls != null) {
    final row = _floor[v['risk']] ?? _floor['low']!;
    final floor = row[v['size']];
    if (floor != null && _classRank[cls]! < _classRank[floor]!) {
      err(
        '$model is class $cls, below floor $floor for '
        '${v['risk']} x size ${v['size']}',
      );
    }
  }
}

void _summary(List<Map<String, Object?>> rows) {
  final cells = <String, List<Map<String, Object?>>>{};
  var excluded = 0;
  for (final row in rows) {
    final attributable =
        row['success'] == true || _modelFaults.contains(row['error_type']);
    if (!attributable) {
      excluded++;
      continue;
    }
    final key =
        '${_modelClass[row['model']]} x ${row['size']} x ${row['risk']}';
    cells.putIfAbsent(key, () => []).add(row);
  }
  stdout.writeln('class x size x risk | n | successes | success rate');
  for (final key in cells.keys.toList()..sort()) {
    final group = cells[key]!;
    final wins = group.where((r) => r['success'] == true).length;
    final rate = group.length >= _minSample
        ? '${(100 * wins / group.length).toStringAsFixed(0)}%'
        : 'n<$_minSample, no estimate';
    stdout.writeln('$key | ${group.length} | $wins | $rate');
  }
  stdout.writeln(
    '${rows.length} outcomes, $excluded excluded '
    '(failures not attributable to the model).',
  );
}

Never _fail(List<String> errors) {
  for (final e in errors) {
    stderr.writeln('model log: $e');
  }
  exit(1);
}
