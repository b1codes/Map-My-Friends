import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';
import 'glass_container.dart';
import 'glass_inlay.dart';
import 'thermal_button.dart';
import 'thermal_response.dart';

/// The modal surfaces: sheets, dialogs, and transient messages.
///
/// These were the last places Material was doing the design system's job, and
/// the least defensible ones. A bottom sheet over the live map is the single
/// cheapest refraction in the app — the scene is already there — and it was
/// spending it on `Theme.of(context).cardColor`.
///
/// Every surface here is [GlassContainer.isolated]: each floats *above* other
/// glass, so sharing the chrome's backdrop key would blank the refraction
/// exactly where the two overlap.

/// One choice in a [GlassSheet.actions] sheet.
class SheetAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// A bottom sheet made of glass.
class GlassSheet extends StatelessWidget {
  final Widget child;

  /// Drawn unless the sheet is short enough to read as a card. The handle is
  /// the affordance for dragging, so a sheet that can be dragged keeps it.
  final bool showHandle;

  final EdgeInsetsGeometry padding;

  const GlassSheet({
    super.key,
    required this.child,
    this.showHandle = true,
    this.padding = const EdgeInsets.all(MapSpacing.md),
  });

  /// Presents [builder]'s content as a glass sheet.
  ///
  /// The barrier is deliberately lighter than Material's default: the scene
  /// behind a sheet is what the sheet is made of, and blacking it out to 60%
  /// leaves the glass with nothing to refract at exactly the moment it is
  /// most visible.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool showHandle = true,
    EdgeInsetsGeometry padding = const EdgeInsets.all(MapSpacing.md),
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      isScrollControlled: isScrollControlled,
      builder: (context) => GlassSheet(
        showHandle: showHandle,
        padding: padding,
        child: builder(context),
      ),
    );
  }

  /// Presents a short list of one-tap choices.
  ///
  /// The "take a photo / choose from gallery" shape, which appeared three
  /// times as a stack of Material `ListTile`s. Each row is a thermal surface,
  /// so choosing feels like the rest of the app rather than like a system
  /// menu that wandered in.
  static Future<void> actions(
    BuildContext context, {
    String? title,
    required List<SheetAction> actions,
  }) {
    return show<void>(
      context,
      isScrollControlled: false,
      builder: (context) {
        final theme = Theme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (title != null) ...<Widget>[
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: MapSpacing.sm),
            ],
            for (final action in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: MapSpacing.xs),
                child: ThermalResponse(
                  borderRadius: MapGlass.radiusSm,
                  onTap: () {
                    Navigator.of(context).pop();
                    action.onTap();
                  },
                  child: GlassInlay(
                    borderRadius: MapGlass.radiusSm,
                    padding: const EdgeInsets.symmetric(
                      horizontal: MapSpacing.sm,
                      vertical: 14,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          action.icon,
                          size: 20,
                          color: theme.colorScheme.onSurface,
                        ),
                        const SizedBox(width: MapSpacing.sm),
                        Expanded(
                          child: Text(
                            action.label,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(MapSpacing.xs),
        child: GlassContainer.isolated(
          borderRadius: MapGlass.radiusLg,
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (showHandle) ...<Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MapGlass.inlayEdge(brightness),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: MapSpacing.sm),
              ],
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dialog made of glass.
///
/// One question, at most two answers, and the destructive one is never the
/// default. Material's `AlertDialog` gave both actions the same text-button
/// weight, which is how a delete confirmation ends up looking like a choice
/// between two equal options.
class GlassDialog extends StatelessWidget {
  final String title;
  final String? message;

  /// Arbitrary content, for the dialogs that ask something a sentence cannot —
  /// a colour picker, a set of statuses. Replaces [message] when given.
  final Widget? content;

  /// Omit to present a dialog with nothing to confirm.
  final String? confirmLabel;
  final VoidCallback? onConfirm;

  /// Omit on a dialog the user dismisses rather than declines.
  final String? cancelLabel;
  final ThermalButtonTone tone;

  const GlassDialog({
    super.key,
    required this.title,
    this.confirmLabel,
    this.onConfirm,
    this.message,
    this.content,
    this.cancelLabel = 'Cancel',
    this.tone = ThermalButtonTone.primary,
  });

  /// Presents [content] under [title] with one way out.
  ///
  /// For dialogs that are a surface rather than a question: the choice is made
  /// inside the content, and the button only closes what is already decided.
  static Future<void> panel(
    BuildContext context, {
    required String title,
    required Widget content,
    String dismissLabel = 'Done',
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (context) => GlassDialog(
        title: title,
        content: content,
        cancelLabel: null,
        confirmLabel: dismissLabel,
        onConfirm: () => Navigator.of(context).pop(),
      ),
    );
  }

  /// Asks the question and resolves to whether it was answered yes.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
    ThermalButtonTone tone = ThermalButtonTone.primary,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (context) => GlassDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        tone: tone,
        onConfirm: () => Navigator.of(context).pop(true),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(MapSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassContainer.isolated(
          borderRadius: MapGlass.radiusLg,
          padding: const EdgeInsets.all(MapSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: theme.textTheme.titleLarge),
              if (message != null) ...<Widget>[
                const SizedBox(height: MapSpacing.xs),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
              if (content != null) ...<Widget>[
                const SizedBox(height: MapSpacing.sm),
                // Bounded so a long picker scrolls inside the panel instead of
                // pushing the dialog past the screen.
                Flexible(child: SingleChildScrollView(child: content!)),
              ],
              const SizedBox(height: MapSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (cancelLabel != null) ...<Widget>[
                    ThermalButton(
                      label: cancelLabel!,
                      tone: ThermalButtonTone.secondary,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    const SizedBox(width: MapSpacing.xs),
                  ],
                  if (confirmLabel != null)
                    ThermalButton(
                      label: confirmLabel!,
                      tone: tone,
                      onPressed: onConfirm,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a transient message means.
enum ToastTone {
  /// It happened. No colour beyond the material itself.
  neutral,

  /// It happened and it was the thing the user was trying to do.
  success,

  /// It did not happen.
  failure,
}

/// A transient message made of glass.
///
/// Still routed through [ScaffoldMessenger], which owns queueing, dismissal,
/// and the "one at a time" rule that a hand-rolled overlay would have to
/// reimplement badly. Only the surface changes: transparent Material shell,
/// glass panel inside it, and a single thermal accent bar instead of a tonal
/// fill. The colour lives on a 3px rule rather than the whole panel, so the
/// message stays legible against either appearance.
class GlassToast {
  const GlassToast._();

  static void show(
    BuildContext context,
    String message, {
    ToastTone tone = ToastTone.neutral,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final theme = Theme.of(context);
    final Color accent = switch (tone) {
      ToastTone.neutral => theme.colorScheme.primary,
      ToastTone.success => theme.colorScheme.secondary,
      ToastTone.failure => MapPalette.thermalCore,
    };
    final IconData? leading =
        icon ??
        switch (tone) {
          ToastTone.neutral => null,
          ToastTone.success => Icons.check,
          ToastTone.failure => Icons.error_outline,
        };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.all(MapSpacing.sm),
          duration: const Duration(seconds: 4),
          content: GlassContainer.isolated(
            borderRadius: MapGlass.radiusMd,
            padding: EdgeInsets.zero,
            child: IntrinsicHeight(
              child: Row(
                children: <Widget>[
                  Container(width: 3, color: accent),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MapSpacing.sm,
                      14,
                      MapSpacing.sm,
                      14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (leading != null) ...<Widget>[
                          Icon(leading, size: 18, color: accent),
                          const SizedBox(width: MapSpacing.xs),
                        ],
                        Flexible(
                          child: Text(
                            message,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (actionLabel != null &&
                            onAction != null) ...<Widget>[
                          const SizedBox(width: MapSpacing.sm),
                          // The follow-up offer lives inside the panel and
                          // reads in the accent, so the message stays one
                          // object rather than a notice with a button bolted
                          // to its edge.
                          TextButton(
                            onPressed: () {
                              messenger.hideCurrentSnackBar();
                              onAction();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: accent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: MapSpacing.xs,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              actionLabel,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  /// Reports a failure. Separate entry point because a failure message is the
  /// one a call site most often gets wrong by styling it like a success.
  static void failure(BuildContext context, String message) =>
      show(context, message, tone: ToastTone.failure);

  /// Confirms that something the user asked for happened.
  static void success(BuildContext context, String message) =>
      show(context, message, tone: ToastTone.success);
}
