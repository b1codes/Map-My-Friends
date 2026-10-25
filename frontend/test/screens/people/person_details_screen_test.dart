import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_event.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/station/station_event.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/components/map/custom_map_marker.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/components/shared/nearby_airports_section.dart';
import 'package:map_my_friends/components/shared/nearby_blocs.dart';
import 'package:map_my_friends/components/shared/nearby_stations_section.dart';
import 'package:map_my_friends/l10n/app_localizations.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/screens/people/add_edit_person_screen.dart';
import 'package:map_my_friends/screens/people/person_details_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/data/latest.dart' as tzdata;

class MockPeopleBloc extends MockBloc<PeopleEvent, PeopleState>
    implements PeopleBloc {}

class MockTripBloc extends MockBloc<TripEvent, TripState> implements TripBloc {}

class MockMapSettingsCubit extends MockCubit<MapSettingsState>
    implements MapSettingsCubit {}

class MockAirportBloc extends MockBloc<AirportEvent, AirportState>
    implements AirportBloc {}

class MockStationBloc extends MockBloc<StationEvent, StationState>
    implements StationBloc {}

const _urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

final _ann = Person(
  id: 'p1',
  firstName: 'Ann',
  lastName: 'Lee',
  relationshipTag: 'FAMILY',
  city: 'Portland',
  state: 'OR',
  country: 'USA',
  street: '1 Main St',
  phoneNumber: '+15035550100',
  birthday: DateTime(1990, 1, 2),
  latitude: 45.52,
  longitude: -122.68,
  timezone: 'America/Los_Angeles',
  pinColor: '#00FF00',
  pinStyle: 'circle',
  pinIconType: 'initials',
);

/// Someone with only what the form requires.
final _bare = Person(
  id: 'p2',
  firstName: 'Bo',
  lastName: '',
  relationshipTag: 'FRIEND',
  city: '',
  state: '',
  country: '',
);

