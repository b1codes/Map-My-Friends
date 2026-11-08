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
}
