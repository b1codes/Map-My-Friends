// The web download budget. Reads a release web build and exits 1 when what
// a visitor downloads has grown past its budget:
//
//   fvm flutter build web --release
//   fvm dart run tool/check_web_size.dart [build/web]
//
// Sizes are gzipped, as the browser fetches them. Checked:
//   - main.dart.js, the compiled app, against [maxAppKiB];
//   - every bundled asset against [maxAssetKiB], so a new image or data file
//     that every visitor would download can't slip in unnoticed (the logo
//     used to be a 2.5 MB, 1024 px PNG drawn at 80 px);
//   - the total of both against [maxTotalKiB], the most a visit downloads
//     (assets load when first used).
// CanvasKit isn't counted: Flutter loads it from Google's CDN, the same
// files for every Flutter app, and the browser caches them across sites.
//
// On GitHub Actions the summary is also written to the job page.
import 'dart:io';

/// Budgets in KiB, gzipped. Measured on 2026-11-07: main.dart.js 1,745 KiB,
/// the largest asset 149 KiB (airports.json), 2,351 KiB in all. Assets load
/// when first used, so the total is the most a visit downloads; most
/// download less (the 260 phone-number flags only with the country picker).
/// A little over the measured size, so a small feature passes and a large
/// dependency or asset fails and gets a look.
const int maxAppKiB = 1900;
const int maxAssetKiB = 200;
const int maxTotalKiB = 2600;

/// Bundled files a visit doesn't download up front, so they aren't
/// budgeted, with why.
const Map<String, String> notDownloadedUpFront = {
  'assets/NOTICES': 'the licences, read only on the About page',
};

class SizedFile {
  SizedFile(this.path, this.gzippedBytes);

  final String path;
  final int gzippedBytes;

  double get kib => gzippedBytes / 1024;
}

class SizeReport {
  SizeReport(this.app, this.assets);

  final SizedFile app;
  final List<SizedFile> assets;

  int get totalBytes =>
      app.gzippedBytes + assets.fold(0, (sum, f) => sum + f.gzippedBytes);

  List<String> get problems {
    String over(SizedFile f, int budget) =>
        '${f.path} is ${f.kib.round()} KiB gzipped, over $budget KiB';
    final total = (totalBytes / 1024).round();
    return [
      if (app.kib > maxAppKiB) over(app, maxAppKiB),
      for (final asset in assets)
        if (asset.kib > maxAssetKiB) over(asset, maxAssetKiB),
      if (totalBytes / 1024 > maxTotalKiB)
        'the app and its assets are $total KiB gzipped, over $maxTotalKiB KiB',
    ];
  }
}

int gzippedSize(File file) => gzip.encode(file.readAsBytesSync()).length;

/// Measures the build in [buildDir]. Paths in the report are relative to it.
SizeReport measure(Directory buildDir) {
  String relative(File f) =>
      f.path.substring(buildDir.path.length).replaceFirst(RegExp(r'^/'), '');

  final main = File('${buildDir.path}/main.dart.js');
  if (!main.existsSync()) {
    throw StateError(
      'No main.dart.js in ${buildDir.path}. Run `flutter build web --release` '
      'first.',
    );
  }
  final assetsDir = Directory('${buildDir.path}/assets');
  final assets = assetsDir.existsSync()
      ? [
          for (final entity in assetsDir.listSync(recursive: true))
            if (entity is File &&
                !notDownloadedUpFront.containsKey(relative(entity)))
              SizedFile(relative(entity), gzippedSize(entity)),
        ]
      : <SizedFile>[];
  assets.sort((a, b) => b.gzippedBytes.compareTo(a.gzippedBytes));
  return SizeReport(SizedFile(relative(main), gzippedSize(main)), assets);
}

String render(SizeReport report) {
  final buffer = StringBuffer()
    ..writeln('## Web download size')
    ..writeln()
    ..writeln(
      'Gzipped. ${report.problems.isEmpty ? 'Within budget.' : 'Over budget.'}',
    )
    ..writeln()
    ..writeln('| File | KiB | Budget |')
    ..writeln('|---|---|---|')
    ..writeln(
      '| ${report.app.path} | ${report.app.kib.round()} | $maxAppKiB |',
    );
  for (final asset in report.assets.take(8)) {
    buffer.writeln('| ${asset.path} | ${asset.kib.round()} | $maxAssetKiB |');
  }
  if (report.assets.length > 8) {
    buffer.writeln('| ${report.assets.length - 8} smaller assets | | |');
  }
  buffer
    ..writeln(
      '| **Total** | **${(report.totalBytes / 1024).round()}** | '
      '$maxTotalKiB |',
    )
    ..writeln();
  for (final problem in report.problems) {
    buffer.writeln('- ❌ $problem');
  }
  return buffer.toString();
}

void main(List<String> args) {
  final report = measure(Directory(args.isEmpty ? 'build/web' : args.first));
  final text = render(report);
  stdout.write(text);

  final stepSummary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (stepSummary != null && stepSummary.isNotEmpty) {
    File(stepSummary).writeAsStringSync(text, mode: FileMode.append);
  }
  if (report.problems.isNotEmpty) exitCode = 1;
}