void main() {
  late MockPeopleBloc peopleBloc;
  late MockTripBloc tripBloc;
  late MockMapSettingsCubit settingsCubit;
  late MockAirportBloc nearbyAirports;
  late MockStationBloc nearbyStations;
  late List<MethodCall> launches;

  setUpAll(() {
    tzdata.initializeTimeZones();
    registerFallbackValue(const DeletePerson(''));
    registerFallbackValue(const ClearTrip());
  });

  setUp(() {
    peopleBloc = MockPeopleBloc();
    tripBloc = MockTripBloc();
    settingsCubit = MockMapSettingsCubit();
    nearbyAirports = MockAirportBloc();
    nearbyStations = MockStationBloc();

    when(() => peopleBloc.state).thenReturn(PeopleLoaded([_ann, _bare]));
    when(() => tripBloc.state).thenReturn(const TripState());
    when(() => settingsCubit.state).thenReturn(const MapSettingsState());
    when(() => nearbyAirports.state).thenReturn(
      NearestAirportsLoaded([
        Airport(
          name: 'Portland International',
          iataCode: 'PDX',
          airportType: 'large_airport',
          city: 'Portland',
          country: 'US',
          latitude: 45.59,
          longitude: -122.6,
          distanceKm: 12,
        ),
      ]),
    );
    when(() => nearbyStations.state).thenReturn(
      NearestStationsLoaded([
        Station(
          name: 'Union Station',
          osmId: 1,
          stationType: 'major_station',
          latitude: 45.53,
          longitude: -122.68,
          distanceKm: 1,
        ),
      ]),
    );

    launches = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, (call) async {
          launches.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, null);
  });

  /// Pushes the details screen over a placeholder home, so a pop is visible.
  Future<void> pumpDetails(WidgetTester tester, String personId) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PeopleBloc>.value(value: peopleBloc),
          BlocProvider<TripBloc>.value(value: tripBloc),
          BlocProvider<MapSettingsCubit>.value(value: settingsCubit),
          RepositoryProvider<NearbyBlocs>.value(
            value: NearbyBlocs(
              airports: nearbyAirports,
              stations: nearbyStations,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PersonDetailsScreen(personId: personId),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
  }

  group('states', () {
    testWidgets('shows a loading placeholder while people are not loaded', (
      tester,
    ) async {
      when(() => peopleBloc.state).thenReturn(PeopleLoading());
      await pumpDetails(tester, 'p1');

      expect(find.text('Person Details'), findsOneWidget);
      expect(find.byType(PulseIndicator), findsOneWidget);
    });

    testWidgets('says so when the person no longer exists', (tester) async {
      await pumpDetails(tester, 'gone');

      expect(find.text('Person Not Found'), findsOneWidget);
      expect(find.text('This person no longer exists.'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsNothing);
    });

    testWidgets('switches to not-found when the person is deleted elsewhere', (
      tester,
    ) async {
      whenListen(
        peopleBloc,
        Stream<PeopleState>.value(PeopleLoaded([_bare])),
        initialState: PeopleLoaded([_ann, _bare]),
      );
      await pumpDetails(tester, 'p1');

      expect(find.text('Person Not Found'), findsOneWidget);
    });
  });

  group('details', () {
    testWidgets('renders everything known about the person', (tester) async {
      await pumpDetails(tester, 'p1');

      // Header title and the profile block both carry the name.
      expect(find.text('Ann Lee'), findsNWidgets(2));
      expect(find.text('FAMILY'), findsNWidgets(2));
      expect(find.textContaining('Local Time: '), findsOneWidget);

      expect(find.text('Location'), findsOneWidget);
      expect(find.text('1 Main St\nPortland, OR USA'), findsOneWidget);
      expect(find.text('Contact & Personal'), findsOneWidget);
      expect(find.text('+15035550100'), findsOneWidget);
      expect(find.text('January 2, 1990'), findsOneWidget);

      final pin = tester.widget<CustomMapMarker>(find.byType(CustomMapMarker));
      expect(pin.pinColorHex, '#00FF00');
      expect(pin.pinStyle, 'circle');
      expect(pin.pinIconType, 'initials');
      expect(pin.initials, 'AL');

      final airports = tester.widget<NearbyAirportsSection>(
        find.byType(NearbyAirportsSection),
      );
      expect((airports.latitude, airports.longitude), (45.52, -122.68));
      expect(find.text('Nearby Airports'), findsOneWidget);
      expect(find.textContaining('PDX'), findsWidgets);
      final stations = tester.widget<NearbyStationsSection>(
        find.byType(NearbyStationsSection),
      );
      expect((stations.latitude, stations.longitude), (45.52, -122.68));
      expect(find.textContaining('Union Station'), findsWidgets);
    });

    testWidgets('shows the profile photo instead of the placeholder', (
      tester,
    ) async {
      const url = 'https://img.test/bo.png';
      await _primeNetworkImage(tester, url);
      when(
        () => peopleBloc.state,
      ).thenReturn(PeopleLoaded([_bare.copyWith(profileImageUrl: url)]));
      await pumpDetails(tester, 'p2');

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, const NetworkImage(url));
      expect(avatar.child, isNull);
      expect(
        tester
            .widget<CustomMapMarker>(find.byType(CustomMapMarker))
            .profileImageUrl,
        url,
      );
    });

    testWidgets('leaves out sections the person has no data for', (
      tester,
    ) async {
      await pumpDetails(tester, 'p2');

      expect(find.text('Location'), findsNothing);
      expect(find.text('Contact & Personal'), findsNothing);
      expect(find.textContaining('Local Time'), findsNothing);
      expect(find.byType(NearbyAirportsSection), findsNothing);
      expect(find.byType(NearbyStationsSection), findsNothing);
      // The pin preview is always there.
      expect(find.text('Map Pin'), findsOneWidget);
      expect(
        tester.widget<CustomMapMarker>(find.byType(CustomMapMarker)).initials,
        'B',
      );
    });

    testWidgets('shows the address with only a city, and only a phone', (
      tester,
    ) async {
      final cityOnly = Person(
        id: 'p3',
        firstName: 'Cy',
        lastName: 'Oh',
        relationshipTag: 'FRIEND',
        city: 'Austin',
        state: '',
        country: '',
        phoneNumber: '555',
        timezone: 'Not/AZone',
      );
      when(() => peopleBloc.state).thenReturn(PeopleLoaded([cityOnly]));
      await pumpDetails(tester, 'p3');

      expect(find.text('Austin,'), findsOneWidget);
      expect(find.text('Phone Number'), findsOneWidget);
      expect(find.text('Birthday'), findsNothing);
      // An unknown zone is ignored rather than crashing the screen.
      expect(find.textContaining('Local Time'), findsNothing);
    });

    testWidgets('shows a birthday without a phone number', (tester) async {
      final birthdayOnly = _bare.copyWith(birthday: DateTime(2000, 12, 31));
      when(() => peopleBloc.state).thenReturn(PeopleLoaded([birthdayOnly]));
      await pumpDetails(tester, 'p2');

      expect(find.text('Contact & Personal'), findsOneWidget);
      expect(find.text('December 31, 2000'), findsOneWidget);
      expect(find.text('Phone Number'), findsNothing);
    });
  });

  group('actions', () {
    testWidgets('tapping the phone number dials it', (tester) async {
      await pumpDetails(tester, 'p1');

      await tester.tap(find.text('+15035550100'));
      await tester.pump();

      expect(launches, hasLength(1));
      expect((launches.single.arguments as Map)['url'], 'tel:+15035550100');
    });

    testWidgets('Add to Trip Planner adds the person as a stop', (
      tester,
    ) async {
      await pumpDetails(tester, 'p1');

      await tester.tap(find.text('Add to Trip Planner'));
      await tester.pump();

      verify(() => tripBloc.add(AddStop(_ann))).called(1);
      expect(find.text('Added Ann to trip'), findsOneWidget);
    });

    testWidgets('Edit opens the form for this person', (tester) async {
      await pumpDetails(tester, 'p2');

      await tester.tap(find.byTooltip('Edit'));
      await _settle(tester);

      final form = tester.widget<AddEditPersonScreen>(
        find.byType(AddEditPersonScreen),
      );
      expect(form.person, same(_bare));
      expect(find.text('Edit Person'), findsOneWidget);
    });

    testWidgets('cancelling the delete confirmation keeps the person', (
      tester,
    ) async {
      await pumpDetails(tester, 'p1');

      await tester.tap(find.byTooltip('Delete'));
      await _settle(tester);
      expect(find.text('Delete Ann?'), findsOneWidget);
      expect(
        find.text(
          'This removes them from your map, your trips, and your contact '
          'history. It cannot be undone.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      verifyNever(() => peopleBloc.add(any()));
      expect(find.byType(PersonDetailsScreen), findsOneWidget);
    });

    testWidgets('confirming the delete removes the person and goes back', (
      tester,
    ) async {
      await pumpDetails(tester, 'p1');

      await tester.tap(find.byTooltip('Delete'));
      await _settle(tester);
      // The dialog's confirm button, not the header action behind it.
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('Delete')),
      );
      await _settle(tester);

      verify(() => peopleBloc.add(const DeletePerson('p1'))).called(1);
      expect(find.byType(PersonDetailsScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Puts a decoded image for [url] in the image cache, so a [NetworkImage] of
/// it resolves without the network.
Future<void> _primeNetworkImage(WidgetTester tester, String url) async {
  final image = await tester.runAsync(() => createTestImage());
  PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(url),
    () => OneFrameImageStreamCompleter(
      SynchronousFuture(ImageInfo(image: image!)),
    ),
  );
  addTearDown(PaintingBinding.instance.imageCache.clear);
}
