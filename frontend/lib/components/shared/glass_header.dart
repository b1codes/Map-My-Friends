import 'package:flutter/material.dart';

import '../../utils/a11y_constants.dart';
import '../../utils/app_theme.dart';
import 'glass_container.dart';
import 'thermal_response.dart';

/// One action in a [GlassHeader].
class HeaderAction {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const HeaderAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
}

/// The top of a surface.
///
/// The shell deliberately has no app bar — it is one glass world with floating
/// chrome — and then nine screens each mounted a Material `AppBar` inside it,
/// so the app carried two navigation chromes with different materials, type,
/// and interaction feedback.
///
/// This is the one header: a glass bar carrying the surface's name, its back
/// affordance when it has one, and its actions as thermal targets. It is laid
/// above the body rather than floating over it, so nothing has to guess at the
/// content inset, and it refracts the Ambient Field like every other panel.
class GlassHeader extends StatelessWidget {
  final String title;

  /// A second line, for surfaces where the title alone does not say what the
  /// screen is holding.
  final String? subtitle;

  final List<HeaderAction> actions;

  /// Shown when the surface was pushed onto the navigator. Defaults to
  /// whether there is anything to pop.
  final bool? showBack;

  const GlassHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <HeaderAction>[],
    this.showBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool back = showBack ?? Navigator.of(context).canPop();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        MapSpacing.sm,
        MediaQuery.of(context).padding.top + MapSpacing.xs,
        MapSpacing.sm,
        MapSpacing.xs,
      ),
      child: GlassContainer(
        borderRadius: MapGlass.radiusLg,
        padding: const EdgeInsets.symmetric(
          horizontal: MapSpacing.xs,
          vertical: MapSpacing.xs,
        ),
        child: Row(
          children: <Widget>[
            if (back)
              _HeaderButton(
                icon: Icons.adaptive.arrow_back,
                label: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            else
              const SizedBox(width: MapSpacing.xs),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: MapSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            for (final action in actions)
              _HeaderButton(
                icon: action.icon,
                label: action.label,
                onPressed: action.onPressed,
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: ThermalResponse(
          onTap: onPressed,
          borderRadius: MapGlass.radiusMd,
          child: SizedBox(
            width: A11yConstants.minTouchTargetSize,
            height: A11yConstants.minTouchTargetSize,
            child: Icon(
              icon,
              size: 22,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
