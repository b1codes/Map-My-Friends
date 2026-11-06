import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/glass_inlay.dart';
import 'package:map_my_friends/utils/app_theme.dart';

void main() {
  Future<BoxDecoration> pumpInlay(
    WidgetTester tester,
    GlassInlay inlay, {
    Brightness brightness = Brightness.light,
    bool highContrast = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: MediaQuery(
          data: MediaQueryData(highContrast: highContrast),
          child: Scaffold(body: Center(child: inlay)),
        ),
      ),
    );
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(GlassInlay),
            matching: find.byType(Container),
          )
          .first,
    );
    return container.decoration! as BoxDecoration;
  }

  const child = Text('inlaid');

  testWidgets('renders its child at the requested size', (tester) async {
    await pumpInlay(
      tester,
      const GlassInlay(width: 120, height: 40, child: child),
    );

    expect(find.text('inlaid'), findsOneWidget);
    expect(tester.getSize(find.byType(GlassInlay)), const Size(120, 40));
  });

  for (final brightness in Brightness.values) {
    testWidgets('uses the ${brightness.name} inlay fill and edge', (
      tester,
    ) async {
      final decoration = await pumpInlay(
        tester,
        const GlassInlay(child: child),
        brightness: brightness,
      );

      expect(decoration.color, MapGlass.inlayFill(brightness));
      final border = decoration.border! as Border;
      expect(border.top.color, MapGlass.inlayEdge(brightness));
      expect(border.top.width, MapGlass.edgeWidth);
    });

    testWidgets('strong deepens the ${brightness.name} well', (tester) async {
      final decoration = await pumpInlay(
        tester,
        const GlassInlay(strong: true, child: child),
        brightness: brightness,
      );

      expect(decoration.color, MapGlass.inlayFillStrong(brightness));
    });
  }

  testWidgets('edge: false draws no border', (tester) async {
    final decoration = await pumpInlay(
      tester,
      const GlassInlay(edge: false, child: child),
    );

    expect(decoration.border, isNull);
  });

  testWidgets('high contrast trades the tint for an opaque, ruled surface', (
    tester,
  ) async {
    final decoration = await pumpInlay(
      tester,
      const GlassInlay(strong: true, child: child),
      highContrast: true,
    );
    final theme = Theme.of(tester.element(find.text('inlaid')));

    expect(decoration.color, theme.colorScheme.surface);
    final border = decoration.border! as Border;
    expect(border.top.color, theme.dividerColor);
    expect(border.top.width, 1.0);
  });

  testWidgets('honours a custom radius', (tester) async {
    final decoration = await pumpInlay(
      tester,
      const GlassInlay(borderRadius: 4, child: child),
    );

    expect(decoration.borderRadius, BorderRadius.circular(4));
  });
}
