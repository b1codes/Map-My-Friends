import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/utils/pin_color.dart';

void main() {
  test('reads #RRGGBB, opaque, in either case', () {
    expect(parsePinColor('#2196F3'), const Color(0xFF2196F3));
    expect(parsePinColor('#abcdef'), const Color(0xFFABCDEF));
  });

  test('reads #AARRGGBB as given', () {
    expect(parsePinColor('#802196F3'), const Color(0x802196F3));
  });

  test('anything else is the fallback, not an exception', () {
    for (final hex in ['7', 'red', '#12345', '', '#GGGGGG', null]) {
      expect(parsePinColor(hex), defaultPinColor, reason: '"$hex"');
      expect(
        parsePinColor(hex, fallback: Colors.teal),
        Colors.teal,
        reason: '"$hex"',
      );
    }
  });

  group('pinColorHexOrDefault', () {
    test('keeps a colour the API accepts as it is', () {
      expect(pinColorHexOrDefault('#2196F3', '#F44336'), '#2196F3');
      expect(pinColorHexOrDefault('#abcdef', '#F44336'), '#abcdef');
    });

    test('anything the API would refuse becomes the default', () {
      for (final hex in ['7', 'red', '#12345', '', '#GGGGGG', null]) {
        expect(
          pinColorHexOrDefault(hex, '#F44336'),
          '#F44336',
          reason: '"$hex"',
        );
      }
    });

    test('a readable colour in another shape keeps its RGB', () {
      expect(pinColorHexOrDefault('2196F3', '#F44336'), '#2196F3');
      expect(pinColorHexOrDefault('#802196F3', '#F44336'), '#2196F3');
    });
  });
}
