import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/utils/app_theme.dart';

/// Contract tests for the Refractive Glass material.
///
/// These lock the numbers that DESIGN.md §4–5 and the LLC `refractive-glass.md`
/// Tier 3 template actually specify. The material drifted out of spec once
/// already — dark mode reached 0.25 fill against a 0.15 ceiling because the
/// clamp ran before the gradient lift was added, so nothing caught it. Every
/// assertion below exists because breaking it silently degrades the material
/// into a tinted card, or silently costs a GPU layer.

Widget _host(
  Widget child, {
  Brightness brightness = Brightness.light,
  bool highContrast = false,
  TextDirection direction = TextDirection.ltr,
  bool group = true,
}) {
  final scaffold = Directionality(
    textDirection: direction,
    child: MediaQuery(
      data: MediaQueryData(highContrast: highContrast),
      child: Theme(
        data: ThemeData(brightness: brightness, useMaterial3: true),
        child: Material(child: Center(child: child)),
      ),
    ),
  );
  return group ? BackdropGroup(child: scaffold) : scaffold;
}

/// The tinted [Container] that carries the material's fill and edge.
BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(GlassContainer),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

List<double> _tintAlphas(WidgetTester tester) {
  final gradient = _decoration(tester).gradient! as LinearGradient;
  return gradient.colors.map((c) => c.a).toList();
}

RenderBackdropFilter _filter(WidgetTester tester) {
  return tester.renderObject<RenderBackdropFilter>(find.byType(BackdropFilter));
}

/// The composed blur, read through [RenderBackdropFilter.filterConfig] rather
/// than the deprecated `filter` getter.
ui.ImageFilter _blurFilter(WidgetTester tester) {
  return _filter(tester).filterConfig.filter!;
}

