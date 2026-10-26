import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/components/map/custom_map_marker.dart';
import 'package:map_my_friends/components/map/person_map_marker.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/screens/people/person_details_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockPeopleBloc extends MockBloc<PeopleEvent, PeopleState>
    implements PeopleBloc {}

Person _person({
  String firstName = 'Ada',
  String lastName = 'Lovelace',
  String pinIconType = 'initials',
}) => Person(
  id: 'p1',
  firstName: firstName,
  lastName: lastName,
  relationshipTag: 'FRIEND',
  city: 'London',
  state: 'England',
  country: 'UK',
  pinColor: '#2196F3',
  pinStyle: 'circle',
  pinIconType: pinIconType,
  pinEmoji: '🦄',
  profileImageUrl: null,
);

void main() {
  late MockPeopleBloc peopleBloc;

  setUp(() {
    peopleBloc = MockPeopleBloc();
    // An empty roster renders the details screen's static "not found" state,
    // which is enough to prove the navigation landed there.
    when(() => peopleBloc.state).thenReturn(const PeopleLoaded([]));
  });

  Future<void> pumpMarker(
    WidgetTester tester,
    Person person, {
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      BlocProvider<PeopleBloc>.value(
        value: peopleBloc,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: PersonMapMarker(person: person, onTap: onTap),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('passes the person\'s pin and initials to the marker', (
    tester,
  ) async {
    await pumpMarker(tester, _person());

    final marker = tester.widget<CustomMapMarker>(find.byType(CustomMapMarker));
    expect(marker.initials, 'AL');
    expect(marker.pinColorHex, '#2196F3');
    expect(marker.pinStyle, 'circle');
    expect(marker.pinIconType, 'initials');
    expect(marker.pinEmoji, '🦄');
    expect(find.text('AL'), findsOneWidget);
  });

  testWidgets('tolerates empty names when building initials', (tester) async {
    await pumpMarker(tester, _person(firstName: 'Cher', lastName: ''));
    expect(
      tester.widget<CustomMapMarker>(find.byType(CustomMapMarker)).initials,
      'C',
    );

    await pumpMarker(tester, _person(firstName: '', lastName: ''));
    expect(
      tester.widget<CustomMapMarker>(find.byType(CustomMapMarker)).initials,
      '',
    );
  });

  testWidgets('announces itself as the friend it marks', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpMarker(tester, _person());

    // The visible initials merge into the same node after the label.
    expect(
      find.bySemanticsLabel(RegExp(r'^Friend: Ada Lovelace\b')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byType(CustomMapMarker)),
      matchesSemantics(
        label: 'Friend: Ada Lovelace\nAL',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a supplied onTap replaces the default dialog', (tester) async {
    var taps = 0;
    await pumpMarker(tester, _person(), onTap: () => taps++);

    await tester.tap(find.byType(PersonMapMarker));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(find.text('View Details'), findsNothing);
  });

  testWidgets('by default asks before opening the person', (tester) async {
    await pumpMarker(tester, _person());

    await tester.tap(find.byType(PersonMapMarker));
    await tester.pumpAndSettle();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('London, England'), findsOneWidget);
    expect(find.text('View Details'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('closing the dialog stays on the map', (tester) async {
    await pumpMarker(tester, _person());

    await tester.tap(find.byType(PersonMapMarker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('View Details'), findsNothing);
    expect(find.byType(PersonDetailsScreen), findsNothing);
    expect(find.byType(PersonMapMarker), findsOneWidget);
  });

  testWidgets('view details opens that person\'s details', (tester) async {
    await pumpMarker(tester, _person());

    await tester.tap(find.byType(PersonMapMarker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Details'));
    // The details screen paints a drifting field; pump past the route
    // transition rather than waiting for it to settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final screen = tester.widget<PersonDetailsScreen>(
      find.byType(PersonDetailsScreen),
    );
    expect(screen.personId, 'p1');
  });
}
