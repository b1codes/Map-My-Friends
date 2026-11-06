import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/image_editor_modal.dart';

Uint8List _pixel() => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  testWidgets('ImageEditorModal renders and has save button', (
    WidgetTester tester,
  ) async {
    // Create a 1x1 transparent pixel
    final Uint8List imageBytes = _pixel();

    await tester.pumpWidget(
      MaterialApp(home: ImageEditorModal(imageBytes: imageBytes)),
    );

    expect(find.text('Edit Image'), findsOneWidget);
    // The save affordance is a thermal header action now, labelled rather
    // than spelled out: the header carries icons, not text buttons.
    expect(find.byTooltip('Save'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    // Tap save (in a real environment this would pop with data,
    // but in test environment creating an image from RepaintBoundary might need more setup or might not return real data easily without golden tests)
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    // If no exception, basic structure is sound.
  });

  testWidgets('saving returns the framed crop as PNG bytes', (tester) async {
    Uint8List? result;
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<Uint8List>(
                MaterialPageRoute(
                  builder: (_) => ImageEditorModal(imageBytes: _pixel()),
                ),
              );
              returned = true;
            },
            child: const Text('edit'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();

    // Rasterising the boundary is real async work, outside fake time.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Save'));
      for (var i = 0; i < 50 && !returned; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(find.byType(ImageEditorModal), findsNothing);
    // The crop comes back PNG-encoded.
    expect(result, isNotNull);
    expect(result!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('frames a circle for avatars and a square otherwise', (
    tester,
  ) async {
    BoxShape frame() {
      final overlay = tester.widget<Container>(
        find.descendant(
          of: find.byType(IgnorePointer).last,
          matching: find.byType(Container),
        ),
      );
      return (overlay.decoration! as BoxDecoration).shape;
    }

    await tester.pumpWidget(
      MaterialApp(home: ImageEditorModal(imageBytes: _pixel())),
    );
    expect(frame(), BoxShape.circle);

    await tester.pumpWidget(
      MaterialApp(
        home: ImageEditorModal(imageBytes: _pixel(), isCircular: false),
      ),
    );
    expect(frame(), BoxShape.rectangle);
    expect(find.text('Pinch to zoom, drag to move'), findsOneWidget);
  });
}
