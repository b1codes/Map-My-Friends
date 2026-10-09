import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';
import 'glass_container.dart';
import 'thermal_button.dart';

/// The empty state for a primary surface: a single glass panel carrying an
/// icon, a headline, a line of guidance, and optionally the one action that
/// resolves the emptiness.
///
/// Three screens grew their own copy of this — People, Trips, and Pulse — and
/// they had already drifted apart: two wrote raw `TextStyle(fontSize: 20)` for
/// the headline, bypassing the Montserrat display voice DESIGN.md §3 asks for,
/// while the third used a body style two steps too small. One of them centred
/// its title and the others did not. Consolidating them fixes all of that at
/// once and makes the next empty state correct by construction.
///
/// The action is modelled as label + callback rather than a `Widget` slot on
/// purpose: a slot would let each caller re-style its own button, which is
/// exactly how the three implementations diverged the first time.
class GlassEmptyState extends StatelessWidget {
  /// Drawn at low opacity — it sets the subject, it is not the message.
  final IconData icon;

  /// One line, sentence case, naming what is absent.
  final String title;

  /// What the person can do about it, in the product's own voice.
  final String message;

  /// Label for the single resolving action. Requires [onAction].
  final String? actionLabel;

  /// Invoked by the action. Requires [actionLabel].
  final VoidCallback? onAction;

  /// Optional leading icon for the action.
  final IconData? actionIcon;

  const GlassEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'An empty-state action needs both a label and a callback: a labelled '
         'button that does nothing is worse than no button.',
       );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Center(
      child: SingleChildScrollView(
        // An empty state is the one screen guaranteed to be seen on a first
        // run, including by someone running large text on a small phone. The
        // panel is generous by design, so it has to be allowed to scroll
        // rather than overflow.
        padding: const EdgeInsets.symmetric(
          horizontal: MapSpacing.md,
          vertical: MapSpacing.md,
        ),
        child: GlassContainer(
          padding: const EdgeInsets.all(MapSpacing.panel),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: onSurface.withValues(alpha: 0.2)),
              const SizedBox(height: MapSpacing.md),
              Text(
                title,
                // Montserrat, per DESIGN.md §3: display-level hierarchy is the
                // industrial voice, and an empty state's headline is display.
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: MapSpacing.xs),
              Text(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: MapSpacing.lg),
                _EmptyStateAction(
                  label: actionLabel!,
                  icon: actionIcon,
                  onPressed: onAction!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The single filled action an empty state may carry.
///
/// Kept as a private wrapper rather than inlined at the call site so every
/// empty state's CTA is the same weight and the same material.
class _EmptyStateAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  const _EmptyStateAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ThermalButton(label: label, icon: icon, onPressed: onPressed);
  }
}
