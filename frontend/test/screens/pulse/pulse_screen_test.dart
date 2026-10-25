import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/pulse/pulse_bloc.dart';
import 'package:map_my_friends/components/pulse/contact_roster_tile.dart';
import 'package:map_my_friends/components/pulse/log_contact_sheet.dart';
import 'package:map_my_friends/components/pulse/pulse_calendar.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/models/contact_log.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/screens/pulse/pulse_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockPulseBloc extends MockBloc<PulseEvent, PulseState>
    implements PulseBloc {}

final _now = DateTime(2026, 7, 22);

Person _person(
  String id,
  String first,
  String last, {
  String tag = 'FRIEND',
  int? daysAgo,
  int? cadence,
}) {
  return Person(
    id: id,
    firstName: first,
    lastName: last,
    relationshipTag: tag,
    city: 'Denver',
    state: 'CO',
    country: 'USA',
    lastContactedAt: daysAgo == null
        ? null
        : _now.subtract(Duration(days: daysAgo)),
    contactCadenceDays: cadence,
  );
}

ContactLog _log(String id, String personId, ContactChannel channel, int ago) {
  return ContactLog(
    id: id,
    personId: personId,
    channel: channel,
    contactedAt: _now.subtract(Duration(days: ago)),
  );
}

/// Same circle as the golden: two fresh friends, two overdue family members,
/// and one friend never contacted.
PulseLoaded _sample({List<ContactLog>? logs}) => PulseLoaded(
  people: [
    _person('1', 'Marco', 'Rossi', daysAgo: 3),
    _person('2', 'Sara', 'Lin', daysAgo: 12),
    _person('3', 'Dev', 'Patel', tag: 'FAMILY', daysAgo: 31),
    _person('4', 'Mom', '', tag: 'FAMILY', daysAgo: 48),
    _person('5', 'Noah', 'Kim'),
  ],
  logs:
      logs ??
      [
        _log('a', '1', ContactChannel.message, 3),
        _log('b', '2', ContactChannel.call, 12),
        _log('c', '3', ContactChannel.video, 12),
      ],
);

