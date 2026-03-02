import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/shared/image_editor_modal.dart';

void main() {
  testWidgets('ImageEditorModal renders and has save button', (
    WidgetTester tester,
  ) async {
    // Create a 1x1 transparent pixel
    final Uint8List imageBytes = Uint8List.fromList([
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

    await tester.pumpWidget(
      MaterialApp(home: ImageEditorModal(imageBytes: imageBytes)),
    );

    expect(find.text('Edit Image'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    // Tap save (in a real environment this would pop with data,
    // but in test environment creating an image from RepaintBoundary might need more setup or might not return real data easily without golden tests)
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // If no exception, basic structure is sound.
  });
}
