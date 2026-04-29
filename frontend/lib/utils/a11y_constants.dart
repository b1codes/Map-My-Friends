import 'package:flutter/material.dart';

class A11yConstants {
  /// Minimum recommended touch target size (48x48 dp) based on Material Design and WCAG guidelines.
  static const double minTouchTargetSize = 48.0;
  static const Size minTouchSize = Size(minTouchTargetSize, minTouchTargetSize);

  /// Standard minimum contrast ratio for normal text (WCAG 2.1 AA)
  static const double minContrastRatio = 4.5;

  /// Standard minimum contrast ratio for large text (WCAG 2.1 AA)
  static const double minContrastRatioLargeText = 3.0;
}
