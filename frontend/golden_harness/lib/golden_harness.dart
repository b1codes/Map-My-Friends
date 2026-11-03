/// What every golden test in the app and the Widgetbook catalog shares.
///
/// A golden is only worth keeping if it changes when the UI does and stays
/// the same when it doesn't. Out of the box, flutter_test gets both wrong:
///
/// * It draws every glyph and icon as a box in the Ahem test font, so a
///   golden can't see a typeface, weight or icon change. [setUpGoldens]
///   loads the real ones: Montserrat and Open Sans from `fonts/` (the files
///   google_fonts would otherwise download), Roboto from the Flutter SDK, and
///   the icon fonts the app bundles. Nothing is fetched over the network.
/// * The same widget renders a little differently on each OS and CPU: text
///   antialiasing and blur differ between macOS and Linux, and slightly even
///   between arm64 and x64 Linux. Goldens are recorded and compared on
///   Linux x64 only, which is what CI runs. [goldenTest] skips everywhere
///   else; `make goldens` runs them on a Mac through Docker.
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/testing.dart';
import 'package:meta/meta.dart';

/// Whether this machine renders goldens the way they were recorded.
bool get isReferencePlatform => Abi.current() == Abi.linuxX64;

/// Why a golden test was skipped here.
const String referencePlatformSkipReason =
    'Goldens are recorded on Linux x64, the platform CI runs, and other '
    'platforms render text and blur slightly differently. Skipped here; run '
    '`make goldens` from the repo root to check them in Docker.';

/// What to do when a golden no longer matches.
const String _updateHint =
    'If the change is intended, run `make update-goldens` from the repo root '
    'and commit the new images. On CI, the expected, actual and diff images '
    'are in the run\'s golden-failures artifacts.';

/// Loads the real fonts and installs the comparator. Call it first in the
/// `main()` of every file with golden tests.
void setUpGoldens() {
  setUpAll(() async {
    if (!isReferencePlatform) {
      debugPrint(referencePlatformSkipReason);
      return;
    }
    // A pinned clock is a fixed local time, and what a screen shows for it
    // (each friend's local time, which day is "today") depends on the
    // machine's time zone. CI and the Docker image both run in UTC.
    if (DateTime.now().timeZoneOffset != Duration.zero) {
      throw StateError(
        'Goldens are recorded in UTC, and this machine is not. Run them with '
        'TZ=UTC, as `make goldens` does.',
      );
    }
    await _loadFonts();
    final base = goldenFileComparator;
    if (base is LocalFileComparator) {
      goldenFileComparator = _HintingComparator(base.basedir);
    }
  });
}

/// A golden test: tagged `golden`, skipped off the reference platform, and,
/// given [now], run with `clock.now()` pinned to it.
@isTest
void goldenTest(
  String description,
  WidgetTesterCallback body, {
  DateTime? now,
}) {
  testWidgets(
    description,
    (tester) async {
      if (now == null) return body(tester);
      return withClock(Clock.fixed(now), () => body(tester));
    },
    skip: !isReferencePlatform,
    tags: const ['golden'],
  );
}

/// Compares [finder] with the golden at [key].
Future<void> expectGolden(
  WidgetTester tester,
  Finder finder,
  String key,
) async {
  await expectLater(finder, matchesGoldenFile(key));
}

/// The weight each google_fonts file name stands for.
const _weights = {
  'Thin': FontWeight.w100,
  'ExtraLight': FontWeight.w200,
  'Light': FontWeight.w300,
  'Regular': FontWeight.w400,
  'Medium': FontWeight.w500,
  'SemiBold': FontWeight.w600,
  'Bold': FontWeight.w700,
  'ExtraBold': FontWeight.w800,
  'Black': FontWeight.w900,
};

/// Loads every face in `fonts/` through google_fonts, so a test never has
/// to.
///
/// google_fonts loads a face the first time a style asks for it. Asked from
/// inside a widget test, that load runs on the test's fake clock and never
/// finishes, and the frame renders in a fallback face. Loaded here, on the
/// real event loop, every face is ready before the first test builds.
Future<void> _preloadGoogleFonts() async {
  final assets = (await AssetManifest.loadFromAssetBundle(rootBundle))
      .listAssets()
      .where((a) => a.startsWith('packages/golden_harness/fonts/'))
      .where((a) => a.endsWith('.ttf'));
  for (final asset in assets) {
    // e.g. OpenSans-SemiBoldItalic: the family as google_fonts names its
    // files, then the weight, then Italic if it is.
    final name = asset.split('/').last.replaceAll('.ttf', '');
    final [family, variant] = name.split('-');
    final italic = variant.endsWith('Italic');
    final weightName = variant.replaceAll('Italic', '');
    final weight = _weights[weightName.isEmpty ? 'Regular' : weightName];
    if (weight == null) {
      throw StateError('$asset: no weight called "$weightName"');
    }
    GoogleFonts.getFont(
      // OpenSans → Open Sans, the family name google_fonts takes.
      family.replaceAllMapped(RegExp('(?<=[a-z])(?=[A-Z])'), (_) => ' '),
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );
  }
  await GoogleFonts.pendingFonts();
}

Future<void> _loadFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // google_fonts looks in the asset bundle first, and finds `fonts/` there:
  // this package's assets are bundled into the tests of every package that
  // depends on it, but not into a release build. A face that isn't there
  // would otherwise be downloaded; fail and name it instead.
  GoogleFonts.config.httpClient = MockClient(
    (request) async => throw StateError(
      'A golden asked for a font that golden_harness/fonts/ does not have. '
      'Save ${request.url} there, named as the error above says '
      '(e.g. Montserrat-Bold.ttf).',
    ),
  );
  await _preloadGoogleFonts();

  // The icon fonts the app bundles (MaterialIcons, CupertinoIcons), listed
  // in the test bundle's font manifest.
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json'))
          as List<Object?>;
  for (final entry in manifest.cast<Map<String, Object?>>()) {
    final loader = FontLoader(entry['family']! as String);
    for (final font
        in (entry['fonts']! as List<Object?>).cast<Map<String, Object?>>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    await loader.load();
  }

  // Roboto, Material's default face, for any text the brand theme doesn't
  // style. The SDK ships it with the Material icons.
  final roboto = FontLoader('Roboto');
  final sdkFonts = Directory(
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts',
  );
  for (final file in sdkFonts.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.startsWith('Roboto-') && name.endsWith('.ttf')) {
      roboto.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
  }
  await roboto.load();
}

/// The default comparator, with what to do next added to its failure.
class _HintingComparator extends LocalFileComparator {
  // LocalFileComparator takes the test file and keeps its directory.
  _HintingComparator(Uri basedir) : super(basedir.resolve('golden_test.dart'));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    try {
      return await super.compare(imageBytes, golden);
    } on FlutterError catch (error) {
      throw FlutterError('${error.message}\n$_updateHint');
    }
  }
}
