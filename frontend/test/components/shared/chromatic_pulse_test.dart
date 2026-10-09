import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/utils/app_theme.dart';

/// Contract tests for the Chromatic Pulse.
///
/// `llc-standards/context/chromatic-pulse.md` fixes this component's constants
/// and its accessibility contract, and is explicit that it is a different
/// motion category from every triggered interaction in the app. The assertions
/// here are the ones that would let it drift back into being a spinner.

Widget _host(
  Widget child, {
  bool disableAnimations = false,
  Size size = const Size(28, 28),
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Theme(
      data: AppTheme.darkTheme,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(ChromaticPulse),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as BoxDecoration;
}

void main() {
  const palette = <Color>[Color(0xFF3F51B5), Color(0xFFFF4081)];

  group('spec constants', () {
    test('match the values chromatic-pulse.md states', () {
      expect(
        MapMotion.chromaticCycle,
        const Duration(milliseconds: 3200),
        reason: 'CHROMATIC_PULSE_DURATION',
      );
      expect(
        MapMotion.chromatic,
        const Cubic(0.45, 0.0, 0.55, 1.0),
        reason: 'CHROMATIC_EASE — symmetric ease-in-out',
      );
    });

    test('do not borrow the interaction curves', () {
      // The pulse is a continuous idle loop with no user input. Reusing the
      // brand's asymmetric slow-in/snap-out curve or the return spring here is
      // called out in the spec as the wrong motion category, not a shortcut.
      expect(MapMotion.chromatic, isNot(MapMotion.strike));
    });
  });

  group('the breath', () {
    testWidgets('cycles colour and opacity together while it runs', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ChromaticPulse(colors: palette)));

      final first = _decoration(tester).color!;
      await tester.pump(const Duration(milliseconds: 800));
      final later = _decoration(tester).color!;

      expect(later, isNot(first));
      // CHROMATIC_OPACITY_RANGE 0.55-1.0, both ends inclusive of rounding.
      for (final color in <Color>[first, later]) {
        expect(color.a, greaterThanOrEqualTo(0.54));
        expect(color.a, lessThanOrEqualTo(1.0));
      }

      // Leave nothing running: a repeating controller outlives the test frame
      // and trips the pending-timer check.
      await tester.pumpWidget(_host(const SizedBox.shrink()));
    });
  });

  group('reduced motion', () {
    testWidgets('renders one static palette colour at full opacity', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ChromaticPulse(colors: palette), disableAnimations: true),
      );

      // This loop can run for the whole length of a slow load — far longer
      // than Thermal Glow's momentary lifecycle — so it must stop entirely,
      // not merely slow down.
      await tester.pumpAndSettle();
      expect(_decoration(tester).color, palette.first);
    });
  });

  group('PulseIndicator', () {
    testWidgets('breathes through the app palette and announces the wait', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          const PulseIndicator(label: 'Loading map'),
          size: const Size(240, 160),
        ),
      );
      await tester.pump();

      final pulse = tester.widget<ChromaticPulse>(find.byType(ChromaticPulse));
      expect(pulse.colors.length, greaterThanOrEqualTo(3));
      expect(pulse.colors.last, MapPalette.thermalCorona);

      // An unlabelled animated box is invisible to a screen reader; the wait
      // is the whole content of the surface at that moment, and it is
      // announced once rather than twice over.
      final node = tester.getSemantics(
        find
            .descendant(
              of: find.byType(PulseIndicator),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(node.label, 'Loading map');
      expect(node.flagsCollection.isLiveRegion, isTrue);

      await tester.pumpWidget(_host(const SizedBox.shrink()));
      semantics.dispose();
    });
  });
}
