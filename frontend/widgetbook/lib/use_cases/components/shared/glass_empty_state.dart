import 'package:flutter/material.dart';
import 'package:map_my_friends/components/shared/glass_empty_state.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/stage.dart';

@widgetbook.UseCase(
  name: 'Playground',
  type: GlassEmptyState,
  path: '[Components]/shared',
)
Widget glassEmptyStatePlayground(BuildContext context) {
  final title = context.knobs.string(
    label: 'Title',
    initialValue: 'No one here yet',
  );
  final message = context.knobs.string(
    label: 'Message',
    initialValue:
        'Add the people you care about and they will appear on your map.',
  );
  final withAction = context.knobs.boolean(
    label: 'With action',
    description:
        'An action needs both a label and a callback; the widget asserts on '
        'one without the other.',
    initialValue: true,
  );
  final actionLabel = context.knobs.string(
    label: 'Action label',
    initialValue: 'Add a person',
  );

  return Stage(
    child: GlassEmptyState(
      icon: Icons.people_outline,
      title: title,
      message: message,
      actionLabel: withAction ? actionLabel : null,
      actionIcon: withAction ? Icons.person_add_alt : null,
      onAction: withAction ? () {} : null,
    ),
  );
}

@widgetbook.UseCase(
  name: 'Error',
  type: GlassEmptyState,
  path: '[Components]/shared',
)
Widget glassEmptyStateError(BuildContext context) {
  return Stage(
    child: GlassEmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Could not load your people',
      message: 'Check your connection and try again.',
      actionLabel: 'Retry',
      actionIcon: Icons.refresh,
      onAction: () {},
    ),
  );
}
