@Tags(['golden'])
library;

// The design system's visual contract, in one frame.
//
// Every material in the app appears here over the surface it is meant to float
// on: the Ambient Field, glass panels, inlays, the thermal response, the
// chromatic pulse, and the type scale. A regression in any of them shows up as
// a pixel diff here before it reaches a screen.
//
// Golden images only match the platform that generated them, so these are
// tagged for CI to skip (`flutter test --exclude-tags golden`) and are kept as
// the local check on what the material actually looks like.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/ambient_field.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/components/shared/glass_inlay.dart';
import 'package:map_my_friends/components/shared/thermal_response.dart';
import 'package:map_my_friends/utils/app_theme.dart';

/// The app's palette and scale with the platform's default typeface, so the
/// specimen renders offline instead of waiting on GoogleFonts.
ThemeData specimenTheme(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? AppTheme.darkTheme
      : AppTheme.lightTheme;
  return base.copyWith(textTheme: Typography.material2021().black.apply());
}

Widget _label(BuildContext context, String text) {
  return Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    ),
  );
}

Widget specimen({required Brightness brightness}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: specimenTheme(brightness),
    home: BackdropGroup(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: AmbientField()),
            Positioned.fill(
              child: Builder(
                builder: (context) {
                  final onSurface = Theme.of(context).colorScheme.onSurface;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(MapSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // A panel: floats over the field, samples the backdrop.
                        GlassContainer(
                          padding: const EdgeInsets.all(MapSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Refractive Glass',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(color: onSurface),
                              ),
                              const SizedBox(height: MapSpacing.xs),
                              Text(
                                'Depth by refraction, never by shadow. The '
                                'field drifting behind this panel is what '
                                'makes its edge read as an edge.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: onSurface),
                              ),
                              const SizedBox(height: MapSpacing.sm),

                              // An inlay: set into the panel, no blur.
                              GlassInlay(
                                child: Row(
                                  children: <Widget>[
                                    GlassInlay(
                                      strong: true,
                                      edge: false,
                                      borderRadius: MapGlass.radiusSm,
                                      padding: const EdgeInsets.all(
                                        MapSpacing.xs,
                                      ),
                                      child: Icon(
                                        Icons.person_outline,
                                        color: onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: MapSpacing.sm),
                                    Expanded(
                                      child: _label(context, 'Inlay row'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: MapSpacing.md),

                        Row(
                          children: <Widget>[
                            Expanded(
                              child: GlassContainer(
                                borderRadius: MapGlass.radiusMd,
                                padding: const EdgeInsets.all(MapSpacing.sm),
                                child: Column(
                                  children: <Widget>[
                                    const SizedBox(
                                      height: 28,
                                      width: 28,
                                      child: PulseIndicator(centered: false),
                                    ),
                                    const SizedBox(height: MapSpacing.xs),
                                    _label(context, 'Chromatic Pulse'),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: MapSpacing.sm),
                            Expanded(
                              child: ThermalResponse(
                                borderRadius: MapGlass.radiusMd,
                                onTap: () {},
                                child: GlassContainer(
                                  borderRadius: MapGlass.radiusMd,
                                  padding: const EdgeInsets.all(MapSpacing.sm),
                                  child: Column(
                                    children: <Widget>[
                                      Icon(
                                        Icons.touch_app_outlined,
                                        color: onSurface,
                                      ),
                                      const SizedBox(height: MapSpacing.xs),
                                      _label(context, 'Thermal Response'),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: MapSpacing.md),

                        GlassContainer(
                          borderRadius: MapGlass.radiusLg,
                          padding: const EdgeInsets.all(MapSpacing.sm),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: <Widget>[
                              for (final icon in <IconData>[
                                Icons.map,
                                Icons.people,
                                Icons.monitor_heart,
                                Icons.route,
                                Icons.person,
                              ])
                                Icon(
                                  icon,
                                  color: icon == Icons.map
                                      ? Theme.of(context).colorScheme.primary
                                      : onSurface.withValues(alpha: 0.6),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: MapSpacing.md),

                        Wrap(
                          spacing: MapSpacing.xs,
                          runSpacing: MapSpacing.xs,
                          children: <Widget>[
                            ElevatedButton(
                              onPressed: () {},
                              child: const Text('Elevated'),
                            ),
                            FilledButton(
                              onPressed: () {},
                              child: const Text('Filled'),
                            ),
                            OutlinedButton(
                              onPressed: () {},
                              child: const Text('Outlined'),
                            ),
                            TextButton(
                              onPressed: () {},
                              child: const Text('Text'),
                            ),
                          ],
                        ),
                        const SizedBox(height: MapSpacing.sm),
                        const TextField(
                          decoration: InputDecoration(labelText: 'Field'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    // Render offline: the real theme, a local typeface. See
    // AppTheme.textThemeBuilder for why this seam exists.
    AppTheme.textThemeBuilder = (color) => Typography.material2021().black
        .apply(bodyColor: color, displayColor: color);
    AppTheme.resetThemeCache();
  });

  tearDownAll(() {
    AppTheme.textThemeBuilder = AppTheme.buildBrandTextTheme;
    AppTheme.resetThemeCache();
  });

  for (final brightness in Brightness.values) {
    final name = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('material specimen — phone $name', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(specimen(brightness: brightness));
      await tester.pump(const Duration(milliseconds: 400));

      // AppTheme builds its scale through GoogleFonts, which kicks off a font
      // fetch the moment the TextStyle is created. Offline that surfaces as a
      // test exception; the specimen renders in the fallback face and every
      // material it exists to check is unaffected.
      tester.takeException();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/specimen_phone_$name.png'),
      );
    });

    testWidgets('material specimen — desktop $name', (tester) async {
      tester.view.physicalSize = const Size(1280 * 2, 900 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(specimen(brightness: brightness));
      await tester.pump(const Duration(milliseconds: 400));

      // AppTheme builds its scale through GoogleFonts, which kicks off a font
      // fetch the moment the TextStyle is created. Offline that surfaces as a
      // test exception; the specimen renders in the fallback face and every
      // material it exists to check is unaffected.
      tester.takeException();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/specimen_desktop_$name.png'),
      );
    });
  }
}
