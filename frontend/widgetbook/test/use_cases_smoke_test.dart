// Opens every catalog entry, through the real Widgetbook app and its addons,
// and fails on anything it throws, or if the route did not reach the entry.
//
// A catalog entry breaks silently: the app's own tests never build it, and a
// renamed parameter or a new bloc a screen reads only shows up when someone
// clicks the entry. This makes that a CI failure instead.
//
// Layout overflows are the one exception, and are reported rather than
// failed. flutter_test draws every glyph as a full-em square, far wider than
// the app's typefaces, so it reports overflows the app does not have (and
// the Google Fonts the screens request cannot load offline to correct it).
// The catalog's Accessibility addon checks overflow against real fonts.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:map_my_friends_widgetbook/main.dart';
import 'package:map_my_friends_widgetbook/main.directories.g.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:widgetbook/widgetbook.dart';

/// A node's place in the tree, as the path Widgetbook routes to.
String _route(String prefix, WidgetbookNode node) =>
    '$prefix${node.name}'.replaceAll(' ', '-').toLowerCase();

/// Every use case in the generated tree, as the path Widgetbook routes to.
List<String> _useCasePaths(List<WidgetbookNode> nodes, [String prefix = '']) {
  return [
    for (final node in nodes)
      if (node is WidgetbookUseCase)
        _route(prefix, node)
      else
        ..._useCasePaths(node.children ?? const [], '$prefix${node.name}/'),
  ];
}

/// A copy of [nodes] whose use cases wrap what they build in a [_Rendered]
/// naming their path.
///
/// A path that does not resolve throws nothing: Widgetbook shows its empty
/// pane and the entry is never built. Finding the marker is what proves the
/// route reached the builder.
List<WidgetbookNode> _tagged(List<WidgetbookNode> nodes, [String prefix = '']) {
  return [
    for (final node in nodes)
      if (node is WidgetbookUseCase)
        WidgetbookUseCase(
          name: node.name,
          designLink: node.designLink,
          builder: (context) =>
              _Rendered(_route(prefix, node), node.builder(context)),
        )
      else
        node.copyWith(
          children: _tagged(node.children ?? const [], '$prefix${node.name}/'),
        ),
  ];
}

class _Rendered extends StatelessWidget {
  const _Rendered(this.path, this.child);

  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

bool _isOverflow(FlutterErrorDetails details) =>
    details.exceptionAsString().contains('overflowed by');

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    // The real theme with a local typeface: GoogleFonts starts a network
    // fetch the moment a TextStyle is built, which fails offline. See
    // AppTheme.textThemeBuilder.
    AppTheme.textThemeBuilder = (color) => Typography.material2021().black
        .apply(bodyColor: color, displayColor: color);
    AppTheme.resetThemeCache();
  });

  tearDownAll(() {
    AppTheme.textThemeBuilder = AppTheme.buildBrandTextTheme;
    AppTheme.resetThemeCache();
  });

  final paths = _useCasePaths(directories);
  final tagged = _tagged(directories);

  test('the catalog is not empty', () {
    expect(paths, isNotEmpty);
  });

  for (final path in paths) {
    testWidgets('opens $path', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        await tester.pumpWidget(
          WidgetbookApp(initialRoute: '/?path=$path&preview', nodes: tagged),
        );
        // Not pumpAndSettle: the Ambient Field and the Chromatic Pulse
        // animate for as long as they are on screen, so nothing settles.
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      } finally {
        FlutterError.onError = previous;
      }

      final overflows = errors.where(_isOverflow).toList();
      if (overflows.isNotEmpty) {
        debugPrint(
          '$path: ${overflows.length} layout overflow(s) under the test font; '
          'check against real fonts in the catalog.',
        );
      }
      final failures = errors.where((d) => !_isOverflow(d)).toList();
      expect(
        failures.map((d) => d.exceptionAsString()).toList(),
        isEmpty,
        reason: '$path threw while building',
      );
      expect(
        find.byWidgetPredicate((w) => w is _Rendered && w.path == path),
        findsOneWidget,
        reason: '$path did not route to its use case',
      );

      // Tear the tree down inside the test, then run out any timers it left
      // (toasts, debounces), so they are not reported against the next one.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
