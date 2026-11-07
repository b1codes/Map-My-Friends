import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_web_size.dart';

void main() {
  late Directory build;

  setUp(() {
    build = Directory.systemTemp.createTempSync('web_size_test');
    addTearDown(() => build.deleteSync(recursive: true));
  });

  void write(String path, List<int> bytes) => (File(
    '${build.path}/$path',
  )..createSync(recursive: true)).writeAsBytesSync(bytes);

  /// Bytes gzip can't shrink, so the gzipped size is about [kib] KiB.
  List<int> incompressible(int kib) {
    var x = 0x2545F491;
    return [
      for (var i = 0; i < kib * 1024; i++)
        (x = (x * 1103515245 + 12345) & 0x7fffffff) >> 16 & 0xff,
    ];
  }

  test('passes a build within every budget', () {
    write('main.dart.js', incompressible(100));
    write('assets/assets/logo.png', incompressible(50));
    final report = measure(build);
    expect(report.problems, isEmpty);
    expect(report.assets.single.path, 'assets/assets/logo.png');
    expect(render(report), contains('Within budget.'));
  });

  test('fails an asset over its budget, and names it', () {
    write('main.dart.js', incompressible(100));
    write('assets/assets/huge.png', incompressible(maxAssetKiB + 20));
    final problems = measure(build).problems;
    expect(problems, hasLength(1));
    expect(problems.single, startsWith('assets/assets/huge.png is'));
  });

  test('fails the app and the total over theirs', () {
    write('main.dart.js', incompressible(maxTotalKiB + 10));
    final problems = measure(build).problems;
    expect(problems, hasLength(2));
    expect(problems.first, startsWith('main.dart.js is'));
    expect(problems.last, startsWith('the app and its assets are'));
  });

  test('leaves out files a visit only downloads on demand', () {
    write('main.dart.js', incompressible(10));
    write('assets/NOTICES', incompressible(maxAssetKiB + 20));
    expect(measure(build).assets, isEmpty);
  });

  test('asks for a build when there is none', () {
    expect(() => measure(build), throwsStateError);
  });
}
