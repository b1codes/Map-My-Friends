import 'package:flutter/foundation.dart';
import 'package:accessibility_tools/accessibility_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:map_my_friends/l10n/app_localizations.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import 'main.directories.g.dart';
import 'support/app_asset_bundle.dart';
import 'support/media_addon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The same start-up the app does, for the same reasons: the Map screen's
  // tile cache needs its backend on native platforms, and People and Pulse
  // render each friend's local time.
  if (!kIsWeb) {
    await FMTCObjectBoxBackend().initialise();
  }
  tz.initializeTimeZones();
  runApp(const WidgetbookApp());
}

@widgetbook.App()
class WidgetbookApp extends StatelessWidget {
  const WidgetbookApp({super.key, this.initialRoute = '/'});

  /// Where the catalog opens, e.g. `/?path=screens/people/peoplescreen/states`.
  /// The smoke test uses it to open every entry in turn.
  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return Widgetbook.material(
      initialRoute: initialRoute,
      directories: directories,
      appBuilder: _appBuilder,
      addons: [
        MaterialThemeAddon(
          themes: [
            WidgetbookTheme(name: 'Light', data: AppTheme.lightTheme),
            WidgetbookTheme(name: 'Dark', data: AppTheme.darkTheme),
          ],
        ),
        ViewportAddon([
          Viewports.none,
          IosViewports.iPhone13,
          IosViewports.iPhoneSE,
          AndroidViewports.samsungGalaxyS20,
          IosViewports.iPadPro11Inches,
          MacosViewports.macbookPro,
        ]),
        LocalizationAddon(
          locales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
        TextScaleAddon(min: 1.0, max: 2.0, divisions: 4),
        MediaPreferencesAddon(),
        // MapSpacing.xs, the first step of the spacing scale, so the grid
        // shows how a layout sits on it.
        GridAddon(8),
        // Flags tap targets under 48pt, unlabelled controls and images, and
        // text that overflows its box — the same bar a11y_constants.dart sets.
        BuilderAddon(
          name: 'Accessibility',
          builder: (context, child) => AccessibilityTools(
            checkFontOverflows: true,
            logLevel: LogLevel.warning,
            child: child,
          ),
        ),
        InspectorAddon(),
        ZoomAddon(),
      ],
    );
  }
}

/// Widgetbook's default MaterialApp, plus the app's own localizations.
///
/// The addons above wrap each entry inside this app, so routes pushed onto
/// the root navigator — dialogs, chiefly — sit outside them. Themes still
/// reach those routes (showDialog captures the caller's Theme), but
/// localizations do not, so they are registered here as well.
Widget _appBuilder(BuildContext context, Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DefaultAssetBundle(
      bundle: AppAssetBundle(rootBundle),
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );
}
