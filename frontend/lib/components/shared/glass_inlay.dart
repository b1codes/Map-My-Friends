import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';

/// Glass with the blur removed.
///
/// The GPU budget is per screen, not per widget: a roster of forty rows cannot
/// spend forty backdrop samples, and a form cannot spend one per field. An
/// inlay is the rest of the material — the fill band and the precision edge —
/// applied to something set *into* a surface rather than floating above one.
///
/// The rule is positional, not stylistic. A panel that floats over the
/// [AmbientField] or the map is [GlassContainer]. A row, chip, field, well, or
/// swatch that sits inside such a panel is a [GlassInlay]. Getting this wrong
/// in the other direction is what a Material `Card` was doing here: an opaque
/// tonal step, standing in for depth the design system resolves optically.
class GlassInlay extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;

  /// A deeper well — for a swatch, an avatar backing, or a selected segment,
  /// where the inlay is the thing *behind* content rather than around it.
  final bool strong;

  /// Whether to draw the precision edge. A well inside an already-bounded row
  /// often reads cleaner without one.
  final bool edge;

  const GlassInlay({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MapSpacing.sm),
    this.borderRadius = MapGlass.radiusMd,
    this.width,
    this.height,
    this.alignment,
    this.strong = false,
    this.edge = true,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bool highContrast = MediaQuery.of(context).highContrast;

    return Container(
      width: width,
      height: height,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: highContrast
            ? Theme.of(context).colorScheme.surface
            : (strong
                  ? MapGlass.inlayFillStrong(brightness)
                  : MapGlass.inlayFill(brightness)),
        borderRadius: BorderRadius.circular(borderRadius),
        border: edge
            ? Border.all(
                color: highContrast
                    ? Theme.of(context).dividerColor
                    : MapGlass.inlayEdge(brightness),
                width: highContrast ? 1.0 : MapGlass.edgeWidth,
              )
            : null,
      ),
      child: child,
    );
  }
}
