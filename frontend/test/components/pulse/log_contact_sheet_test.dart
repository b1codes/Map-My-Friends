import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:map_my_friends/components/pulse/log_contact_sheet.dart';
import 'package:map_my_friends/models/contact_log.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/utils/contact_recency.dart';

Person _person({
  String? phone,
  String tag = 'FRIEND',
  int? cadence,
  String lastName = 'Lovelace',
}) => Person(
  id: 'p1',
  firstName: 'Ada',
  lastName: lastName,
  relationshipTag: tag,
  city: 'London',
  state: 'England',
  country: 'UK',
  phoneNumber: phone,
  contactCadenceDays: cadence,
);

/// One call to [LogContactSheet.onLog].
typedef _Logged = ({ContactChannel channel, DateTime date, String? note});

const _urlLauncher = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  late List<_Logged> logged;
  late List<int> cadences;
  late List<String> launched;

  DateTime today() => DateUtils.dateOnly(DateTime.now());

  setUp(() {
    logged = [];
    cadences = [];
    launched = [];
  });

  Future<void> openSheet(WidgetTester tester, Person person) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => LogContactSheet.show(
                context,
                person: person,
                recency: ContactRecency.forPerson(person),
                onLog: (channel, date, note) =>
                    logged.add((channel: channel, date: date, note: note)),
                onSetCadence: cadences.add,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  void fakeLauncher(WidgetTester tester, {bool fail = false}) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _urlLauncher,
      (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
          if (fail) throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
          return true;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _urlLauncher,
        null,
      ),
    );
  }

  Finder primaryButton(String label) =>
      find.widgetWithText(ElevatedButton, label);

  testWidgets('names who the contact is with', (tester) async {
    await openSheet(tester, _person());

    expect(find.text('Log contact'), findsOneWidget);
    expect(find.text('with Ada Lovelace'), findsOneWidget);
  });

  testWidgets('trims the subtitle when there is no last name', (tester) async {
    await openSheet(tester, _person(lastName: ''));
    expect(find.text('with Ada'), findsOneWidget);
  });

  group('channel', () {
    testWidgets('defaults to a call', (tester) async {
      await openSheet(tester, _person());

      expect(primaryButton('Log call'), findsOneWidget);
    });

    testWidgets('the primary action follows the chosen channel', (
      tester,
    ) async {
      await openSheet(tester, _person());

      await tester.tap(find.text('Video chat'));
      await tester.pump();
      expect(primaryButton('Log video chat'), findsOneWidget);

      await tester.tap(find.text('Message'));
      await tester.pump();
      expect(primaryButton('Log message'), findsOneWidget);
    });

    testWidgets('marks the selected option for assistive technology', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openSheet(tester, _person());

      expect(find.bySemanticsLabel(RegExp(r'^Call, selected')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Message, selected')),
        findsNothing,
      );

      await tester.tap(find.text('Message'));
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp(r'^Message, selected')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Call, selected')), findsNothing);
      semantics.dispose();
    });
  });

  group('submitting', () {
    testWidgets('logs a call today with no note and closes', (tester) async {
      await openSheet(tester, _person());

      await tester.tap(primaryButton('Log call'));
      await tester.pumpAndSettle();

      expect(logged, [
        (channel: ContactChannel.call, date: today(), note: null),
      ]);
      expect(cadences, isEmpty);
      expect(find.byType(LogContactSheet), findsNothing);
    });

    testWidgets('sends the chosen channel, date and trimmed note', (
      tester,
    ) async {
      await openSheet(tester, _person());

      await tester.tap(find.text('Message'));
      await tester.tap(find.text('Yesterday'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Note (optional)'),
        '  Talked about the engine  ',
      );
      await tester.pump();
      await tester.tap(primaryButton('Log message'));
      await tester.pumpAndSettle();

      expect(logged, [
        (
          channel: ContactChannel.message,
          date: today().subtract(const Duration(days: 1)),
          note: 'Talked about the engine',
        ),
      ]);
    });

    testWidgets('a whitespace-only note is sent as no note', (tester) async {
      await openSheet(tester, _person());

      await tester.enterText(
        find.widgetWithText(TextField, 'Note (optional)'),
        '   ',
      );
      await tester.tap(primaryButton('Log call'));
      await tester.pumpAndSettle();

      expect(logged.single.note, isNull);
    });

    testWidgets('dismissing the sheet logs nothing', (tester) async {
      await openSheet(tester, _person());

      await tester.tap(find.text('Video chat'));
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(LogContactSheet), findsNothing);
      expect(logged, isEmpty);
    });
  });

  group('date', () {
    testWidgets('Today is chosen until another day is', (tester) async {
      await openSheet(tester, _person());

      expect(find.text('Pick date…'), findsOneWidget);
      await tester.tap(find.text('Yesterday'));
      await tester.tap(find.text('Today'));
      await tester.tap(primaryButton('Log call'));
      await tester.pumpAndSettle();

      expect(logged.single.date, today());
    });

    testWidgets('a picked date replaces the picker label and is logged', (
      tester,
    ) async {
      await openSheet(tester, _person());

      await tester.tap(find.text('Pick date…'));
      await tester.pumpAndSettle();
      expect(find.text('When did you connect?'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final now = today();
      final picked = DateTime(now.year, now.month - 1, 15);
      expect(find.text(DateFormat.yMMMMd().format(picked)), findsOneWidget);
      expect(find.text('Pick date…'), findsNothing);

      await tester.tap(primaryButton('Log call'));
      await tester.pumpAndSettle();
      expect(logged.single.date, picked);
    });

    testWidgets('cancelling the picker keeps the date', (tester) async {
      await openSheet(tester, _person());

      await tester.tap(find.text('Yesterday'));
      await tester.tap(find.text('Pick date…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Pick date…'), findsOneWidget);
      await tester.tap(primaryButton('Log call'));
      await tester.pumpAndSettle();
      expect(logged.single.date, today().subtract(const Duration(days: 1)));
    });

    testWidgets('the picker offers no future dates', (tester) async {
      await openSheet(tester, _person());

      await tester.tap(find.text('Pick date…'));
      await tester.pumpAndSettle();

      // Opened on today, the last selectable day: paging forward is off.
      final next = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.widgetWithIcon(IconButton, Icons.chevron_right),
        ),
      );
      expect(next.onPressed, isNull);
      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(dialog.lastDate, today());
      expect(dialog.firstDate, DateTime(today().year - 3));
    });
  });

  group('cadence', () {
    Finder stepper(IconData icon) =>
        find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton));

    testWidgets('defaults from the relationship tag', (tester) async {
      await openSheet(tester, _person(tag: 'FAMILY'));
      expect(find.text('Stay in touch every 14 days'), findsOneWidget);
    });

    testWidgets('prefers the person\'s own cadence', (tester) async {
      await openSheet(tester, _person(cadence: 10));
      expect(find.text('Stay in touch every 10 days'), findsOneWidget);
    });

    testWidgets('the stepper is collapsed until asked for', (tester) async {
      await openSheet(tester, _person());

      expect(find.text('30 days'), findsNothing);
      await tester.tap(find.text('Stay in touch every 30 days'));
      await tester.pump();
      expect(find.text('30 days'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);

      await tester.tap(find.text('Stay in touch every 30 days'));
      await tester.pump();
      expect(find.text('30 days'), findsNothing);
    });

    testWidgets('steps a week at a time and reports each change', (
      tester,
    ) async {
      await openSheet(tester, _person());
      await tester.tap(find.text('Stay in touch every 30 days'));
      await tester.pump();

      await tester.tap(stepper(Icons.add));
      await tester.pump();
      expect(find.text('37 days'), findsOneWidget);
      expect(find.text('Stay in touch every 37 days'), findsOneWidget);

      await tester.tap(stepper(Icons.remove));
      await tester.pump();
      await tester.tap(stepper(Icons.remove));
      await tester.pump();
      expect(find.text('23 days'), findsOneWidget);

      expect(cadences, [37, 30, 23]);
      // Changing the cadence is not logging a contact.
      expect(logged, isEmpty);
    });

    testWidgets('clamps at one day and disables going lower', (tester) async {
      await openSheet(tester, _person(cadence: 5));
      await tester.tap(find.text('Stay in touch every 5 days'));
      await tester.pump();

      await tester.tap(stepper(Icons.remove));
      await tester.pump();

      expect(cadences, [1]);
      expect(find.text('1 days'), findsOneWidget);
      expect(
        tester.widget<IconButton>(stepper(Icons.remove)).onPressed,
        isNull,
      );
    });

    testWidgets('clamps at a year and disables going higher', (tester) async {
      await openSheet(tester, _person(cadence: 360));
      await tester.tap(find.text('Stay in touch every 360 days'));
      await tester.pump();

      await tester.tap(stepper(Icons.add));
      await tester.pump();

      expect(cadences, [365]);
      expect(tester.widget<IconButton>(stepper(Icons.add)).onPressed, isNull);
    });
  });

  group('quick launch', () {
    testWidgets('is offered for calls and messages to someone with a phone', (
      tester,
    ) async {
      await openSheet(tester, _person(phone: '+15551234'));

      expect(primaryButton('Call & log'), findsOneWidget);
      expect(find.text('Just log it'), findsOneWidget);

      await tester.tap(find.text('Message'));
      await tester.pump();
      expect(primaryButton('Message & log'), findsOneWidget);

      // There is no video deep link, so video falls back to plain logging.
      await tester.tap(find.text('Video chat'));
      await tester.pump();
      expect(primaryButton('Log video chat'), findsOneWidget);
      expect(find.text('Just log it'), findsNothing);
    });

    testWidgets('is not offered without a phone number', (tester) async {
      await openSheet(tester, _person(phone: ''));

      expect(primaryButton('Call & log'), findsNothing);
      expect(primaryButton('Log call'), findsOneWidget);
    });

    testWidgets('call & log dials the number, then logs', (tester) async {
      fakeLauncher(tester);
      await openSheet(tester, _person(phone: '+15551234'));

      await tester.tap(primaryButton('Call & log'));
      await tester.pumpAndSettle();

      expect(launched, ['tel:+15551234']);
      expect(logged.single.channel, ContactChannel.call);
      expect(find.byType(LogContactSheet), findsNothing);
    });

    testWidgets('message & log opens SMS, then logs', (tester) async {
      fakeLauncher(tester);
      await openSheet(tester, _person(phone: '+15551234'));

      await tester.tap(find.text('Message'));
      await tester.pump();
      await tester.tap(primaryButton('Message & log'));
      await tester.pumpAndSettle();

      expect(launched, ['sms:+15551234']);
      expect(logged.single.channel, ContactChannel.message);
    });

    testWidgets('still logs when no dialer is available', (tester) async {
      fakeLauncher(tester, fail: true);
      await openSheet(tester, _person(phone: '+15551234'));

      await tester.tap(primaryButton('Call & log'));
      await tester.pumpAndSettle();

      expect(launched, ['tel:+15551234']);
      expect(logged, hasLength(1));
      expect(find.byType(LogContactSheet), findsNothing);
    });

    testWidgets('just log it logs without launching anything', (tester) async {
      fakeLauncher(tester);
      await openSheet(tester, _person(phone: '+15551234'));

      await tester.tap(find.text('Just log it'));
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      expect(logged.single.channel, ContactChannel.call);
    });
  });
}
