import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/ambient_field.dart';
import 'package:map_my_friends/components/shared/ambient_scaffold.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/components/shared/glass_header.dart';
import 'package:map_my_friends/utils/app_theme.dart';

void main() {
  setUpAll(() {
    // AppTheme fetches its brand faces at runtime; render offline.
    AppTheme.textThemeBuilder = (color) => Typography.material2021().black
        .apply(bodyColor: color, displayColor: color);
    AppTheme.resetThemeCache();
  });

  tearDownAll(() {
    AppTheme.textThemeBuilder = AppTheme.buildBrandTextTheme;
    AppTheme.resetThemeCache();
  });

  /// Reduced motion stops the field's drift, so the tree can settle.
  Future<void> pumpScaffold(
    WidgetTester tester,
    AmbientScaffold scaffold, {
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: scaffold,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Scaffold innerScaffold(WidgetTester tester) => tester.widget<Scaffold>(
    find.descendant(
      of: find.byType(AmbientScaffold),
      matching: find.byType(Scaffold),
    ),
  );

  testWidgets('paints its own field under a transparent scaffold', (
    tester,
  ) async {
    await pumpScaffold(tester, const AmbientScaffold(body: Text('body')));

    expect(find.text('body'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AmbientScaffold),
        matching: find.byType(AmbientField),
      ),
      findsOneWidget,
    );
    final scaffold = innerScaffold(tester);
    expect(scaffold.backgroundColor, Colors.transparent);
    expect(scaffold.extendBodyBehindAppBar, isTrue);
  });

  testWidgets('owns a backdrop group, so glass headers work inside it', (
    tester,
  ) async {
    await pumpScaffold(
      tester,
      const AmbientScaffold(
        header: GlassHeader(title: 'Trips'),
        body: Text('body'),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(GlassContainer), findsOneWidget);
    // The header sits above the body rather than over it.
    expect(
      tester.getBottomLeft(find.byType(GlassHeader)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('body')).dy),
    );
  });

  testWidgets('passes the app bar, FAB and inset choice to the scaffold', (
    tester,
  ) async {
    await pumpScaffold(
      tester,
      AmbientScaffold(
        appBar: AppBar(title: const Text('Legacy')),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: false,
        body: const Text('body'),
      ),
    );

    expect(find.text('Legacy'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    final scaffold = innerScaffold(tester);
    expect(scaffold.resizeToAvoidBottomInset, isFalse);
    expect(scaffold.extendBodyBehindAppBar, isFalse);
  });

  for (final brightness in Brightness.values) {
    testWidgets('appearance pins the surface to ${brightness.name}', (
      tester,
    ) async {
      // The app is in the opposite appearance.
      final appTheme = ThemeData(
        brightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      );
      await pumpScaffold(
        tester,
        AmbientScaffold(appearance: brightness, body: const Text('body')),
        theme: appTheme,
      );

      expect(
        Theme.of(tester.element(find.text('body'))).brightness,
        brightness,
      );
    });
  }

  testWidgets('without an appearance it follows the app', (tester) async {
    await pumpScaffold(
      tester,
      const AmbientScaffold(body: Text('body')),
      theme: ThemeData(brightness: Brightness.dark),
    );

    expect(
      Theme.of(tester.element(find.text('body'))).brightness,
      Brightness.dark,
    );
  });
}
