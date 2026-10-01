// Validates logs/model-outcomes.md: schema, enumerations and the model class
// floor from docs/agents/model-routing.md.
// Run: dart run tool/check_model_log.dart [path]
import 'dart:convert';
import 'dart:io';

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

// Minimum class by risk tag.
const _riskFloor = {'risk-platform': 'M', 'risk-audio': 'L'};

const _columns = [
  'date',
  'task',
  'prefix',
  'size',
  'risk',
  'agent',
  'model',
  'reasoning',
  'success',
  'attempts',
  'escalation',
  'error type',
  'review',
  'ci',
  'evidence',
  'failure cost',
  'minutes',
  'tokens',
  'notes',
];

const _allowed = {
  'prefix': {'AGT', 'DOM', 'AUD', 'UX', 'MOB', 'QA', 'REL'},
  'size': {'S', 'M', 'L'},
  'risk': {'-', 'risk-ux', 'risk-scope', 'risk-platform', 'risk-audio'},
  'agent': {'claude', 'codex'},
  'reasoning': {'low', 'medium', 'high', '-'},
  'success': {'yes', 'no'},
  'error type': {
    '-',
    'random',
    'misread-task',
    'missing-context',
    'model-limit',
    'environment',
  },
  'review': {'ok', 'changes', 'blocked', '-'},
  'ci': {'green', 'red-green', 'red', '-'},
  'evidence': {'static', 'unit', 'widget', 'emulator', 'device'},
  'failure cost': {'-', 'L', 'M', 'H'},
};

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'logs/model-outcomes.md';
  final lines = const LineSplitter().convert(File(path).readAsStringSync());
  final errors = <String>[];

  final start = lines.indexWhere((l) => l.trim() == '## Entries');
  if (start < 0) {
    _fail(['$path: missing "## Entries" section']);
  }

  final table = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('## ')) break;
    if (line.trimLeft().startsWith('|')) table.add(line.trim());
  }
  if (table.length < 2 || _cells(table[0]).join('|') != _columns.join('|')) {
    _fail(['$path: header must be exactly: ${_columns.join(' | ')}']);
  }

  final seen = <String>{};
  for (final row in table.skip(2)) {
    final cells = _cells(row);
    final label = cells.length > 1 ? cells[1] : row;
    if (cells.length != _columns.length) {
      errors.add(
        '$label: expected ${_columns.length} columns, found ${cells.length}',
      );
      continue;
    }
    final v = Map.fromIterables(_columns, cells);

    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v['date']!)) {
      errors.add('$label: date must be YYYY-MM-DD');
    }
    if (!RegExp(r'^[A-Z]+-\d{3}$').hasMatch(v['task']!)) {
      errors.add('$label: task must look like PREFIX-###');
    } else if (!seen.add(v['task']!)) {
      errors.add('$label: duplicate task row');
    } else if (v['task']!.split('-').first != v['prefix']) {
      errors.add('$label: prefix does not match task ID');
    }
    for (final entry in _allowed.entries) {
      if (!entry.value.contains(v[entry.key])) {
        errors.add(
          '$label: ${entry.key} "${v[entry.key]}" not in ${entry.value.join(', ')}',
        );
      }
    }
    final attempts = int.tryParse(v['attempts']!);
    if (attempts == null || attempts < 1) {
      errors.add('$label: attempts must be an integer >= 1');
    }
    for (final f in ['minutes', 'tokens']) {
      if (v[f]!.isNotEmpty && int.tryParse(v[f]!) == null) {
        errors.add('$label: $f must be empty or an integer');
      }
    }

    final failed = v['success'] == 'no';
    final needsErrorType = failed || (attempts ?? 1) > 1;
    if (needsErrorType && v['error type'] == '-') {
      errors.add(
        '$label: error type required when success is no or attempts > 1',
      );
    }
    if (!needsErrorType && v['error type'] != '-') {
      errors.add('$label: error type must be "-" for a clean success');
    }
    if (failed && v['failure cost'] == '-') {
      errors.add('$label: failure cost required when success is no');
    }
    if (!failed && v['failure cost'] != '-') {
      errors.add('$label: failure cost must be "-" when success is yes');
    }

    final cls = _modelClass[v['model']];
    if (cls == null) {
      errors.add(
        '$label: unknown model "${v['model']}"; add it to _modelClass',
      );
    } else {
      final floor = _riskFloor[v['risk']];
      if (floor != null && _classRank[cls]! < _classRank[floor]!) {
        errors.add(
          '$label: ${v['model']} is class $cls, below floor $floor for ${v['risk']}',
        );
      }
      if (v['size'] == 'L' && _classRank[cls]! < _classRank['M']!) {
        errors.add('$label: size L requires class M or higher');
      }
    }
  }

  if (errors.isNotEmpty) _fail(errors);
  stdout.writeln('OK: ${seen.length} rows in $path');
}

List<String> _cells(String row) {
  final parts = row.split('|').map((c) => c.trim()).toList();
  return parts.sublist(1, parts.length - 1);
}

Never _fail(List<String> errors) {
  for (final e in errors) {
    stderr.writeln('model log: $e');
  }
  exit(1);
}
