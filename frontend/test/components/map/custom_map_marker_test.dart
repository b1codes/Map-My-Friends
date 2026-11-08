import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/map/custom_map_marker.dart';

void main() {
  group('CustomMapMarker', () {
    testWidgets('renders different pin styles correctly', (tester) async {
      final styles = ['circle', 'square', 'diamond', 'triangle', 'teardrop'];

      for (final style in styles) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomMapMarker(
                pinColorHex: '#FF0000',
                pinStyle: style,
                pinIconType: 'none',
              ),
            ),
          ),
        );

        if (style == 'triangle') {
          expect(find.byType(CustomPaint), findsAtLeast(1));
        } else {
          expect(find.byType(Container), findsAtLeast(1));
        }
      }
    });

    // The colour comes from the API. Anything but #RRGGBB made int.parse
    // throw, and every screen drawing that pin with it. The API now refuses
    // such colours, but older records may hold one. Found by the nightly API
    // fuzz test.
    for (final hex in ['7', 'red', '#12345', '', '#GGGGGG']) {
      testWidgets('draws a pin whose colour "$hex" is not a hex colour', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomMapMarker(
                pinColorHex: hex,
                pinStyle: 'circle',
                pinIconType: 'initials',
                initials: 'AB',
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('AB'), findsOneWidget);
      });
    }

    testWidgets('renders initials correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomMapMarker(
              pinColorHex: '#00FF00',
              pinStyle: 'circle',
              pinIconType: 'initials',
              initials: 'AB',
            ),
          ),
        ),
      );

      expect(find.text('AB'), findsOneWidget);
    });

    testWidgets('renders emoji correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomMapMarker(
              pinColorHex: '#0000FF',
              pinStyle: 'square',
              pinIconType: 'emoji',
              pinEmoji: '📍',
            ),
          ),
        ),
      );

      expect(find.text('📍'), findsOneWidget);
    });

    testWidgets('handles tap events', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomMapMarker(
              pinColorHex: '#FFFF00',
              pinStyle: 'teardrop',
              pinIconType: 'none',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(CustomMapMarker));
      expect(tapped, isTrue);
    });

    testWidgets('uses semantics label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomMapMarker(
              pinColorHex: '#FF00FF',
              pinStyle: 'circle',
              pinIconType: 'none',
              semanticsLabel: 'Test Marker',
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Test Marker'), findsOneWidget);
    });
  });
}
