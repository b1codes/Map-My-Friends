import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/ambient_field.dart';
import 'package:map_my_friends/utils/app_theme.dart';

/// Contract tests for the Ambient Field.
///
/// The field is the reason glass is visible anywhere outside the map, so the
/// assertions here are about the things that would silently un-make it: an
/// orbit that does not close, motion that ignores the user's setting, or a
/// decorative layer that shows up in the semantics tree.

Widget _host({
  Brightness brightness = Brightness.dark,
  bool disableAnimations = false,
  bool highContrast = false,
}) {
  return MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
      highContrast: highContrast,
    ),
    child: Theme(
      data: ThemeData(brightness: brightness),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: AmbientField(),
      ),
    ),
  );
}

void main() {
  group('orbits', () {
    test('close exactly at the end of a cycle', () {
      // Each mass traces a Lissajous figure over one MapField.cycle. Whole
      // numbers of turns per axis are what make the composition continuous
      // when the controller wraps from 1.0 back to 0.0; a fractional value
      // would snap every mass to a new position once every two minutes, in
      // full view, on every screen in the app.
      for (final mass in MapField.masses) {
        expect(mass.cyclesX, greaterThanOrEqualTo(1));
        expect(mass.cyclesY, greaterThanOrEqualTo(1));
        expect(mass.cyclesX, mass.cyclesX.toInt());
        expect(mass.cyclesY, mass.cyclesY.toInt());
      }
    });

    test('stay inside the surface they drift across', () {
      // Centre plus amplitude is where a mass reaches; past the surface it is
      // paying for a shader that never lands a lit pixel on screen.
      for (final mass in MapField.masses) {
        expect(mass.center.dx + mass.amplitude.dx, lessThanOrEqualTo(1.0));
        expect(mass.center.dx - mass.amplitude.dx, greaterThanOrEqualTo(0.0));
        expect(mass.center.dy + mass.amplitude.dy, lessThanOrEqualTo(1.0));
        expect(mass.center.dy - mass.amplitude.dy, greaterThanOrEqualTo(0.0));
      }
    });

    test('never reach the tint ceiling glass reserves for itself', () {
      // The field is what glass refracts. A mass at panel-fill opacity would
      // compete with the material instead of feeding it.
      for (final mass in MapField.masses) {
        for (final brightness in Brightness.values) {
          expect(mass.alpha(brightness), lessThan(0.25));
          expect(mass.alpha(brightness), greaterThan(0.0));
        }
      }
    });
  });

  group('appearances', () {
    test('the void is near-neutral, not dark blue software', () {
      // DESIGN.md §6. A ground with real chroma is how a void becomes a
      // navy app; the only colour in the field belongs to the masses.
      for (final color in MapField.groundDark) {
        final channels = <double>[color.r, color.g, color.b];
        final spread =
            channels.reduce((a, b) => a > b ? a : b) -
            channels.reduce((a, b) => a < b ? a : b);
        expect(spread, lessThan(0.05));
        expect(color.computeLuminance(), lessThan(0.05));
      }
    });

    test('daylight stays light enough for dark glass to read against', () {
      for (final color in MapField.groundLight) {
        expect(color.computeLuminance(), greaterThan(0.75));
      }
    });
  });

  group('accessibility', () {
    testWidgets(
      'reduced motion freezes the composition instead of removing it',
      (tester) async {
        await tester.pumpWidget(_host(disableAnimations: true));

        // A repeating controller never settles. Reaching the settle means the
        // drift really stopped — and the CustomPaint is still there, because
        // the field is what makes the glass above it legible.
        await tester.pumpAndSettle();
        expect(find.byType(CustomPaint), findsWidgets);
      },
    );

    testWidgets('high contrast collapses to one flat ground', (tester) async {
      await tester.pumpWidget(_host(highContrast: true));
      await tester.pumpAndSettle();

      final box = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(AmbientField),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(box.color, MapField.ground(Brightness.dark));
    });

    testWidgets('is excluded from semantics', (tester) async {
      await tester.pumpWidget(_host(disableAnimations: true));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AmbientField),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });
  });
}
