import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/utils/app_theme.dart';

/// WCAG's contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('MapSignal ink', () {
    const signals = <String, MapSignal>{
      'airport': MapPalette.airport,
      'majorStation': MapPalette.majorStation,
      'commuterRail': MapPalette.commuterRail,
      'subway': MapPalette.subway,
      'regionalStation': MapPalette.regionalStation,
      'vital': MapPalette.vital,
      'calm': MapPalette.calm,
      'due': MapPalette.due,
      'overdue': MapPalette.overdue,
      'critical': MapPalette.critical,
      'journeyConfirmed': MapPalette.journeyConfirmed,
      'journeyCancelled': MapPalette.journeyCancelled,
      'journeyPlanned': MapPalette.journeyPlanned,
    };

    // Inks known to fall short, with the task that fixes them. The test
    // fails if one of these passes, so the list can't go stale.
    const knownLow = <String, String>{
      'due (light)': 'the low text contrast task',
    };

    // Ink is the signal as text, so it has to read as text (WCAG AA, 4.5:1)
    // on the ground of its own appearance. Glass over the ground moves the
    // backdrop only slightly; the catalog contrast test checks the composed
    // result on every screen.
    for (final brightness in Brightness.values) {
      final ground = brightness == Brightness.dark
          ? MapField.groundDark
          : MapField.groundLight;
      test('every ink reaches 4.5:1 on the ${brightness.name} ground', () {
        final low = <String>{};
        final failures = <String>[];
        for (final MapEntry(key: name, value: signal) in signals.entries) {
          final key = '$name (${brightness.name})';
          final worst = ground
              .map((stop) => _contrast(signal.ink(brightness), stop))
              .reduce(math.min);
          if (worst >= 4.5) continue;
          low.add(key);
          if (!knownLow.containsKey(key)) {
            failures.add('$key: ${worst.toStringAsFixed(2)}:1');
          }
        }
        expect(failures, isEmpty, reason: 'these inks are too faint as text');
        final fixed = knownLow.keys
            .where((k) => k.endsWith('(${brightness.name})'))
            .where((k) => !low.contains(k));
        expect(
          fixed,
          isEmpty,
          reason: 'these pass now; remove them from knownLow',
        );
      });
    }
  });

  group('MapGlass inlays', () {
    test('dark inlays lighten with white; light inlays darken with ink', () {
      final darkInlay = MapGlass.inlayFill(Brightness.dark);
      final lightInlay = MapGlass.inlayFill(Brightness.light);
      expect(darkInlay.withValues(alpha: 1), Colors.white);
      expect(lightInlay.withValues(alpha: 1), MapGlass.bodyLight);
      expect(darkInlay.a, closeTo(0.07, 0.005));
      expect(lightInlay.a, closeTo(0.05, 0.005));
    });

    test('a strong inlay is always more opaque than a regular one', () {
      for (final b in Brightness.values) {
        expect(
          MapGlass.inlayFillStrong(b).a,
          greaterThan(MapGlass.inlayFill(b).a),
          reason: b.name,
        );
      }
      expect(
        MapGlass.inlayFillStrong(Brightness.dark).withValues(alpha: 1),
        Colors.white,
      );
      expect(
        MapGlass.inlayFillStrong(Brightness.light).withValues(alpha: 1),
        MapGlass.bodyLight,
      );
    });

    test('selection lift uses the documented per-appearance strengths', () {
      final dark = MapGlass.selectionLift(Brightness.dark);
      final light = MapGlass.selectionLift(Brightness.light);
      expect(dark.withValues(alpha: 1), Colors.white);
      expect(light.withValues(alpha: 1), Colors.black);
      expect(dark.a, closeTo(MapGlass.selectionLiftDark, 0.005));
      expect(light.a, closeTo(MapGlass.selectionLiftLight, 0.005));
    });
  });

  group('MapField', () {
    test('ground is the middle stop of each appearance gradient', () {
      expect(MapField.ground(Brightness.dark), MapField.groundDark[1]);
      expect(MapField.ground(Brightness.light), MapField.groundLight[1]);
      expect(
        MapField.ground(Brightness.dark),
        isNot(MapField.ground(Brightness.light)),
      );
    });

    test('each mass resolves its alpha per appearance', () {
      for (final mass in MapField.masses) {
        expect(mass.alpha(Brightness.dark), mass.alphaDark);
        expect(mass.alpha(Brightness.light), mass.alphaLight);
      }
    });
  });
}
