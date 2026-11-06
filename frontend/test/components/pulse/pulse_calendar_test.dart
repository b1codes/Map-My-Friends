import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/pulse/pulse_calendar.dart';
import 'package:map_my_friends/models/contact_log.dart';
import 'package:map_my_friends/utils/contact_recency.dart';

/// Pinned "today": Wednesday 18 March 2026. March 2026 starts on a Sunday.
final _today = DateTime(2026, 3, 18, 15, 30);

ContactLog _log(DateTime day, ContactChannel channel, {String id = '1'}) =>
    ContactLog(id: id, personId: 'p1', channel: channel, contactedAt: day);

void main() {
  late List<String> calls;
  late List<DateTime> selected;

  setUp(() {
    calls = [];
    selected = [];
  });

  Future<void> pumpCalendar(
    WidgetTester tester, {
    DateTime? month,
    DateTime? selectedDay,
    Map<DateTime, List<ContactLog>> logs = const {},
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PulseCalendar(
              displayedMonth: month ?? DateTime(2026, 3),
              selectedDay: selectedDay,
              logsByDay: logs,
              onPreviousMonth: () => calls.add('previous'),
              onNextMonth: () => calls.add('next'),
              onSelectDay: selected.add,
              now: _today,
            ),
          ),
        ),
      ),
    );
  }

  Finder dayCell(String day) =>
      find.ancestor(of: find.text(day), matching: find.byType(InkWell));

  /// The channel markers under a day's number, in order.
  List<Color> markers(WidgetTester tester, String day) => tester
      .widgetList<Container>(
        find.descendant(
          of: dayCell(day),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.constraints ==
                    const BoxConstraints.tightFor(width: 5, height: 5),
          ),
        ),
      )
      .map((c) => (c.decoration! as BoxDecoration).color!)
      .toList();

  BoxDecoration? dayDecoration(WidgetTester tester, String day) {
    final box = tester.widget<Container>(
      find.ancestor(of: find.text(day), matching: find.byType(Container)).first,
    );
    return box.decoration as BoxDecoration?;
  }

  test('dateKey drops the time of day', () {
    expect(
      PulseCalendar.dateKey(DateTime(2026, 3, 5, 23, 59, 59)),
      DateTime(2026, 3, 5),
    );
  });

  testWidgets('titles the displayed month and lays out every day', (
    tester,
  ) async {
    await pumpCalendar(tester);

    expect(find.text('March 2026'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('32'), findsNothing);
    // English weeks start on Sunday, and so does March 2026: no leading blanks.
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate = grid.childrenDelegate as SliverChildListDelegate;
    expect(delegate.children, hasLength(31));
  });

  testWidgets('follows the locale\'s first day of the week', (tester) async {
    await pumpCalendar(tester, locale: const Locale('es'));

    // Spanish weeks start on Monday, so Sunday the 1st sits after six blanks.
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate = grid.childrenDelegate as SliverChildListDelegate;
    expect(delegate.children, hasLength(31 + 6));
    final header = tester.widget<Row>(
      find.ancestor(of: find.text('L'), matching: find.byType(Row)).first,
    );
    final first = (header.children.first as Expanded).child as Center;
    expect((first.child! as Text).data, 'L');
  });

  testWidgets('pages back a month', (tester) async {
    await pumpCalendar(tester);

    await tester.tap(find.byTooltip('Previous month'));
    expect(calls, ['previous']);
  });

  testWidgets('cannot page past the current month', (tester) async {
    await pumpCalendar(tester);

    final next = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      ),
    );
    expect(next.onPressed, isNull);
    await tester.tap(find.byTooltip('Next month'));
    expect(calls, isEmpty);
  });

  testWidgets('pages forward from an earlier month', (tester) async {
    await pumpCalendar(tester, month: DateTime(2026, 2));

    expect(find.text('February 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Next month'));
    expect(calls, ['next']);
  });

  testWidgets('selects a past day as a date-only value', (tester) async {
    await pumpCalendar(tester);

    await tester.tap(find.text('10'));
    await tester.tap(find.text('18'));
    expect(selected, [DateTime(2026, 3, 10), DateTime(2026, 3, 18)]);
  });

  testWidgets('future days cannot be selected', (tester) async {
    await pumpCalendar(tester);

    await tester.tap(find.text('19'));
    await tester.tap(find.text('31'));
    expect(selected, isEmpty);
  });

  testWidgets('every day of a past month is selectable', (tester) async {
    await pumpCalendar(tester, month: DateTime(2026, 2));

    await tester.tap(find.text('28'));
    expect(selected, [DateTime(2026, 2, 28)]);
  });

  testWidgets('rings today and fills the selected day', (tester) async {
    await pumpCalendar(tester, selectedDay: DateTime(2026, 3, 4, 9));
    final primary = Theme.of(
      tester.element(find.text('1')),
    ).colorScheme.primary;

    final today = dayDecoration(tester, '18')!;
    expect(today.color, isNull);
    expect((today.border! as Border).top.color, primary);

    final chosen = dayDecoration(tester, '4')!;
    expect(chosen.color, primary);
    expect(chosen.shape, BoxShape.circle);

    expect(dayDecoration(tester, '5'), isNull);
  });

  testWidgets('marks days with one dot per channel, in channel order', (
    tester,
  ) async {
    final fifth = DateTime(2026, 3, 5);
    final sixth = DateTime(2026, 3, 6);
    await pumpCalendar(
      tester,
      logs: {
        fifth: [
          _log(fifth, ContactChannel.message, id: 'a'),
          _log(fifth, ContactChannel.call, id: 'b'),
          _log(fifth, ContactChannel.message, id: 'c'),
          _log(fifth, ContactChannel.video, id: 'd'),
        ],
        sixth: [_log(sixth, ContactChannel.video)],
      },
    );

    expect(markers(tester, '5'), [
      ContactChannel.call.markerColor,
      ContactChannel.video.markerColor,
      ContactChannel.message.markerColor,
    ]);
    expect(markers(tester, '6'), [ContactChannel.video.markerColor]);
    expect(markers(tester, '7'), isEmpty);
  });

  testWidgets('markers on the selected day switch to the on-primary ink', (
    tester,
  ) async {
    final fifth = DateTime(2026, 3, 5);
    await pumpCalendar(
      tester,
      selectedDay: fifth,
      logs: {
        fifth: [_log(fifth, ContactChannel.call)],
      },
    );
    final onPrimary = Theme.of(
      tester.element(find.text('5')),
    ).colorScheme.onPrimary;

    expect(markers(tester, '5'), [onPrimary]);
  });

  testWidgets('announces how many contacts each day holds', (tester) async {
    final semantics = tester.ensureSemantics();
    final fifth = DateTime(2026, 3, 5);
    final sixth = DateTime(2026, 3, 6);
    await pumpCalendar(
      tester,
      selectedDay: sixth,
      logs: {
        fifth: [
          _log(fifth, ContactChannel.call, id: 'a'),
          _log(fifth, ContactChannel.call, id: 'b'),
        ],
        sixth: [_log(sixth, ContactChannel.video)],
      },
    );

    // Anchored at the start only: the day number's own text currently merges
    // in after the label (reported separately as a duplicate announcement).
    expect(
      find.bySemanticsLabel(RegExp(r'^5, 2 contacts logged')),
      findsOneWidget,
    );
    final sixthNode = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^6, 1 contact logged')),
    );
    final sixthFlags = sixthNode.getSemanticsData();
    expect(sixthFlags.hasAction(SemanticsAction.tap), isTrue);
    expect(sixthFlags.flagsCollection.isButton, isTrue);
    expect(sixthFlags.flagsCollection.isSelected, Tristate.isTrue);
    // A past day without logs is just its number; a future one is not a
    // button.
    final seventh = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^7\b')));
    expect(seventh.getSemanticsData().flagsCollection.isButton, isTrue);
    final future = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^25\b')));
    expect(future.getSemanticsData().flagsCollection.isButton, isFalse);
    expect(future.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });
}
