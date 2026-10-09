import 'package:flutter/material.dart';
import 'package:map_my_friends/components/people/person_card.dart';
import 'package:map_my_friends/components/pulse/contact_roster_tile.dart';
import 'package:map_my_friends/components/pulse/log_contact_sheet.dart';
import 'package:map_my_friends/components/pulse/pulse_calendar.dart';
import 'package:map_my_friends/components/shared/glass_container.dart';
import 'package:map_my_friends/components/shared/glass_surfaces.dart';
import 'package:map_my_friends/components/shared/thermal_button.dart';
import 'package:map_my_friends/models/contact_log.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/utils/app_theme.dart';
import 'package:map_my_friends/utils/contact_recency.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/fixtures.dart';
import '../../support/stage.dart';

Person _personKnob(BuildContext context) => context.knobs.object.dropdown(
  label: 'Person',
  description:
      'Each sample sits at a different point on the recency scale; the last '
      'is the long-name layout stress case.',
  options: Fixtures.people,
  labelBuilder: (p) => '${p.firstName} ${p.lastName}'.trim(),
);

ContactRecency _recencyOf(Person person) =>
    ContactRecency.forPerson(person, now: Fixtures.now);

// --- PersonCard ---------------------------------------------------------------

@widgetbook.UseCase(
  name: 'Default',
  type: PersonCard,
  path: '[Components]/people',
)
Widget personCardDefault(BuildContext context) {
  final person = _personKnob(context);
  return Stage(
    maxWidth: 320,
    child: GlassContainer(
      child: PersonCard(person: person, onTap: () {}),
    ),
  );
}

@widgetbook.UseCase(name: 'Grid', type: PersonCard, path: '[Components]/people')
Widget personCardGrid(BuildContext context) {
  return Stage(
    maxWidth: 720,
    child: GlassContainer(
      child: GridView.extent(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        maxCrossAxisExtent: 220,
        mainAxisSpacing: MapSpacing.sm,
        crossAxisSpacing: MapSpacing.sm,
        childAspectRatio: 1.4,
        children: [
          for (final person in Fixtures.people)
            PersonCard(person: person, onTap: () {}),
        ],
      ),
    ),
  );
}

// --- ContactRosterTile --------------------------------------------------------

@widgetbook.UseCase(
  name: 'Default',
  type: ContactRosterTile,
  path: '[Components]/pulse',
)
Widget contactRosterTileDefault(BuildContext context) {
  final person = _personKnob(context);
  return Stage(
    child: GlassContainer(
      child: ContactRosterTile(
        person: person,
        recency: _recencyOf(person),
        onTap: () {},
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Every recency level',
  type: ContactRosterTile,
  path: '[Components]/pulse',
)
Widget contactRosterTileLevels(BuildContext context) {
  // Ranked the way the Pulse roster ranks them: most overdue first.
  final ranked = [...Fixtures.people]
    ..sort(
      (a, b) =>
          _recencyOf(b).overdueRatio.compareTo(_recencyOf(a).overdueRatio),
    );

  return Stage(
    child: GlassContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final person in ranked)
            ContactRosterTile(
              person: person,
              recency: _recencyOf(person),
              onTap: () {},
            ),
        ],
      ),
    ),
  );
}

// --- LogContactSheet ----------------------------------------------------------

@widgetbook.UseCase(
  name: 'Inline',
  type: LogContactSheet,
  path: '[Components]/pulse',
)
Widget logContactSheetInline(BuildContext context) {
  final person = _personKnob(context);
  return Stage(
    alignment: Alignment.bottomCenter,
    padding: EdgeInsets.zero,
    child: GlassSheet(
      child: LogContactSheet(
        // Keyed so picking another person resets the sheet's own state.
        key: ValueKey(person.id),
        person: person,
        recency: _recencyOf(person),
        onLog: (channel, date, note) {},
        onSetCadence: (days) {},
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'As shown (tap to open)',
  type: LogContactSheet,
  path: '[Components]/pulse',
)
Widget logContactSheetShown(BuildContext context) {
  final person = _personKnob(context);
  return Stage(
    child: Builder(
      builder: (context) => ThermalButton(
        label: 'Log contact with ${person.firstName}',
        icon: Icons.add_comment_outlined,
        onPressed: () => LogContactSheet.show(
          context,
          person: person,
          recency: _recencyOf(person),
          onLog: (channel, date, note) => GlassToast.success(
            context,
            'Logged a ${channel.label.toLowerCase()} with ${person.firstName}',
          ),
          onSetCadence: (days) =>
              GlassToast.show(context, 'Cadence set to every $days days'),
        ),
      ),
    ),
  );
}

// --- PulseCalendar ------------------------------------------------------------

@widgetbook.UseCase(
  name: 'Interactive',
  type: PulseCalendar,
  path: '[Components]/pulse',
)
Widget pulseCalendarInteractive(BuildContext context) {
  final withLogs = context.knobs.boolean(
    label: 'With contact history',
    initialValue: true,
  );
  return Stage(
    child: GlassContainer(
      child: _CalendarHarness(logs: withLogs ? Fixtures.contactLogs : const []),
    ),
  );
}

/// Owns the month and selection the Pulse screen would, so the arrows and
/// day taps work.
class _CalendarHarness extends StatefulWidget {
  const _CalendarHarness({required this.logs});

  final List<ContactLog> logs;

  @override
  State<_CalendarHarness> createState() => _CalendarHarnessState();
}

class _CalendarHarnessState extends State<_CalendarHarness> {
  DateTime _month = DateTime(Fixtures.now.year, Fixtures.now.month);
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final byDay = <DateTime, List<ContactLog>>{};
    for (final log in widget.logs) {
      byDay
          .putIfAbsent(PulseCalendar.dateKey(log.contactedAt), () => [])
          .add(log);
    }

    return PulseCalendar(
      displayedMonth: _month,
      selectedDay: _selected,
      logsByDay: byDay,
      now: Fixtures.now,
      onPreviousMonth: () =>
          setState(() => _month = DateTime(_month.year, _month.month - 1)),
      onNextMonth: () =>
          setState(() => _month = DateTime(_month.year, _month.month + 1)),
      onSelectDay: (day) => setState(
        () => _selected = DateUtils.isSameDay(day, _selected) ? null : day,
      ),
    );
  }
}
