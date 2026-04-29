import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double? width;
  final double? height;
  final String? semanticLabel;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 16.0,
    this.blur = 10.0,
    this.opacity = 0.4,
    this.padding = const EdgeInsets.all(16.0),
    this.color,
    this.width,
    this.height,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool highContrast = MediaQuery.of(context).highContrast;
    final bool isDark = theme.brightness == Brightness.dark;

    // Hardened contrast for accessibility:
    // In dark mode, ensure slightly higher base opacity to maintain visibility against varied backgrounds.
    final double effectiveOpacity = highContrast
        ? 1.0
        : (isDark ? opacity + 0.15 : opacity).clamp(0.0, 1.0);
    final double effectiveBlur = highContrast ? 0.0 : blur;

    Widget container;

    if (highContrast) {
      container = Container(
        width: width,
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: theme.dividerColor, width: 1.0),
        ),
        child: child,
      );
    } else {
      final baseColor = color ?? theme.colorScheme.surface;
      container = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: effectiveBlur,
            sigmaY: effectiveBlur,
          ),
          child: Container(
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: effectiveOpacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.4),
                width: 2.0,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  baseColor.withValues(
                    alpha: (effectiveOpacity + 0.1).clamp(0.0, 1.0),
                  ),
                  baseColor.withValues(alpha: effectiveOpacity),
                ],
              ),
            ),
            child: child,
          ),
        ),
      );
    }

    if (semanticLabel != null) {
      return Semantics(label: semanticLabel, container: true, child: container);
    }

    return container;
  }
}
