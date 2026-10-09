import 'package:flutter/material.dart';
import 'package:map_my_friends/components/shared/glass_surfaces.dart';
import 'package:map_my_friends/components/shared/thermal_button.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/stage.dart';

// --- GlassSheet ---------------------------------------------------------------

@widgetbook.UseCase(
  name: 'Inline',
  type: GlassSheet,
  path: '[Components]/shared',
)
Widget glassSheetInline(BuildContext context) {
  final showHandle = context.knobs.boolean(
    label: 'Show handle',
    initialValue: true,
  );
  final theme = Theme.of(context);

  return Stage(
    alignment: Alignment.bottomCenter,
    padding: EdgeInsets.zero,
    child: GlassSheet(
      showHandle: showHandle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sheet title', style: theme.textTheme.titleLarge),
          const SizedBox(height: MapSpacing.xs),
          Text(
            'A sheet is a modal surface, so it samples its own backdrop '
            'rather than sharing the screen\'s.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: MapSpacing.md),
          ThermalButton(
            label: 'Primary action',
            onPressed: () {},
            expand: true,
          ),
        ],
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Action sheet (tap to open)',
  type: GlassSheet,
  path: '[Components]/shared',
)
Widget glassSheetActions(BuildContext context) {
  final title = context.knobs.stringOrNull(
    label: 'Title',
    initialValue: 'Marco Rossi',
  );

  return Stage(
    child: Builder(
      builder: (context) => ThermalButton(
        label: 'Open action sheet',
        icon: Icons.more_horiz,
        onPressed: () => GlassSheet.actions(
          context,
          title: title,
          actions: [
            SheetAction(icon: Icons.call_outlined, label: 'Call', onTap: () {}),
            SheetAction(
              icon: Icons.message_outlined,
              label: 'Message',
              onTap: () {},
            ),
            SheetAction(
              icon: Icons.route_outlined,
              label: 'Add to trip',
              onTap: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

// --- GlassDialog --------------------------------------------------------------

@widgetbook.UseCase(
  name: 'Playground',
  type: GlassDialog,
  path: '[Components]/shared',
)
Widget glassDialogPlayground(BuildContext context) {
  final title = context.knobs.string(
    label: 'Title',
    initialValue: 'Delete Marco?',
  );
  final message = context.knobs.stringOrNull(
    label: 'Message',
    initialValue: 'They will be removed from your map and every trip.',
  );
  final confirmLabel = context.knobs.string(
    label: 'Confirm label',
    initialValue: 'Delete',
  );
  final cancelLabel = context.knobs.stringOrNull(
    label: 'Cancel label',
    initialValue: 'Cancel',
  );
  final tone = context.knobs.object.dropdown(
    label: 'Tone',
    options: ThermalButtonTone.values,
    initialOption: ThermalButtonTone.danger,
    labelBuilder: (t) => t.name,
  );

  // Rendered in place rather than through showDialog, so the knobs above
  // update it live.
  return Stage(
    padding: EdgeInsets.zero,
    child: GlassDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      tone: tone,
      onConfirm: () {},
    ),
  );
}

@widgetbook.UseCase(
  name: 'Confirm (tap to open)',
  type: GlassDialog,
  path: '[Components]/shared',
)
Widget glassDialogConfirm(BuildContext context) {
  return Stage(
    child: Builder(
      builder: (context) => ThermalButton(
        label: 'Delete person',
        icon: Icons.delete_outline,
        tone: ThermalButtonTone.danger,
        onPressed: () async {
          final confirmed = await GlassDialog.confirm(
            context,
            title: 'Delete Marco?',
            message: 'They will be removed from your map and every trip.',
            confirmLabel: 'Delete',
            tone: ThermalButtonTone.danger,
          );
          if (context.mounted) {
            GlassToast.show(context, confirmed ? 'Deleted' : 'Kept');
          }
        },
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Panel (tap to open)',
  type: GlassDialog,
  path: '[Components]/shared',
)
Widget glassDialogPanel(BuildContext context) {
  return Stage(
    child: Builder(
      builder: (context) => ThermalButton(
        label: 'Choose a pin colour',
        icon: Icons.palette_outlined,
        onPressed: () => GlassDialog.panel(
          context,
          title: 'Pin colour',
          content: Wrap(
            spacing: MapSpacing.xs,
            runSpacing: MapSpacing.xs,
            children: [
              for (final color in const [
                Color(0xFF3F51B5),
                Color(0xFFFF4081),
                Color(0xFF4CAF50),
                Color(0xFFFF9800),
                Color(0xFF9C27B0),
              ])
                CircleAvatar(backgroundColor: color, radius: 20),
            ],
          ),
        ),
      ),
    ),
  );
}

// --- GlassToast ---------------------------------------------------------------

@widgetbook.UseCase(
  name: 'Tones (tap to show)',
  type: GlassToast,
  path: '[Components]/shared',
)
Widget glassToastTones(BuildContext context) {
  final message = context.knobs.string(
    label: 'Message',
    initialValue: 'Marco was added to your trip',
  );
  final withAction = context.knobs.boolean(
    label: 'With action',
    initialValue: false,
  );

  // A Scaffold of its own, so the snack bar appears inside the selected
  // device frame instead of at the bottom of the Widgetbook window.
  return Stage.route(
    child: ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stage(
          child: Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final tone in ToastTone.values) ...[
                  ThermalButton(
                    label: 'Show ${tone.name}',
                    tone: ThermalButtonTone.secondary,
                    onPressed: () => GlassToast.show(
                      context,
                      message,
                      tone: tone,
                      actionLabel: withAction ? 'Undo' : null,
                      onAction: withAction ? () {} : null,
                    ),
                  ),
                  const SizedBox(height: MapSpacing.xs),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