void main() {
  late MockPulseBloc bloc;

  setUpAll(() {
    registerFallbackValue(LoadPulse());
  });

  setUp(() {
    bloc = MockPulseBloc();
    whenListen(bloc, const Stream<PulseState>.empty(), initialState: _sample());
  });

  Future<void> pumpPulse(WidgetTester tester) async {
    // Wider than a phone on purpose: GlassToast's message row cannot wrap
    // (see the report on glass_surfaces.dart), so a long confirmation
    // overflows a phone-width snackbar under the test font.
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        // The shell owns the BackdropGroup in production.
        home: BackdropGroup(
          child: BlocProvider<PulseBloc>.value(
            value: bloc,
            child: PulseScreen(now: _now),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  StreamController<PulseState> streamFrom(PulseState initial) {
    final controller = StreamController<PulseState>();
    addTearDown(() => unawaited(controller.close()));
    whenListen(bloc, controller.stream, initialState: initial);
    return controller;
  }

  Finder calendarDay(int day) => find.descendant(
    of: find.byType(PulseCalendar),
    matching: find.text('$day'),
  );

  group('PulseScreen lifecycle', () {
    testWidgets('loads the circle on mount', (tester) async {
      await pumpPulse(tester);

      verify(() => bloc.add(LoadPulse())).called(1);
    });

    for (final state in <PulseState>[PulseInitial(), PulseLoading()]) {
      testWidgets('${state.runtimeType} shows only the pulse', (tester) async {
        whenListen(bloc, const Stream<PulseState>.empty(), initialState: state);
        await pumpPulse(tester);

        expect(find.byType(PulseIndicator), findsOneWidget);
        expect(find.byType(ContactRosterTile), findsNothing);
      });
    }

    testWidgets('PulseError shows the message, and Try again reloads', (
      tester,
    ) async {
      whenListen(
        bloc,
        const Stream<PulseState>.empty(),
        initialState: const PulseError('Server unreachable'),
      );
      await pumpPulse(tester);

      expect(find.text("Couldn't load your circle"), findsOneWidget);
      expect(find.text('Server unreachable'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();

      // Once on mount, once for the retry.
      verify(() => bloc.add(LoadPulse())).called(2);
    });

    testWidgets('an empty circle points the user at the People tab', (
      tester,
    ) async {
      whenListen(
        bloc,
        const Stream<PulseState>.empty(),
        initialState: const PulseLoaded(people: [], logs: []),
      );
      await pumpPulse(tester);

      expect(find.text('No one to keep up with yet'), findsOneWidget);
      expect(find.byType(ContactRosterTile), findsNothing);
    });
  });

  group('PulseScreen roster', () {
    testWidgets('orders people most-overdue first, never-contacted on top', (
      tester,
    ) async {
      await pumpPulse(tester);

      final tiles = tester
          .widgetList<ContactRosterTile>(find.byType(ContactRosterTile))
          .map((t) => t.person.firstName)
          .toList();
      // Noah never; Mom 48/14d; Dev 31/14d; Sara 12/30d; Marco 3/30d.
      expect(tiles, ['Noah', 'Mom', 'Dev', 'Sara', 'Marco']);

      final tops = [
        for (final name in ['Noah Kim', 'Mom', 'Dev Patel', 'Sara Lin'])
          tester.getTopLeft(find.text(name)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
    });

    testWidgets('a custom cadence outranks the tag default', (tester) async {
      whenListen(
        bloc,
        const Stream<PulseState>.empty(),
        initialState: PulseLoaded(
          people: [
            // 10 days on a 30-day default is fine...
            _person('1', 'Ana', 'A', daysAgo: 10),
            // ...but the same 10 days on a 5-day cadence is overdue.
            _person('2', 'Ben', 'B', daysAgo: 10, cadence: 5),
          ],
          logs: [_log('x', '1', ContactChannel.call, 10)],
        ),
      );
      await pumpPulse(tester);

      final tiles = tester
          .widgetList<ContactRosterTile>(find.byType(ContactRosterTile))
          .map((t) => t.person.firstName)
          .toList();
      expect(tiles, ['Ben', 'Ana']);
    });

    testWidgets('the header counts the people who need attention', (
      tester,
    ) async {
      await pumpPulse(tester);

      // Noah (never), Mom and Dev (past 2x their family cadence).
      expect(find.text('3 connections need a hello'), findsOneWidget);
    });

    testWidgets('one overdue person reads in the singular', (tester) async {
      whenListen(
        bloc,
        const Stream<PulseState>.empty(),
        initialState: PulseLoaded(
          people: [
            _person('1', 'Ana', 'A', daysAgo: 1),
            _person('2', 'Ben', 'B', daysAgo: 90),
          ],
          logs: [_log('x', '1', ContactChannel.call, 1)],
        ),
      );
      await pumpPulse(tester);

      expect(find.text('1 connection needs a hello'), findsOneWidget);
    });

    testWidgets('no one overdue reads as caught up', (tester) async {
      whenListen(
        bloc,
        const Stream<PulseState>.empty(),
        initialState: PulseLoaded(
          people: [_person('1', 'Ana', 'A', daysAgo: 1)],
          logs: [_log('x', '1', ContactChannel.call, 1)],
        ),
      );
      await pumpPulse(tester);

      expect(find.text("You're all caught up"), findsOneWidget);
    });

    testWidgets('with no logs yet it invites a first touchpoint', (
      tester,
    ) async {
      whenListen(
        bloc,
        const Stream<PulseState>.empty(),
        initialState: _sample(logs: const []),
      );
      await pumpPulse(tester);

      expect(find.text('Start your first touchpoint'), findsOneWidget);
      expect(find.textContaining('need a hello'), findsNothing);
    });
  });

  group('PulseScreen calendar', () {
    testWidgets('selecting a day lists who was contacted, and tapping it '
        'again clears the selection', (tester) async {
      await pumpPulse(tester);
      expect(find.text('Sara Lin'), findsOneWidget);

      await tester.tap(calendarDay(10));
      await tester.pump();

      expect(find.text('Friday, July 10, 2026'), findsOneWidget);
      // Once in the roster, once as a chip in the day detail.
      expect(find.text('Sara Lin'), findsNWidgets(2));
      expect(find.text('Dev Patel'), findsNWidgets(2));
      expect(find.text('Marco Rossi'), findsOneWidget);

      await tester.tap(calendarDay(10));
      await tester.pump();

      expect(find.text('Friday, July 10, 2026'), findsNothing);
      expect(find.text('Sara Lin'), findsOneWidget);
    });

    testWidgets('a day with no logs says so', (tester) async {
      await pumpPulse(tester);

      await tester.tap(calendarDay(5));
      await tester.pump();

      expect(find.text('Sunday, July 5, 2026'), findsOneWidget);
      expect(find.text('No contact logged this day.'), findsOneWidget);
    });

    testWidgets('a log for someone no longer in the circle reads "Someone"', (
      tester,
    ) async {
      whenListen(
        bloc,
        const Stream<PulseState>.empty(),
        initialState: _sample(
          logs: [_log('gone', 'deleted-person', ContactChannel.call, 2)],
        ),
      );
      await pumpPulse(tester);

      await tester.tap(calendarDay(20));
      await tester.pump();

      expect(find.text('Someone'), findsOneWidget);
    });

    testWidgets('months page back and forward, never past the current one', (
      tester,
    ) async {
      await pumpPulse(tester);
      expect(find.text('July 2026'), findsOneWidget);
      IconButton next() => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right).first,
      );
      expect(find.byTooltip('Next month'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pump();
      expect(find.text('June 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pump();
      expect(find.text('July 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Next month'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('July 2026'), findsOneWidget);
      expect(find.text('August 2026'), findsNothing);
      // Keep the finder honest if the icon ever changes.
      expect(() => next(), returnsNormally);
    });
  });

  group('PulseScreen log contact sheet', () {
    Future<void> openSheetFor(WidgetTester tester, String name) async {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(LogContactSheet), findsOneWidget);
    }

    testWidgets('tapping a person opens the sheet for them', (tester) async {
      await pumpPulse(tester);

      await openSheetFor(tester, 'Marco Rossi');

      expect(find.text('Log contact'), findsOneWidget);
      expect(find.text('with Marco Rossi'), findsOneWidget);
    });

    testWidgets('logging dispatches LogContact for that person, closes the '
        'sheet and confirms', (tester) async {
      await pumpPulse(tester);
      await openSheetFor(tester, 'Marco Rossi');

      await tester.tap(find.text('Video chat'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '  caught up on Rome  ');
      await tester.tap(find.text('Log video chat'));
      await tester.pumpAndSettle();

      final event =
          verify(
                () => bloc.add(captureAny(that: isA<LogContact>())),
              ).captured.single
              as LogContact;
      expect(event.personId, '1');
      expect(event.channel, ContactChannel.video);
      expect(event.note, 'caught up on Rome');
      expect(event.contactedAt, DateUtils.dateOnly(event.contactedAt));

      expect(find.byType(LogContactSheet), findsNothing);
      expect(find.text('Logged video chat with Marco'), findsOneWidget);
    });

    testWidgets('a blank note is sent as null', (tester) async {
      await pumpPulse(tester);
      await openSheetFor(tester, 'Sara Lin');

      await tester.tap(find.text('Log call'));
      await tester.pumpAndSettle();

      final event =
          verify(
                () => bloc.add(captureAny(that: isA<LogContact>())),
              ).captured.single
              as LogContact;
      expect(event.personId, '2');
      expect(event.channel, ContactChannel.call);
      expect(event.note, isNull);
      expect(find.text('Logged call with Sara'), findsOneWidget);
    });

    testWidgets('stepping the cadence dispatches SetCadence each step', (
      tester,
    ) async {
      await pumpPulse(tester);
      // Sara is a friend: the 30-day default.
      await openSheetFor(tester, 'Sara Lin');

      await tester.tap(find.text('Stay in touch every 30 days'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      verify(
        () => bloc.add(const SetCadence(personId: '2', cadenceDays: 37)),
      ).called(1);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      verify(
        () => bloc.add(const SetCadence(personId: '2', cadenceDays: 30)),
      ).called(1);
      verify(
        () => bloc.add(const SetCadence(personId: '2', cadenceDays: 23)),
      ).called(1);
      verifyNever(() => bloc.add(any(that: isA<LogContact>())));
    });

    testWidgets('a family member starts from the 14-day cadence', (
      tester,
    ) async {
      await pumpPulse(tester);
      await openSheetFor(tester, 'Dev Patel');

      expect(find.text('Stay in touch every 14 days'), findsOneWidget);
    });
  });

  group('PulseScreen action errors', () {
    testWidgets('a new nonce with an error toasts once', (tester) async {
      final states = streamFrom(_sample());
      await pumpPulse(tester);

      final failed = _sample();
      states.add(
        PulseLoaded(
          people: failed.people,
          logs: failed.logs,
          actionError: 'Could not save contact. Please try again.',
          actionNonce: 1,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Could not save contact. Please try again.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('a later state carrying the same nonce does not toast again', (
      tester,
    ) async {
      final states = streamFrom(_sample());
      await pumpPulse(tester);
      final base = _sample();

      states.add(
        PulseLoaded(
          people: base.people,
          logs: base.logs,
          actionError: 'Could not update cadence. Please try again.',
          actionNonce: 1,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Could not update cadence'), findsOneWidget);

      ScaffoldMessenger.of(
        tester.element(find.byType(PulseScreen)),
      ).removeCurrentSnackBar();
      await tester.pump();
      expect(find.textContaining('Could not update cadence'), findsNothing);

      // A different list, so it is a genuinely new state, but the same nonce.
      states.add(
        PulseLoaded(
          people: base.people.sublist(1),
          logs: base.logs,
          actionError: 'Could not update cadence. Please try again.',
          actionNonce: 1,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Could not update cadence'), findsNothing);

      // A repeat of the identical failure still notifies: new nonce.
      states.add(
        PulseLoaded(
          people: base.people,
          logs: base.logs,
          actionError: 'Could not update cadence. Please try again.',
          actionNonce: 2,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Could not update cadence'), findsOneWidget);
    });

    testWidgets('a nonce change without an error is silent', (tester) async {
      final states = streamFrom(_sample());
      await pumpPulse(tester);
      final base = _sample();

      states.add(
        PulseLoaded(people: base.people, logs: base.logs, actionNonce: 3),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
