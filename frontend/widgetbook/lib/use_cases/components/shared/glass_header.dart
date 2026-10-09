import 'package:flutter/material.dart';
import 'package:map_my_friends/components/shared/glass_header.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/stage.dart';

@widgetbook.UseCase(
  name: 'Playground',
  type: GlassHeader,
  path: '[Components]/shared',
)
Widget glassHeaderPlayground(BuildContext context) {
  final title = context.knobs.string(label: 'Title', initialValue: 'People');
  final subtitle = context.knobs.stringOrNull(
    label: 'Subtitle',
    initialValue: '6 friends',
  );
  final showBack = context.knobs.boolean(
    label: 'Show back',
    initialValue: false,
  );
  final actionCount = context.knobs.int.slider(
    label: 'Actions',
    initialValue: 2,
    max: 3,
  );

  const actions = <HeaderAction>[
    HeaderAction(icon: Icons.person_add_alt, label: 'Add', onPressed: _noop),
    HeaderAction(icon: Icons.search, label: 'Search', onPressed: _noop),
    HeaderAction(icon: Icons.more_horiz, label: 'More', onPressed: _noop),
  ];

  return Stage(
    alignment: Alignment.topCenter,
    padding: EdgeInsets.zero,
    maxWidth: null,
    child: GlassHeader(
      title: title,
      subtitle: subtitle,
      showBack: showBack,
      actions: actions.take(actionCount).toList(),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Long title',
  type: GlassHeader,
  path: '[Components]/shared',
)
Widget glassHeaderLongTitle(BuildContext context) {
  return const Stage(
    alignment: Alignment.topCenter,
    padding: EdgeInsets.zero,
    maxWidth: null,
    child: GlassHeader(
      title: 'Maximiliane-Josephine von Hohenzollern-Sigmaringen',
      subtitle: 'Garmisch-Partenkirchen, Bavaria, Germany',
      showBack: true,
      actions: [
        HeaderAction(
          icon: Icons.edit_outlined,
          label: 'Edit',
          onPressed: _noop,
        ),
        HeaderAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          onPressed: _noop,
        ),
      ],
    ),
  );
}

void _noop() {}
