import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/people/person_card.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:timezone/data/latest.dart' as tzdata;

Person _person({String? timezone}) => Person(
  id: 'p1',
  firstName: 'Ada',
  lastName: 'Lovelace',
  relationshipTag: 'FAMILY',
  city: 'London',
  state: 'England',
  country: 'UK',
  timezone: timezone,
);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  Future<void> pumpCard(
    WidgetTester tester,
    Person person, {
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonCard(person: person, onTap: onTap ?? () {}),
        ),
      ),
    );
  }

  testWidgets('shows the name, place and relationship', (tester) async {
    await pumpCard(tester, _person());

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('London, England'), findsOneWidget);
    expect(find.text('FAMILY'), findsOneWidget);
  });

  testWidgets('shows the local time where the person lives', (tester) async {
    await pumpCard(tester, _person(timezone: 'Asia/Tokyo'));

    expect(find.byIcon(Icons.access_time), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp(r'^\d{1,2}:\d{2}\s[AP]M$').hasMatch(w.data ?? ''),
      ),
      findsOneWidget,
    );
  });

  for (final tz in [null, '', 'Mars/Olympus_Mons']) {
    testWidgets(
      'shows no clock for timezone ${tz == null ? 'null' : '"$tz"'}',
      (tester) async {
        await pumpCard(tester, _person(timezone: tz));

        expect(find.byIcon(Icons.access_time), findsNothing);
        expect(find.text('Ada Lovelace'), findsOneWidget);
      },
    );
  }

  testWidgets('reports taps', (tester) async {
    var taps = 0;
    await pumpCard(tester, _person(), onTap: () => taps++);

    await tester.tap(find.byType(PersonCard));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
