import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/thermal_response.dart';
import 'package:map_my_friends/utils/app_theme.dart';

/// The Thermal Glow is specified numerically — 50ms excitation, 300ms
/// dissipation, and a stiffness-180 / damping-12 return — so it can be tested
/// numerically. These hold the component to the physics rather than to a
/// screenshot, which is the only thing a still frame cannot capture.

Widget _host({bool reduceMotion = false, VoidCallback? onTap}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: ThermalResponse(
          onTap: onTap,
          child: const SizedBox(width: 44, height: 44),
        ),
      ),
    ),
  );
}

/// The surface's current scale, read off the rendered transform.
double _scale(WidgetTester tester) {
  final t = tester.widget<Transform>(find.byType(Transform));
  return t.transform.storage[0];
}

bool _isGlowing(WidgetTester tester) =>
    find.byType(DecoratedBox).evaluate().isNotEmpty;

/// Presses and pumps one frame so the controllers actually start: a controller
/// begun during a frame does not advance until the next one.
Future<TestGesture> _press(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ThermalResponse)),
  );
  await tester.pump();
  return gesture;
}

Future<void> _lift(WidgetTester tester, TestGesture gesture) async {
  await gesture.up();
  await tester.pump();
}

void main() {
  group('spec constants', () {
    // Everything below reads MapMotion tokens, which is tautological on its
    // own: widening a duration would move the goalposts and stay green. These
    // pin the tokens to the values interaction-physics.md states.
    test('match llc-standards/interaction-physics.md', () {
      expect(MapMotion.excitation, const Duration(milliseconds: 50));
      expect(MapMotion.dissipation, const Duration(milliseconds: 300));
      expect(MapMotion.springStiffness, 180.0);
      expect(MapMotion.springDamping, 12.0);
      expect(MapMotion.springMass, 1.0);
    });

    test('use the only curvature the spec permits', () {
      // "All non-spring animations must utilise a custom Quart.out or
      // Quint.out curve." The component shipped easeOutExpo, which is neither.
      expect(MapMotion.strike, anyOf(Curves.easeOutQuart, Curves.easeOutQuint));
    });

    test('the return spring is underdamped', () {
      // Damping below 2*sqrt(k*m) is what produces the single pass through
      // neutral. Critically damped would ease to a stop and read as soft.
      final critical =
          2 * math.sqrt(MapMotion.springStiffness * MapMotion.springMass);
      expect(MapMotion.springDamping, lessThan(critical));
    });
  });

  group('excitation', () {
    testWidgets('reaches full heat within the 50ms strike', (tester) async {
      await tester.pumpWidget(_host());
      expect(_isGlowing(tester), isFalse, reason: 'cold at rest');

      await _press(tester);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        _isGlowing(tester),
        isTrue,
        reason: 'heat rises during the strike',
      );

      await tester.pump(MapMotion.excitation);
      // Fully struck: the surface is at its deepest yield.
      expect(_scale(tester), closeTo(1.0 - MapMotion.pressDepth, 0.001));
    });

    testWidgets('the surface yields, but barely', (tester) async {
      await tester.pumpWidget(_host());
      await _press(tester);
      await tester.pump(MapMotion.excitation);

      final scale = _scale(tester);
      expect(scale, lessThan(1.0), reason: 'PRODUCT.md asks for mass');
      expect(
        scale,
        greaterThan(0.94),
        reason: 'a precision instrument, not a toy — felt more than seen',
      );
    });
  });

  group('dissipation', () {
    testWidgets('cools to nothing over the 300ms cycle', (tester) async {
      await tester.pumpWidget(_host());
      final gesture = await _press(tester);
      await tester.pump(MapMotion.excitation);

      await _lift(tester, gesture);
      expect(_isGlowing(tester), isTrue, reason: 'still cooling');

      // The literal, not the token: 300ms is the specified cooling cycle.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(
        _isGlowing(tester),
        isFalse,
        reason: 'the 300ms cooling cycle must actually finish in 300ms',
      );

      await tester.pumpAndSettle();
    });
  });

  group('return spring', () {
    testWidgets('overshoots neutral — it is a spring, not an ease', (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      final gesture = await _press(tester);
      await tester.pump(MapMotion.excitation);
      await _lift(tester, gesture);

      var overshoot = 0.0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        overshoot = overshoot > _scale(tester) ? overshoot : _scale(tester);
      }

      // An eased return approaches 1.0 from below and stops. Damping 12
      // against stiffness 180 is underdamped, so the surface passes neutral
      // once — that pass is the "sharp, authoritative return" in
      // interaction-physics.md, and an ease cannot produce it.
      expect(
        overshoot,
        greaterThan(1.0),
        reason: 'no overshoot means the spring was replaced by a curve',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('oscillation stays minimal', (tester) async {
      await tester.pumpWidget(_host());
      final gesture = await _press(tester);
      await tester.pump(MapMotion.excitation);
      await _lift(tester, gesture);

      var peak = 0.0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        peak = peak > _scale(tester) ? peak : _scale(tester);
      }

      // "Minimal oscillation, dead-stop accuracy": the rebound past neutral
      // must stay well under the depression that caused it.
      expect(peak - 1.0, lessThan(MapMotion.pressDepth * 0.5));
      await tester.pumpAndSettle();
    });

    testWidgets('settles exactly at neutral', (tester) async {
      await tester.pumpWidget(_host());
      final gesture = await _press(tester);
      await tester.pump(MapMotion.excitation);
      await _lift(tester, gesture);
      await tester.pumpAndSettle();

      expect(_scale(tester), closeTo(1.0, 0.001));
    });

    testWidgets('an interrupted return resumes rather than restarting', (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      final first = await _press(tester);
      await tester.pump(MapMotion.excitation);
      await _lift(tester, first);
      await tester.pump(const Duration(milliseconds: 40));

      final midReturn = _scale(tester);
      expect(midReturn, lessThan(1.0), reason: 'still on the way back');

      final second = await _press(tester);
      await tester.pump();
      expect(tester.takeException(), isNull);

      await _lift(tester, second);
      await tester.pumpAndSettle();
      expect(_scale(tester), closeTo(1.0, 0.001));
    });
  });

  group('reduced motion', () {
    testWidgets('drops the displacement but keeps the feedback', (
      tester,
    ) async {
      await tester.pumpWidget(_host(reduceMotion: true));
      final gesture = await _press(tester);
      await tester.pump(MapMotion.excitation);

      // Spatial movement is what the setting is about; the glow is colour and
      // luminosity, and it is the part that confirms the tap landed.
      expect(_scale(tester), closeTo(1.0, 0.0001));
      expect(_isGlowing(tester), isTrue);

      await _lift(tester, gesture);
      await tester.pumpAndSettle();
      expect(_isGlowing(tester), isFalse);
    });
  });

  group('behaviour', () {
    testWidgets('still reports taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(onTap: () => taps++));

      await tester.tap(find.byType(ThermalResponse));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    // A finger that went down on a surface the app then removed (a sheet
    // that closed, a screen that was replaced) still lifts, and the pointer
    // up is still delivered to it. It used to animate disposed controllers:
    // "AnimationController.reverse() called after dispose()". Found by the
    // monkey test.
    for (final reduceMotion in [false, true]) {
      testWidgets('a finger lifting after the surface is gone does nothing'
          '${reduceMotion ? ' (reduced motion)' : ''}', (tester) async {
        await tester.pumpWidget(_host(reduceMotion: reduceMotion));
        final gesture = await _press(tester);

        await tester.pumpWidget(const SizedBox.shrink());
        await gesture.up();
        await tester.pump();

        expect(tester.takeException(), isNull);
      });

      testWidgets('a cancelled pointer after the surface is gone does nothing'
          '${reduceMotion ? ' (reduced motion)' : ''}', (tester) async {
        await tester.pumpWidget(_host(reduceMotion: reduceMotion));
        final gesture = await _press(tester);

        await tester.pumpWidget(const SizedBox.shrink());
        await gesture.cancel();
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the glow is painted over the child but never hit-tests', (
      tester,
    ) async {
      await tester.pumpWidget(_host(onTap: () {}));
      final gesture = await _press(tester);
      await tester.pump(MapMotion.excitation);

      // The glow fills the surface above the child in the Stack. It carries no
      // fill today, so it happens not to absorb pointers — but a future tint
      // would, silently, and only on a pressed control. Hold the guard
      // structurally rather than trusting that omission.
      expect(
        find.ancestor(
          of: find.byType(DecoratedBox),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );

      await _lift(tester, gesture);
      await tester.pumpAndSettle();
    });

    testWidgets('disposes cleanly mid-animation', (tester) async {
      await tester.pumpWidget(_host());
      await _press(tester);
      await tester.pump(const Duration(milliseconds: 20));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });
  });
}
