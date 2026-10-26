import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/utils/app_theme.dart';

void main() {
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
