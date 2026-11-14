// lib/ reads the current time only through package:clock.
//
// clock.now() is DateTime.now() until a test pins it with withClock. The
// goldens pin it to the catalog's fixed date, so the Pulse calendar, the
// "today" in the contact sheet and every recency colour render the same on
// any day. One DateTime.now() on a render path would make those images
// change overnight, with no code change to explain it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DateTime.now(), and TZDateTime.now(location), which is built on it.
final _now = RegExp(r'DateTime\.now\(');

void main() {
  test('nothing in lib/ calls DateTime.now() or TZDateTime.now()', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains(_now)) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'use clock.now() from package:clock instead, and '
          'TZDateTime.from(clock.now(), location) for a zone',
    );
  });
}
