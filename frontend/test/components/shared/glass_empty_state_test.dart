import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/glass_empty_state.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:map_my_friends/components/shared/thermal_button.dart';
import 'package:map_my_friends/components/shared/thermal_response.dart';

/// The three screens this component replaced had drifted apart in typography,
/// alignment, and button styling. These tests hold the consolidated version to
/// the design system so the next empty state cannot drift back.

Widget _host(
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: BackdropGroup(child: Scaffold(body: child)),
    ),
  );
}

const _basic = GlassEmptyState(
  icon: Icons.route_outlined,
  title: 'No Trips Yet',
  message: 'Plan your first route on the map!',
);

void main() {
  testWidgets('renders subject, headline, and guidance', (tester) async {
    await tester.pumpWidget(_host(_basic));

    expect(find.byIcon(Icons.route_outlined), findsOneWidget);
    expect(find.text('No Trips Yet'), findsOneWidget);
    expect(find.text('Plan your first route on the map!'), findsOneWidget);
  });

  testWidgets('headline uses the display voice, not a raw TextStyle', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_basic));

    // DESIGN.md §3: Montserrat carries display-level hierarchy. Two of the
    // three originals hard-coded TextStyle(fontSize: 20), which silently
    // dropped the brand face.
    final context = tester.element(find.text('No Trips Yet'));
    final expected = Theme.of(context).textTheme.titleLarge!;
    final rendered = tester.widget<Text>(find.text('No Trips Yet')).style!;

    expect(rendered.fontFamily, expected.fontFamily);
    expect(rendered.fontFamily, contains('Montserrat'));
    expect(rendered.fontSize, expected.fontSize);
  });

  testWidgets('guidance uses the body voice at reduced emphasis', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_basic));

    final style = tester
        .widget<Text>(find.text('Plan your first route on the map!'))
        .style!;

    expect(style.fontFamily, contains('OpenSans'));
    expect(style.color!.a, closeTo(0.7, 0.01));
  });

  testWidgets('both texts are centred', (tester) async {
    await tester.pumpWidget(_host(_basic));

    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.textAlign, TextAlign.center);
    }
  });

  group('action', () {
    testWidgets('is absent when the state offers no resolution', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_basic));
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('fires its callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          GlassEmptyState(
            icon: Icons.route_outlined,
            title: 'No Trips Yet',
            message: 'Plan your first route.',
            actionLabel: 'Start Planning',
            onAction: () => taps++,
          ),
        ),
      );

      await tester.tap(find.text('Start Planning'));
      expect(taps, 1);
    });

    testWidgets('carries a leading icon when given one', (tester) async {
      await tester.pumpWidget(
        _host(
          GlassEmptyState(
            icon: Icons.people_outline,
            title: 'No Friends Added Yet',
            message: 'Add friends and family.',
            actionLabel: 'Add Your First Friend',
            actionIcon: Icons.person_add_alt_1,
            onAction: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);
    });

    testWidgets('is flat and on the radius scale', (tester) async {
      await tester.pumpWidget(
        _host(
          GlassEmptyState(
            icon: Icons.route_outlined,
            title: 'No Trips Yet',
            message: 'Plan your first route.',
            actionLabel: 'Start Planning',
            onAction: () {},
          ),
        ),
      );

      // The CTA is the app's own action now, not a Material button wearing
      // the design system's numbers.
      expect(find.byType(ThermalButton), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);

      // DESIGN.md §6 bans drop shadows; depth here is the glass behind it.
      final decorations = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ThermalButton),
              matching: find.byType(Container),
            ),
          )
          .map((container) => container.decoration)
          .whereType<BoxDecoration>();
      for (final decoration in decorations) {
        expect(decoration.boxShadow, anyOf(isNull, isEmpty));
      }

      final response = tester.widget<ThermalResponse>(
        find.descendant(
          of: find.byType(ThermalButton),
          matching: find.byType(ThermalResponse),
        ),
      );
      expect(
        response.borderRadius,
        MapGlass.radiusSm,
        reason: 'DESIGN.md components.button-thermal uses rounded.sm',
      );
    });

    testWidgets('a label without a callback is rejected at construction', (
      tester,
    ) async {
      expect(
        () => GlassEmptyState(
          icon: Icons.route_outlined,
          title: 'No Trips Yet',
          message: 'Plan your first route.',
          actionLabel: 'Start Planning',
        ),
        throwsAssertionError,
      );
    });
  });

  testWidgets('scrolls instead of overflowing a small screen at large text', (
    tester,
  ) async {
    // The panel is deliberately generous, and an empty state is guaranteed to
    // be seen on a first run — including by someone at maximum text size on the
    // smallest phone this project supports.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        GlassEmptyState(
          icon: Icons.people_outline,
          title: 'No Friends Added Yet',
          message:
              'Add friends and family to see their locations on the map and '
              'plan shared routes!',
          actionLabel: 'Add Your First Friend',
          actionIcon: Icons.person_add_alt_1,
          onAction: () {},
        ),
        size: const Size(320, 568),
        textScale: 3.0,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('spacing comes from the scale, not from stray numbers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        GlassEmptyState(
          icon: Icons.route_outlined,
          title: 'No Trips Yet',
          message: 'Plan your first route.',
          actionLabel: 'Start Planning',
          onAction: () {},
        ),
      ),
    );

    // Height-only boxes are the layout gaps; Icon builds a square SizedBox of
    // its own, which is a glyph size rather than a spacing decision.
    final gaps = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((b) => b.width == null && b.height != null)
        .map((b) => b.height!)
        .toSet();

    const scale = <double>[
      MapSpacing.xs,
      MapSpacing.sm,
      MapSpacing.md,
      MapSpacing.lg,
      MapSpacing.panel,
    ];
    for (final gap in gaps) {
      expect(scale, contains(gap), reason: '$gap is off the spacing scale');
    }
  });
}
