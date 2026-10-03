import 'dart:io';

/// A dependency-rule failure with its source file and directive.
class ArchitectureViolation {
  const ArchitectureViolation(this.rule, this.file, this.detail);

  final String rule;
  final String file;
  final String detail;

  @override
  String toString() => '$rule $file: $detail';
}

class _Dependency {
  const _Dependency(this.source, this.directive, this.uri, this.target);

  final String source;
  final String directive;
  final String uri;
  final String? target;
}

/// Scans Dart directives against the dependency boundaries in ADR 0001.
List<ArchitectureViolation> scanArchitecture(Directory root) {
  final rootPath = _slash(root.absolute.path);
  final dependencies = <_Dependency>[];
  final violations = <ArchitectureViolation>[];
  for (final directory in ['lib', 'packages/synesterra_core/lib']) {
    final base = Directory('${root.path}/$directory');
    if (!base.existsSync()) continue;
    for (final entity in base.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = _relative(rootPath, entity.absolute.path);
      final content = _withoutComments(entity.readAsStringSync());
      final directives = RegExp(
        r'''^\s*(import|export|part)\s+['"][^'"]+['"][^;]*;''',
        multiLine: true,
      );
      for (final match in directives.allMatches(content)) {
        final directive = match.group(1)!;
        if (directive.startsWith('part')) {
          violations.add(ArchitectureViolation('R9', source, directive));
        }
        final uris = RegExp(r'''['"]([^'"]+)['"]''');
        for (final uriMatch in uris.allMatches(match.group(0)!)) {
          final uri = uriMatch.group(1)!;
          dependencies.add(
            _Dependency(
              source,
              directive,
              uri,
              _resolve(rootPath, entity, uri),
            ),
          );
        }
      }
      final partOf = RegExp(
        r'''^\s*part\s+of\s+(?:['"][^'"]+['"]|[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*;''',
        multiLine: true,
      );
      for (final match in partOf.allMatches(content)) {
        violations.add(
          ArchitectureViolation('R9', source, match.group(0)!.trim()),
        );
      }
    }
  }

  void fail(String rule, _Dependency dependency) => violations.add(
    ArchitectureViolation(
      rule,
      dependency.source,
      '${dependency.directive} ${dependency.uri}',
    ),
  );

  final graph = <String, Set<String>>{};
  final edges = <String, _Dependency>{};
  for (final dependency in dependencies) {
    final source = dependency.source;
    final target = dependency.target;
    final inCore = source.startsWith('packages/synesterra_core/lib/');
    final coreTarget =
        target?.startsWith('packages/synesterra_core/lib/') ?? false;

    if (inCore &&
        !(dependency.uri.startsWith('dart:') &&
            const {
              'dart:core',
              'dart:async',
              'dart:math',
              'dart:collection',
              'dart:convert',
              'dart:typed_data',
            }.contains(dependency.uri)) &&
        !coreTarget) {
      fail('R1', dependency);
    }

    if (inCore && coreTarget) {
      final from = _coreContext(source);
      final to = _coreContext(target!);
      const allowed = {
        'rhythm': <String>{},
        'sound': <String>{},
        'harmony': {'rhythm'},
        'session': {'rhythm', 'harmony', 'sound'},
        'playback': {'rhythm', 'harmony', 'sound', 'session'},
        'ports': {'rhythm', 'harmony', 'sound', 'session', 'playback'},
      };
      if (from != null &&
          to != null &&
          from != to &&
          !(allowed[from]?.contains(to) ?? false)) {
        fail('R2', dependency);
      }
    }

    if (!inCore &&
        coreTarget &&
        (target != 'packages/synesterra_core/lib/synesterra_core.dart' ||
            dependency.uri != 'package:synesterra_core/synesterra_core.dart')) {
      fail('R3', dependency);
    }

    final fromFeature = _feature(source);
    final toFeature = target == null ? null : _feature(target);
    if (fromFeature != null && toFeature != null && fromFeature != toFeature) {
      fail('R4', dependency);
    }

    final fromUi = fromFeature != null || source.startsWith('lib/shared/');
    if (fromUi &&
        ((target != null &&
                (target.startsWith('lib/data/services/') ||
                    target.startsWith('lib/data/audio/') ||
                    target.startsWith('lib/data/repositories/impl/'))) ||
            dependency.uri == 'package:flutter/services.dart' ||
            _pluginPackages.any(
              (name) => dependency.uri.startsWith('package:$name/'),
            ))) {
      fail('R5', dependency);
    }

    if (source.startsWith('lib/data/') &&
        target != null &&
        (target.startsWith('lib/features/') ||
            target.startsWith('lib/shared/') ||
            target.startsWith('lib/app/'))) {
      fail('R6', dependency);
    }

    if (source == 'lib/main.dart') {
      if ((target != null && !target.startsWith('lib/app/')) ||
          (target == null &&
              !dependency.uri.startsWith('package:flutter/') &&
              !dependency.uri.startsWith('dart:'))) {
        fail('R7', dependency);
      }
    } else if (target != null) {
      if (target.startsWith('lib/data/repositories/impl/') &&
          !source.startsWith('lib/app/') &&
          !source.startsWith('lib/data/repositories/impl/')) {
        fail('R7', dependency);
      }
      if ((target.startsWith('lib/data/services/') ||
              target.startsWith('lib/data/audio/')) &&
          !source.startsWith('lib/app/') &&
          !source.startsWith('lib/data/repositories/impl/') &&
          !_sameRestrictedArea(source, target)) {
        fail('R7', dependency);
      }
    }

    final fromModule = _module(source);
    final toModule = target == null ? null : _module(target);
    if (fromModule != null && toModule != null && fromModule != toModule) {
      graph.putIfAbsent(fromModule, () => {}).add(toModule);
      edges['$fromModule->$toModule'] = dependency;
    }
  }

  final stack = <String>[];
  final activeIndex = <String, int>{};
  final visited = <String>{};
  void visit(String node) {
    visited.add(node);
    activeIndex[node] = stack.length;
    stack.add(node);
    for (final next in graph[node] ?? const <String>{}) {
      final cycleStart = activeIndex[next];
      if (cycleStart != null) {
        final cycle = [...stack.skip(cycleStart), next];
        for (var i = 0; i < cycle.length - 1; i++) {
          final edge = edges['${cycle[i]}->${cycle[i + 1]}'];
          if (edge != null) fail('R8', edge);
        }
      } else if (!visited.contains(next)) {
        visit(next);
      }
    }
    stack.removeLast();
    activeIndex.remove(node);
  }

  for (final node in graph.keys) {
    if (!visited.contains(node)) visit(node);
  }
  return violations;
}

