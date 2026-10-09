import 'package:flutter/material.dart';
import 'package:map_my_friends/components/map/custom_map_marker.dart';
import 'package:map_my_friends/components/map/person_map_marker.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../support/fixtures.dart';
import '../../../support/stage.dart';
import '../../../support/story_scope.dart';

// The string values the API stores; CustomMapMarker switches on them.
const _pinStyles = ['teardrop', 'circle', 'square', 'diamond', 'triangle'];
const _iconTypes = ['none', 'initials', 'emoji', 'picture'];

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

// --- CustomMapMarker ----------------------------------------------------------

@widgetbook.UseCase(
  name: 'Playground',
  type: CustomMapMarker,
  path: '[Components]/map',
)
Widget customMapMarkerPlayground(BuildContext context) {
  final style = context.knobs.object.dropdown(
    label: 'Pin style',
    options: _pinStyles,
  );
  final iconType = context.knobs.object.dropdown(
    label: 'Icon type',
    options: _iconTypes,
    initialOption: 'initials',
  );
  final color = context.knobs.color(
    label: 'Pin colour',
    initialValue: const Color(0xFFF44336),
  );
  final initials = context.knobs.string(label: 'Initials', initialValue: 'MR');
  final emoji = context.knobs.string(label: 'Emoji', initialValue: '🎨');

  return Stage(
    child: Center(
      child: Transform.scale(
        scale: 3,
        child: CustomMapMarker(
          pinColorHex: _hex(color),
          pinStyle: style,
          pinIconType: iconType,
          pinEmoji: emoji,
          initials: initials,
          semanticsLabel: 'Friend marker',
          onTap: () {},
        ),
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Every style',
  type: CustomMapMarker,
  path: '[Components]/map',
)
Widget customMapMarkerMatrix(BuildContext context) {
  final theme = Theme.of(context);
  return Stage(
    maxWidth: 640,
    child: GlassContainer(
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              const SizedBox.shrink(),
              for (final type in _iconTypes)
                Padding(
                  padding: const EdgeInsets.only(bottom: MapSpacing.xs),
                  child: Text(
                    type,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          for (final style in _pinStyles)
            TableRow(
              children: [
                Text(style, style: theme.textTheme.labelSmall),
                for (final type in _iconTypes)
                  Padding(
                    padding: const EdgeInsets.all(MapSpacing.xs),
                    child: Center(
                      child: CustomMapMarker(
                        pinColorHex: '#3F51B5',
                        pinStyle: style,
                        pinIconType: type,
                        pinEmoji: '🏡',
                        initials: 'AR',
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}

// --- PersonMapMarker ----------------------------------------------------------

@widgetbook.UseCase(
  name: 'Sample people (tap one)',
  type: PersonMapMarker,
  path: '[Components]/map',
)
Widget personMapMarkerRoster(BuildContext context) {
  // Tapping opens the same confirm dialog the map does, and "View Details"
  // pushes the real Person details screen.
  return StoryScope(
    child: Stage(
      child: GlassContainer(
        child: Wrap(
          spacing: MapSpacing.md,
          runSpacing: MapSpacing.md,
          alignment: WrapAlignment.center,
          children: [
            for (final Person person in Fixtures.people)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 48,
                    child: Center(child: PersonMapMarker(person: person)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    person.firstName,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
