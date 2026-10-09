import 'package:flutter/material.dart';

import '../../utils/a11y_constants.dart';
import '../../utils/app_theme.dart';
import 'chromatic_pulse.dart';
import 'glass_inlay.dart';
import 'thermal_response.dart';

/// How much weight an action carries on its surface.
enum ThermalButtonTone {
  /// The one action a surface is for. Solid brand fill.
  primary,

  /// A real action that is not the point of the screen. Inlay body, so it
  /// belongs to the glass family rather than sitting on top of it.
  secondary,

  /// Destructive. Reaches for the thermal core, which is the only place in the
  /// system where heat is a *warning* rather than a response.
  danger,
}

/// The app's action.
///
/// Material's buttons answer a press with an expanding ink circle. This one
/// answers the way everything else in the app does — the surface takes on heat
/// and yields under the finger — and it carries the loading state in the app's
/// own vocabulary instead of parking a spinner inside a label.
///
/// Flat in every tone: DESIGN.md §4 resolves depth by refraction and §6 bans
/// drop shadows, so a raised action is Material's default leaking through
/// rather than a decision this system made.
class ThermalButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ThermalButtonTone tone;

  /// Replaces the label with a Chromatic Pulse and suppresses the tap. The
  /// button keeps its size, so the surface does not reflow mid-action.
  final bool loading;

  /// Fills the available width. A form's submit wants this; a row of two
  /// actions does not.
  final bool expand;

  const ThermalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = ThermalButtonTone.primary,
    this.loading = false,
    this.expand = false,
  });

  bool get _enabled => onPressed != null && !loading;

  Color _fill(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (tone) {
      ThermalButtonTone.primary => scheme.primary,
      ThermalButtonTone.danger => MapPalette.thermalCore,
      ThermalButtonTone.secondary => Colors.transparent,
    };
  }

  Color _ink(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (tone) {
      ThermalButtonTone.primary => scheme.onPrimary,
      ThermalButtonTone.danger => Colors.white,
      ThermalButtonTone.secondary => scheme.onSurface,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    // A disabled control has to read as unavailable without becoming
    // unreadable: 38% is the floor where the label still resolves against
    // either ground.
    final double opacity = _enabled ? 1.0 : 0.38;

    Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null && !loading) ...<Widget>[
          Icon(icon, size: 18, color: ink.withValues(alpha: opacity)),
          const SizedBox(width: MapSpacing.xs),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: ink.withValues(alpha: opacity),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    if (loading) {
      // Sized to the label's line box so the button holds its shape while it
      // waits, rather than collapsing and shoving the layout around.
      content = Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Opacity(opacity: 0.0, child: content),
          SizedBox(
            height: 18,
            width: 18,
            child: ChromaticPulse(
              colors: <Color>[ink, ink.withValues(alpha: 0.45)],
              borderRadius: 9,
            ),
          ),
        ],
      );
    }

    final padding = const EdgeInsets.symmetric(
      horizontal: MapSpacing.md,
      vertical: 14,
    );

    final Widget body = tone == ThermalButtonTone.secondary
        ? GlassInlay(
            padding: padding,
            borderRadius: MapGlass.radiusSm,
            child: content,
          )
        : Container(
            padding: padding,
            decoration: BoxDecoration(
              color: _fill(context).withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(MapGlass.radiusSm),
            ),
            child: content,
          );

    final Widget sized = ConstrainedBox(
      // The 48dp floor is a target size, not a visual one: the control may
      // look smaller than it is, but it may never be smaller than it looks.
      constraints: BoxConstraints(
        minHeight: A11yConstants.minTouchTargetSize,
        minWidth: expand ? double.infinity : A11yConstants.minTouchTargetSize,
      ),
      child: body,
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      child: ExcludeSemantics(
        child: ThermalResponse(
          enabled: _enabled,
          onTap: onPressed,
          borderRadius: MapGlass.radiusSm,
          child: sized,
        ),
      ),
    );
  }
}
