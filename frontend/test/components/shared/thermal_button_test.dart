import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/components/shared/glass_inlay.dart';
import 'package:map_my_friends/components/shared/thermal_button.dart';
import 'package:map_my_friends/utils/app_theme.dart';

void main() {
  Future<void> pumpButton(WidgetTester tester, ThermalButton button) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: button)),
        ),
      );

  BoxDecoration fill(WidgetTester tester) =>
      tester
              .widget<Container>(
                find
                    .descendant(
                      of: find.byType(ThermalButton),
                      matching: find.byWidgetPredicate(
                        (w) => w is Container && w.decoration is BoxDecoration,
                      ),
                    )
                    .first,
              )
              .decoration!
          as BoxDecoration;

  Color labelColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style!.color!;

  testWidgets('fires onPressed when tapped', (tester) async {
    var presses = 0;
    await pumpButton(
      tester,
      ThermalButton(label: 'Save', onPressed: () => presses++),
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(presses, 1);
  });

  testWidgets('is a labelled, enabled button to assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpButton(tester, ThermalButton(label: 'Save', onPressed: () {}));

    expect(
      tester.getSemantics(find.byType(ThermalButton)),
      matchesSemantics(
        label: 'Save',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('without onPressed it is disabled and dimmed', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpButton(
      tester,
      const ThermalButton(label: 'Save', onPressed: null),
    );

    expect(
      tester.getSemantics(find.byType(ThermalButton)),
      matchesSemantics(label: 'Save', isButton: true, hasEnabledState: true),
    );
    expect(labelColor(tester, 'Save').a, closeTo(0.38, 0.01));
    expect(fill(tester).color!.a, closeTo(0.38, 0.01));
    semantics.dispose();
  });

  testWidgets('loading swaps the label for a pulse and ignores taps', (
    tester,
  ) async {
    var presses = 0;
    await pumpButton(
      tester,
      ThermalButton(
        label: 'Save',
        icon: Icons.check,
        loading: true,
        onPressed: () => presses++,
      ),
    );

    expect(find.byType(ChromaticPulse), findsOneWidget);
    // The label stays in the tree, invisible, so the button keeps its size.
    final hidden = tester.widget<Opacity>(
      find.ancestor(of: find.text('Save'), matching: find.byType(Opacity)),
    );
    expect(hidden.opacity, 0);
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.tap(find.byType(ThermalButton));
    await tester.pump(const Duration(milliseconds: 100));
    expect(presses, 0);
  });

  testWidgets('shows a leading icon in the label colour', (tester) async {
    await pumpButton(
      tester,
      ThermalButton(label: 'Add', icon: Icons.add, onPressed: () {}),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.add));
    expect(icon.color, labelColor(tester, 'Add'));
  });

  group('tone', () {
    testWidgets('primary fills with the brand colour', (tester) async {
      await pumpButton(tester, ThermalButton(label: 'Go', onPressed: () {}));
      final scheme = Theme.of(tester.element(find.text('Go'))).colorScheme;

      expect(fill(tester).color, scheme.primary);
      expect(labelColor(tester, 'Go'), scheme.onPrimary);
      expect(find.byType(GlassInlay), findsNothing);
    });

    testWidgets('danger reaches for the thermal core', (tester) async {
      await pumpButton(
        tester,
        ThermalButton(
          label: 'Delete',
          tone: ThermalButtonTone.danger,
          onPressed: () {},
        ),
      );

      expect(fill(tester).color, MapPalette.thermalCore);
      expect(labelColor(tester, 'Delete'), Colors.white);
    });

    testWidgets('secondary sits in a glass inlay', (tester) async {
      await pumpButton(
        tester,
        ThermalButton(
          label: 'Cancel',
          tone: ThermalButtonTone.secondary,
          onPressed: () {},
        ),
      );
      final scheme = Theme.of(tester.element(find.text('Cancel'))).colorScheme;

      expect(find.byType(GlassInlay), findsOneWidget);
      expect(labelColor(tester, 'Cancel'), scheme.onSurface);
    });
  });

  group('size', () {
    testWidgets('never smaller than a 48dp target', (tester) async {
      await pumpButton(tester, ThermalButton(label: 'X', onPressed: () {}));

      final size = tester.getSize(find.byType(ThermalButton));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('expand fills the available width', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: Column(
                children: [
                  ThermalButton(label: 'Wide', expand: true, onPressed: () {}),
                  ThermalButton(label: 'Snug', onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(ThermalButton).first).width, 300);
      expect(
        tester.getSize(find.byType(ThermalButton).last).width,
        lessThan(300),
      );
    });
  });
}
