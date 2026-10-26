import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host side of `flutter drive`: relays the journeys' results and saves the
/// screenshot a failing journey takes (see `journey` in
/// integration_test/support/e2e.dart) to build/e2e/screenshots/.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/e2e/screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    stdout.writeln('Saved failure screenshot: ${file.path}');
    return true;
  },
);
