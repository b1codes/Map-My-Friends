import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_coverage.dart';

const _lcov = '''
SF:/repo/frontend/lib/a.dart
DA:1,1
LF:10
LH:9
end_of_record
SF:lib/l10n/app_localizations_en.dart
LF:17
LH:0
end_of_record
SF:lib/b.dart
LF:0
LH:0
end_of_record
''';

void main() {
  group('parseLcov', () {
    test('reads each record and makes absolute paths package-relative', () {
      final files = parseLcov(_lcov, root: '/repo/frontend');
      expect(files.map((f) => f.path), [
        'lib/a.dart',
        'lib/l10n/app_localizations_en.dart',
        'lib/b.dart',
      ]);
      expect(files.first.found, 10);
      expect(files.first.hit, 9);
      expect(files.first.percent, 90);
      expect(files.last.percent, 100, reason: 'no lines means nothing missed');
    });
  });

  group('isExcluded', () {
    test('skips generated code only', () {
      expect(isExcluded('lib/l10n/app_localizations.dart'), isTrue);
      expect(isExcluded('lib/l10n/app_localizations_es.dart'), isTrue);
      expect(isExcluded('lib/models/person.g.dart'), isTrue);
      expect(isExcluded('lib/models/person.freezed.dart'), isTrue);
      expect(isExcluded('lib/l10n/locale_picker.dart'), isFalse);
      expect(isExcluded('lib/models/person.dart'), isFalse);
    });
  });

  group('hasExecutableCode', () {
    test('is false for a constants-only file', () {
      expect(
        hasExecutableCode('''
import 'package:flutter/material.dart';

class Sizes {
  /// Minimum touch target (dp).
  static const double min = 48.0;
  static const Size minSize = Size(min, min);
}

enum Mode { light, dark }
typedef Callback = void Function(int value);
'''),
        isFalse,
      );
    });

    test('is true for functions, methods, constructors and getters', () {
      expect(hasExecutableCode('int twice(int x) => x * 2;'), isTrue);
      expect(hasExecutableCode('void main() {}'), isTrue);
      expect(hasExecutableCode('Future<void> load() async {}'), isTrue);
      expect(
        hasExecutableCode('class A { A(this.x) {} final int x; }'),
        isTrue,
      );
      expect(hasExecutableCode('class A { int get x => 1; }'), isTrue);
    });

    test('ignores code that only appears in comments', () {
      expect(
        hasExecutableCode('// call() => thing\n/* f() {} */\nconst a = 1;'),
        isFalse,
      );
    });
  });

  group('evaluate', () {
    final reported = [
      FileCoverage('lib/a.dart', 100, 98),
      FileCoverage('lib/l10n/app_localizations_en.dart', 50, 0),
      FileCoverage('test/helpers/fake.dart', 50, 0),
    ];

    test('totals lib/ without generated files or test helpers', () {
      final result = evaluate(reported, {'lib/a.dart': 'void a() {}'});
      expect(result.found, 100);
      expect(result.hit, 98);
      expect(result.missing, isEmpty);
      expect(result.passes, isTrue);
    });

    test('fails below the gate', () {
      final result = evaluate(
        [FileCoverage('lib/a.dart', 100, 50)],
        {'lib/a.dart': 'void a() {}'},
      );
      expect(result.percent, 50);
      expect(result.passes, isFalse);
    });

    test('fails on a file with code that no test loaded', () {
      final result = evaluate(reported, {
        'lib/a.dart': 'void a() {}',
        'lib/untested.dart': 'void untested() {}',
        'lib/constants.dart': 'const double size = 48.0;',
        'lib/l10n/app_localizations_es.dart': 'String hi() => "hola";',
      });
      expect(result.missing, ['lib/untested.dart']);
      expect(result.passes, isFalse);
      expect(summary(result), contains('`lib/untested.dart`'));
    });
  });

  group('summary', () {
    test('lists the least covered files, lowest first', () {
      final result = evaluate([
        FileCoverage('lib/full.dart', 10, 10),
        FileCoverage('lib/half.dart', 10, 5),
        FileCoverage('lib/most.dart', 10, 9),
      ], {});
      final text = summary(result);
      expect(text, contains('**80.00%** of 30 lines in 3 files'));
      expect(text, isNot(contains('lib/full.dart')));
      expect(
        text.indexOf('lib/half.dart'),
        lessThan(text.indexOf('lib/most.dart')),
      );
    });
  });
}
