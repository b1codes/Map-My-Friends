import 'package:flutter/painting.dart';

/// The colour a pin falls back to when its own can't be read: the app's
/// default for a new person.
const defaultPinColor = Color(0xFFF44336);

final _hex = RegExp(r'^#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');

/// [hex] as a colour: "#RRGGBB" (opaque) or "#AARRGGBB", or [fallback].
///
/// The colour comes from the API. Parsed with a bare int.parse, a value
/// like "red" threw on every screen drawing that pin, and "7" gave a fully
/// transparent one. The API refuses such colours now, but older records
/// may still hold one.
Color parsePinColor(String? hex, {Color fallback = defaultPinColor}) {
  final match = _hex.firstMatch(hex ?? '');
  if (match == null) return fallback;
  final digits = match.group(1)!;
  return Color(int.parse(digits.length == 6 ? 'FF$digits' : digits, radix: 16));
}