void main() {
  const probe = SizedBox(width: 120, height: 60);

  group('spec constants', () {
    // Every assertion elsewhere in this file reads MapGlass tokens, which makes
    // it tautological on its own: widening a token would move the goalposts and
    // stay green. These pin the tokens to the literals the specification
    // actually states, so changing the material is a deliberate two-file edit
    // with this test as the checkpoint.
    test('match the values DESIGN.md and refractive-glass.md state', () {
      // refractive-glass.md §Implementation Notes.
      expect(MapGlass.blurSigma, 20.0, reason: 'sigmaX/sigmaY 20');
      expect(MapGlass.tintMin, 0.05, reason: 'opacity floor');
      expect(MapGlass.tintMax, 0.15, reason: 'opacity ceiling');

      // DESIGN.md §5 — RefractiveGlass: 0.5px, 20% white.
      expect(MapGlass.edgeWidth, 0.5);
      expect(MapGlass.edgeLight, 0.20);

      // DESIGN.md rounded scale: sm 8 / md 16 / lg 30.
      expect(MapGlass.radiusSm, 8.0);
      expect(MapGlass.radiusMd, 16.0);
      expect(MapGlass.radiusLg, 30.0);
    });

    test('leave headroom for the sheen inside the band', () {
      // The composed top-left value is base fill + sheen. If the sheen ever
      // exceeds the band's width the clamp cannot keep the composite legal.
      expect(MapGlass.tintLight + MapGlass.sheen, lessThanOrEqualTo(0.15));
      expect(MapGlass.tintDark + MapGlass.sheen, lessThanOrEqualTo(0.15));
      expect(MapGlass.tintLight, greaterThanOrEqualTo(0.05));
    });
  });

  group('blur', () {
    testWidgets('samples at the LLC standard sigma on both axes', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const GlassContainer(child: probe)));

      // refractive-glass.md §Implementation Notes: sigmaX/sigmaY 20 is the
      // standard refractive look. A lower value reads as a scrim, not glass.
      expect(MapGlass.blurSigma, 20.0);
      expect(
        _blurFilter(tester).toString(),
        ui.ImageFilter.blur(
          sigmaX: MapGlass.blurSigma,
          sigmaY: MapGlass.blurSigma,
        ).toString(),
      );
    });

    testWidgets('a negative sigma degrades to flat rather than throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const GlassContainer(blur: -8, child: probe)),
      );

      expect(tester.takeException(), isNull);
      expect(
        _blurFilter(tester).toString(),
        ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0).toString(),
      );
    });
  });

  group('tint band', () {
    // The composed value — base fill plus the top-left sheen — is what must
    // stay inside the band. Clamping only the base is the bug that shipped.
    void expectInBand(List<double> alphas) {
      for (final a in alphas) {
        expect(
          a,
          inInclusiveRange(0.05, 0.15),
          reason:
              'composed fill $a is outside the 0.05-0.15 band; above the '
              'ceiling the surface reads as a tinted card, not glass '
              '(DESIGN.md §6)',
        );
      }
    }

    testWidgets('light stays inside the band', (tester) async {
      await tester.pumpWidget(_host(const GlassContainer(child: probe)));
      expectInBand(_tintAlphas(tester));
    });

    testWidgets('dark stays inside the band', (tester) async {
      await tester.pumpWidget(
        _host(const GlassContainer(child: probe), brightness: Brightness.dark),
      );
      expectInBand(_tintAlphas(tester));
    });

    testWidgets('dark carries more fill than light, but only slightly', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const GlassContainer(child: probe)));
      final light = _tintAlphas(tester).reduce((a, b) => a < b ? a : b);

      await tester.pumpWidget(
        _host(const GlassContainer(child: probe), brightness: Brightness.dark),
      );
      final dark = _tintAlphas(tester).reduce((a, b) => a < b ? a : b);

      expect(dark, greaterThan(light));
      expect(
        dark - light,
        lessThanOrEqualTo(0.05),
        reason:
            'dark mode buys legibility at the edge, not in the fill — a large '
            'lift here is how it turned into "dark blue software"',
      );
    });

    testWidgets('an out-of-band caller value is clamped, not honoured', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        for (final opacity in <double>[-1.0, 0.0, 0.9, 1.0]) {
          await tester.pumpWidget(
            _host(
              GlassContainer(opacity: opacity, child: probe),
              brightness: brightness,
            ),
          );
          expectInBand(_tintAlphas(tester));
        }
      }
    });

    testWidgets('lights the surface from the top-left in both appearances', (
      tester,
    ) async {
      // The sheen is a direction of light, not a direction of alpha. Dark
      // glass is a light body over the void, so more alpha reads brighter;
      // light glass is the void neutral over daylight, so more alpha reads
      // darker and the ramp inverts. Asserting raw alpha would pin the
      // implementation of one appearance and call the other one broken, so
      // this composites each end over the field it actually floats on.
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _host(const GlassContainer(child: probe), brightness: brightness),
        );
        final gradient = _decoration(tester).gradient! as LinearGradient;

        expect(gradient.begin, Alignment.topLeft);
        expect(gradient.end, Alignment.bottomRight);

        final ground = MapField.ground(brightness);
        final near = Color.alphaBlend(gradient.colors.first, ground);
        final far = Color.alphaBlend(gradient.colors.last, ground);

        expect(
          near.computeLuminance(),
          greaterThan(far.computeLuminance()),
          reason:
              'the top-left corner is the lit end of the surface; a single '
              'source of light does not move between appearances',
        );
      }
    });

    testWidgets('the light source does not mirror under RTL', (tester) async {
      // Alignment, not AlignmentDirectional, is deliberate: a room's light does
      // not move because the text does. Mirroring it would break the single
      // source of light across a screen that mixes scripts.
      await tester.pumpWidget(
        _host(const GlassContainer(child: probe), direction: TextDirection.rtl),
      );
      final gradient = _decoration(tester).gradient! as LinearGradient;

      expect(gradient.begin, Alignment.topLeft);
    });
  });

  group('precision edge', () {
    testWidgets('is a hairline in both appearances', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _host(const GlassContainer(child: probe), brightness: brightness),
        );
        final border = _decoration(tester).border! as Border;

        // DESIGN.md §5: a 0.5px semi-transparent hairline. Any heavier and
        // the surface acquires a drawn outline instead of a refractive edge.
        expect(border.top.width, 0.5);

        // The edge is drawn in the material's own body colour, which differs
        // by appearance: white catches the light in the void, and a white
        // hairline on daylight is an edge nobody can see.
        final expected = brightness == Brightness.dark
            ? Colors.white
            : MapGlass.bodyLight;
        expect(border.top.color.r, expected.r);
        expect(border.top.color.g, expected.g);
        expect(border.top.color.b, expected.b);
      }
    });

    testWidgets('dark carries a stronger edge than light', (tester) async {
      await tester.pumpWidget(_host(const GlassContainer(child: probe)));
      final light = (_decoration(tester).border! as Border).top.color.a;

      await tester.pumpWidget(
        _host(const GlassContainer(child: probe), brightness: Brightness.dark),
      );
      final dark = (_decoration(tester).border! as Border).top.color.a;

      expect(
        dark,
        greaterThan(light),
        reason: 'the edge is what defines a dark panel once the fill is capped',
      );
    });
  });

  group('GPU budget', () {
    testWidgets('shares the enclosing group\'s backdrop key', (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassContainer(child: probe),
              GlassContainer(child: probe),
              GlassContainer(child: probe),
            ],
          ),
        ),
      );

      final keys = tester
          .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter))
          .map((r) => r.backdropKey)
          .toList();

      expect(keys, hasLength(3));
      expect(keys.first, isNotNull);
      // Three panels, one backdrop sample: this is what holds the two-layer
      // ceiling in impeller-optimization.md without rationing glass.
      expect(keys.toSet(), hasLength(1));
    });

    testWidgets('an isolated surface does not join the group', (tester) async {
      await tester.pumpWidget(
        _host(const GlassContainer.isolated(child: probe)),
      );

      expect(_filter(tester).backdropKey, isNull);
    });

    testWidgets('every surface is promoted to its own repaint boundary', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const GlassContainer(child: probe)));

      // impeller-optimization.md §Promotion. Without this, an unrelated
      // ancestor repaint — a map tile, a scrolling list — re-blurs the surface.
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });

    testWidgets('a missing BackdropGroup fails loudly in debug', (
      tester,
    ) async {
      // BackdropFilter.grouped degrades silently to an unshared sample when no
      // group is found. Silence is the failure mode this assert exists to stop.
      await tester.pumpWidget(
        _host(const GlassContainer(child: probe), group: false),
      );

      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('accessibility', () {
    testWidgets('high contrast drops the blur for an opaque surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const GlassContainer(child: probe), highContrast: true),
      );

      // Flutter exposes no reduce-transparency flag, so highContrast is the
      // available proxy for the iOS/Android setting that targets this material.
      expect(find.byType(BackdropFilter), findsNothing);

      final decoration = _decoration(tester);
      expect(decoration.gradient, isNull);
      expect(decoration.color!.a, 1.0);
      expect((decoration.border! as Border).top.width, greaterThan(0));
    });

    testWidgets('high contrast needs no group and never throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const GlassContainer(child: probe),
          highContrast: true,
          group: false,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('a semantic label becomes one node, not a leaf per child', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const GlassContainer(semanticLabel: 'Finding you', child: probe)),
      );

      expect(find.bySemanticsLabel('Finding you'), findsOneWidget);
    });
  });

  group('geometry', () {
    testWidgets('honours the radius on clip, fill, and edge together', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const GlassContainer(borderRadius: MapGlass.radiusMd, child: probe),
        ),
      );

      // A clip that disagrees with the decoration leaves a visible seam.
      final clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byType(GlassContainer),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(clip.borderRadius, BorderRadius.circular(MapGlass.radiusMd));
      expect(
        _decoration(tester).borderRadius,
        BorderRadius.circular(MapGlass.radiusMd),
      );
    });

    testWidgets('a negative radius degrades to square rather than throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const GlassContainer(borderRadius: -12, child: probe)),
      );

      expect(tester.takeException(), isNull);
      expect(_decoration(tester).borderRadius, BorderRadius.zero);
    });

    testWidgets('grows with its content instead of clipping it', (
      tester,
    ) async {
      // Glass wraps translated and text-scaled content; a surface that cannot
      // grow turns a long German label into an overflow stripe.
      await tester.pumpWidget(
        _host(const GlassContainer(child: SizedBox(width: 260, height: 140))),
      );

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(GlassContainer));
      expect(size.width, greaterThanOrEqualTo(260));
      expect(size.height, greaterThanOrEqualTo(140));
    });
  });
}
