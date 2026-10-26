import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/pulse/contact_roster_tile.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/utils/contact_recency.dart';

Person _person({
  String firstName = 'grace',
  String lastName = 'hopper',
  String? lastContactChannel,
}) => Person(
  id: 'p1',
  firstName: firstName,
  lastName: lastName,
  relationshipTag: 'FRIEND',
  city: 'Arlington',
  state: 'VA',
  country: 'USA',
  lastContactChannel: lastContactChannel,
);

final _now = DateTime(2026, 3, 1);

ContactRecency _recency(int? daysAgo, {int cadence = 30}) =>
    ContactRecency.fromValues(
      lastContactedAt: daysAgo == null
          ? null
          : _now.subtract(Duration(days: daysAgo)),
      cadenceDays: cadence,
      now: _now,
    );

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    Person? person,
    ContactRecency? recency,
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContactRosterTile(
            person: person ?? _person(),
            recency: recency ?? _recency(3),
            onTap: onTap ?? () {},
          ),
        ),
      ),
    );
  }

  /// The status orb's decoration on the avatar.
  BoxDecoration orb(WidgetTester tester) {
    final positioned = find.descendant(
      of: find.byType(ContactRosterTile),
      matching: find.byType(Positioned),
    );
    final container = tester.widget<Container>(
      find.descendant(of: positioned, matching: find.byType(Container)),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('shows the name and uppercased initials', (tester) async {
    await pumpTile(tester);

    expect(find.text('grace hopper'), findsOneWidget);
    expect(find.text('GH'), findsOneWidget);
  });

  testWidgets('falls back to ? when there is no name to abbreviate', (
    tester,
  ) async {
    await pumpTile(
      tester,
      person: _person(firstName: '', lastName: ''),
    );
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('a recent contact reads as in touch', (tester) async {
    await pumpTile(tester, recency: _recency(3));

    expect(find.text('In touch · 3d'), findsOneWidget);
    expect(find.text('Contacted 3 days ago'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    // Not overdue, so the orb does not glow.
    expect(orb(tester).boxShadow, isNull);
    final name = tester.widget<Text>(find.text('grace hopper'));
    expect(name.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('an overdue contact glows and says so', (tester) async {
    await pumpTile(tester, recency: _recency(50));

    expect(find.text('Overdue · 50d'), findsOneWidget);
    expect(find.text('Contacted last month'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(orb(tester).boxShadow, isNotEmpty);
    final name = tester.widget<Text>(find.text('grace hopper'));
    expect(name.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('someone never contacted has no day count', (tester) async {
    await pumpTile(tester, recency: _recency(null));

    expect(find.text('Not yet logged'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
    expect(find.text('No contact logged yet'), findsOneWidget);
    expect(find.byIcon(Icons.waving_hand), findsOneWidget);
    expect(orb(tester).boxShadow, isNotEmpty);
  });

  testWidgets('shows the channel of the last touchpoint when known', (
    tester,
  ) async {
    await pumpTile(tester, person: _person(lastContactChannel: 'VIDEO'));
    expect(find.byIcon(Icons.videocam), findsOneWidget);

    await pumpTile(
      tester,
      person: _person(lastContactChannel: 'CARRIER_PIGEON'),
    );
    expect(find.byIcon(Icons.videocam), findsNothing);
    expect(find.byIcon(Icons.call), findsNothing);
    expect(find.byIcon(Icons.chat_bubble), findsNothing);
  });

  testWidgets('the cadence bar fills with progress, never to nothing', (
    tester,
  ) async {
    double fill() => tester
        .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .widthFactor!;

    await pumpTile(tester, recency: _recency(15));
    expect(fill(), closeTo(0.5, 1e-9));

    await pumpTile(tester, recency: _recency(0));
    expect(fill(), 0.02);

    await pumpTile(tester, recency: _recency(90));
    expect(fill(), 1.0);
  });

  testWidgets('tapping the row opens the log sheet', (tester) async {
    var taps = 0;
    await pumpTile(tester, onTap: () => taps++);

    await tester.tap(find.byType(ContactRosterTile));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
