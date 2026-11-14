// The frontend coverage gate. Reads the lcov report that
// `flutter test --coverage` writes and exits 1 when line coverage of lib/ is
// below [minimumLineCoverage], or when a file in lib/ is missing from the
// report.
//
//   fvm flutter test --exclude-tags golden --coverage
//   fvm dart run tool/check_coverage.dart [path/to/lcov.info]
//
// Flutter only reports files a test loaded, so an untested new file is
// invisible to the total instead of counting as 0%. The missing-file check
// closes that gap. Files with no executable code (constants only) never appear
// in a report, so those are allowed.
//
// On GitHub Actions the summary is also written to the job page.
import 'dart:io';

/// Set a little under the measured total (98.62% without generated files,
/// 2026-11-03) so a stray line doesn't fail a PR, while an untested screen or
/// service does. Raise it as coverage rises.
const double minimumLineCoverage = 97.0;

/// Generated code, measured by its generator's tests rather than ours.
final List<RegExp> excluded = [
  RegExp(r'^lib/l10n/app_localizations(_\w+)?\.dart$'),
  RegExp(r'\.g\.dart$'),
  RegExp(r'\.freezed\.dart$'),
];

class FileCoverage {
  FileCoverage(this.path, this.found, this.hit);

  final String path;
  final int found;
  final int hit;

  double get percent => found == 0 ? 100 : 100 * hit / found;
}

/// Parses the `SF:`, `LF:` and `LH:` records of an lcov report. Absolute
/// paths are made relative to [root], the package directory.
List<FileCoverage> parseLcov(String lcov, {String root = ''}) {
  final files = <FileCoverage>[];
  String? path;
  var found = 0;
  var hit = 0;
  for (final line in lcov.split('\n')) {
    if (line.startsWith('SF:')) {
      path = line.substring(3).trim();
      if (root.isNotEmpty && path.startsWith(root)) {
        path = path.substring(root.length).replaceFirst(RegExp(r'^/'), '');
      }
      found = 0;
      hit = 0;
    } else if (line.startsWith('LF:')) {
      found = int.parse(line.substring(3).trim());
    } else if (line.startsWith('LH:')) {
      hit = int.parse(line.substring(3).trim());
    } else if (line.trim() == 'end_of_record' && path != null) {
      files.add(FileCoverage(path, found, hit));
      path = null;
    }
  }
  return files;
}

bool isExcluded(String path) => excluded.any((re) => re.hasMatch(path));

/// Whether [source] declares anything that runs: a function, method,
/// constructor or accessor body. Constants-only files have none, so the VM
/// reports no lines for them. A heuristic, erring towards "has code": a
/// false positive only asks for a test that wasn't strictly needed.
bool hasExecutableCode(String source) {
  final code = source
      .replaceAll(RegExp(r'//.*'), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return RegExp(
    r'(\)|\bget\s+\w+)\s*(async\*?|sync\*)?\s*(\{|=>)',
  ).hasMatch(code);
}

class Result {
  Result(this.files, this.missing);

  final List<FileCoverage> files;

  /// Files in lib/ with code that no test loaded.
  final List<String> missing;

  int get found => files.fold(0, (sum, f) => sum + f.found);
  int get hit => files.fold(0, (sum, f) => sum + f.hit);
  double get percent => found == 0 ? 100 : 100 * hit / found;
  bool get passes => percent >= minimumLineCoverage && missing.isEmpty;
}

Result evaluate(List<FileCoverage> reported, Map<String, String> libSources) {
  final files = reported
      .where((f) => f.path.startsWith('lib/') && !isExcluded(f.path))
      .toList();
  final reportedPaths = files.map((f) => f.path).toSet();
  final missing =
      libSources.entries
          .where(
            (e) =>
                !isExcluded(e.key) &&
                !reportedPaths.contains(e.key) &&
                hasExecutableCode(e.value),
          )
          .map((e) => e.key)
          .toList()
        ..sort();
  return Result(files, missing);
}

String summary(Result result, {int lowest = 10}) {
  final buffer = StringBuffer()
    ..writeln('### Frontend line coverage')
    ..writeln()
    ..writeln(
      '**${result.percent.toStringAsFixed(2)}%** of ${result.found} lines '
      'in ${result.files.length} files (gate: '
      '${minimumLineCoverage.toStringAsFixed(0)}%, generated files excluded).',
    );
  if (result.missing.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('No test loads these files, so their lines go uncounted:')
      ..writeln();
    for (final path in result.missing) {
      buffer.writeln('- `$path`');
    }
  }
  final under = result.files.where((f) => f.hit < f.found).toList()
    ..sort((a, b) => a.percent.compareTo(b.percent));
  if (under.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('| Least covered | Lines | Covered |')
      ..writeln('| --- | ---: | ---: |');
    for (final f in under.take(lowest)) {
      buffer.writeln(
        '| `${f.path}` | ${f.hit}/${f.found} | '
        '${f.percent.toStringAsFixed(1)}% |',
      );
    }
  }
  return buffer.toString();
}

void main(List<String> args) {
  final lcovFile = File(args.isEmpty ? 'coverage/lcov.info' : args.first);
  if (!lcovFile.existsSync()) {
    stderr.writeln(
      '${lcovFile.path} not found. '
      'Run `fvm flutter test --exclude-tags golden --coverage` first.',
    );
    exit(2);
  }
  final libSources = {
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        entity.path.replaceAll(r'\', '/'): entity.readAsStringSync(),
  };
  final result = evaluate(
    parseLcov(lcovFile.readAsStringSync(), root: Directory.current.path),
    libSources,
  );
  final report = summary(result);
  stdout.write(report);

  final stepSummary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (stepSummary != null && stepSummary.isNotEmpty) {
    File(stepSummary).writeAsStringSync(report, mode: FileMode.append);
  }

  if (!result.passes) {
    stderr.writeln();
    if (result.percent < minimumLineCoverage) {
      stderr.writeln(
        'Line coverage ${result.percent.toStringAsFixed(2)}% is below the '
        '${minimumLineCoverage.toStringAsFixed(0)}% gate.',
      );
    }
    if (result.missing.isNotEmpty) {
      stderr.writeln(
        '${result.missing.length} file(s) in lib/ have code no test loads. '
        'Add tests for them.',
      );
    }
    exit(1);
  }
}
