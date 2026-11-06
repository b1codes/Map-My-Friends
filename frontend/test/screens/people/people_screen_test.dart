import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/components/people/person_card.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/l10n/app_localizations.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/screens/people/add_edit_person_screen.dart';
import 'package:map_my_friends/screens/people/people_screen.dart';
import 'package:map_my_friends/screens/people/person_details_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockPeopleBloc extends MockBloc<PeopleEvent, PeopleState>
    implements PeopleBloc {}

Person _person(String id, String first, String last) => Person(
  id: id,
  firstName: first,
  lastName: last,
  relationshipTag: 'FRIEND',
  city: 'Portland',
  state: 'OR',
  country: 'USA',
);

void main() {
  late MockPeopleBloc peopleBloc;

  setUp(() {
    peopleBloc = MockPeopleBloc();
    when(() => peopleBloc.state).thenReturn(PeopleInitial());
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider<PeopleBloc>.value(
        value: peopleBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The shell provides the backdrop group in the app.
          home: BackdropGroup(child: const PeopleScreen()),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('shows a labelled loading state while people load', (
    tester,
  ) async {
    when(() => peopleBloc.state).thenReturn(PeopleLoading());
    await pumpScreen(tester);

    expect(find.byType(PulseIndicator), findsOneWidget);
    expect(find.text('Loading your people'), findsOneWidget);
    expect(find.byType(PersonCard), findsNothing);
  });

  testWidgets('shows the error message when loading fails', (tester) async {
    when(
      () => peopleBloc.state,
    ).thenReturn(const PeopleError('Server unreachable'));
    await pumpScreen(tester);

    expect(find.text("Couldn't load your people"), findsOneWidget);
    expect(find.text('Server unreachable'), findsOneWidget);
    expect(find.text('Add Your First Friend'), findsNothing);
  });

  testWidgets('before anything loads, shows the empty copy with no action', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('No Friends Added Yet'), findsOneWidget);
    expect(find.text('Add Your First Friend'), findsNothing);
  });

  testWidgets('an empty list offers to add the first friend', (tester) async {
    when(() => peopleBloc.state).thenReturn(const PeopleLoaded([]));
    await pumpScreen(tester);

    expect(find.text('No Friends Added Yet'), findsOneWidget);
    // No count in the header when there is no one to count.
    expect(find.textContaining('people'), findsNothing);

    await tester.tap(find.text('Add Your First Friend'));
    await settle(tester);

    final screen = tester.widget<AddEditPersonScreen>(
      find.byType(AddEditPersonScreen),
    );
    expect(screen.person, isNull);
    expect(find.text('Add Person'), findsOneWidget);
  });

  testWidgets('the header action opens the add-person form', (tester) async {
    when(
      () => peopleBloc.state,
    ).thenReturn(PeopleLoaded([_person('1', 'Ann', 'Lee')]));
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Add person'));
    await settle(tester);

    expect(find.byType(AddEditPersonScreen), findsOneWidget);
  });

  testWidgets('counts one person in the singular', (tester) async {
    when(
      () => peopleBloc.state,
    ).thenReturn(PeopleLoaded([_person('1', 'Ann', 'Lee')]));
    await pumpScreen(tester);

    expect(find.text('1 person'), findsOneWidget);
  });

  testWidgets('lists everyone on a phone and opens the tapped person', (
    tester,
  ) async {
    when(() => peopleBloc.state).thenReturn(
      PeopleLoaded([
        _person('1', 'Ann', 'Lee'),
        _person('2', 'Bob', 'Ray'),
        _person('3', 'Cy', 'Oh'),
      ]),
    );
    await pumpScreen(tester);

    expect(find.text('3 people'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    expect(find.text('Ann Lee'), findsOneWidget);
    expect(find.text('Bob Ray'), findsOneWidget);
    expect(find.text('Cy Oh'), findsOneWidget);

    await tester.tap(find.text('Bob Ray'));
    await settle(tester);

    final details = tester.widget<PersonDetailsScreen>(
      find.byType(PersonDetailsScreen),
    );
    expect(details.personId, '2');
  });

  testWidgets('lays people out in a grid on a wide window', (tester) async {
    when(() => peopleBloc.state).thenReturn(
      PeopleLoaded([_person('1', 'Ann', 'Lee'), _person('2', 'Bob', 'Ray')]),
    );
    await pumpScreen(tester, size: const Size(1400, 900));

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(PersonCard), findsNWidgets(2));

    await tester.tap(find.text('Ann Lee'));
    await settle(tester);

    expect(
      tester
          .widget<PersonDetailsScreen>(find.byType(PersonDetailsScreen))
          .personId,
      '1',
    );
  });

  testWidgets('rebuilds when the bloc emits a new list', (tester) async {
    whenListen(
      peopleBloc,
      Stream<PeopleState>.fromIterable([
        PeopleLoaded([_person('1', 'Ann', 'Lee')]),
      ]),
      initialState: PeopleLoading(),
    );
    await pumpScreen(tester);
    await tester.pump();

    expect(find.text('Loading your people'), findsNothing);
    expect(find.text('Ann Lee'), findsOneWidget);
  });
}