String _slash(String path) => path.replaceAll('\\', '/');

// Keep this list in sync with platform packages adopted by the app.
const _pluginPackages = {
  'audio_session',
  'device_info_plus',
  'file_picker',
  'flutter_soloud',
  'just_audio',
  'package_info_plus',
  'path_provider',
  'permission_handler',
  'share_plus',
  'shared_preferences',
  'url_launcher',
};

bool _sameRestrictedArea(String source, String target) => const [
  'lib/data/audio/',
  'lib/data/services/',
  'lib/data/repositories/impl/',
].any((area) => source.startsWith(area) && target.startsWith(area));

String _withoutComments(String source) {
  final output = StringBuffer();
  var index = 0;
  var blockDepth = 0;
  var lineComment = false;
  String? quote;
  while (index < source.length) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';
    if (lineComment) {
      if (char == '\n') lineComment = false;
      output.write(char == '\n' ? '\n' : ' ');
    } else if (blockDepth > 0) {
      if (char == '/' && next == '*') {
        blockDepth++;
        output.write('  ');
        index++;
      } else if (char == '*' && next == '/') {
        blockDepth--;
        output.write('  ');
        index++;
      } else {
        output.write(char == '\n' ? '\n' : ' ');
      }
    } else if (quote != null) {
      output.write(char);
      if (char == '\\' && next.isNotEmpty) {
        output.write(next);
        index++;
      } else if (char == quote) {
        quote = null;
      }
    } else if (char == '/' && next == '/') {
      lineComment = true;
      output.write('  ');
      index++;
    } else if (char == '/' && next == '*') {
      blockDepth = 1;
      output.write('  ');
      index++;
    } else {
      if (char == "'" || char == '"') quote = char;
      output.write(char);
    }
    index++;
  }
  return output.toString();
}

String _relative(String root, String path) =>
    _slash(path).substring(root.length + 1);

String? _resolve(String root, File source, String uri) {
  Uri? resolved;
  if (uri.startsWith('package:synesterra_core/')) {
    resolved = Uri.file('$root/packages/synesterra_core/lib/')
        .resolve(uri.substring('package:synesterra_core/'.length));
  } else if (uri.startsWith('package:synesterra/')) {
    resolved = Uri.file('$root/lib/')
        .resolve(uri.substring('package:synesterra/'.length));
  } else if (!uri.contains(':')) {
    resolved = source.absolute.uri.resolve(uri);
  }
  if (resolved == null) return null;
  final path = _slash(File.fromUri(resolved).absolute.path);
  return path.startsWith('$root/') ? path.substring(root.length + 1) : null;
}

String? _coreContext(String path) {
  final match = RegExp(r'^packages/synesterra_core/lib/src/([^/]+)/')
      .firstMatch(path);
  return match?.group(1);
}

String? _feature(String path) =>
    RegExp(r'^lib/features/([^/]+)/').firstMatch(path)?.group(1);

String? _module(String path) {
  final context = _coreContext(path);
  if (context != null) return 'core/$context';
  if (path.startsWith('packages/synesterra_core/lib/')) return 'core/public';
  final feature = _feature(path);
  if (feature != null) return 'features/$feature';
  if (path.startsWith('lib/data/repositories/impl/')) {
    return 'repositories/impl';
  }
  if (path.startsWith('lib/data/repositories/')) return 'repositories';
  for (final module in ['app', 'shared', 'data/services', 'data/audio']) {
    if (path.startsWith('lib/$module/')) return module;
  }
  return null;
}
