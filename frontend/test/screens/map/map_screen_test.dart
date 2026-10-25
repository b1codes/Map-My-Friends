import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_event.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_event.dart';
import 'package:map_my_friends/bloc/profile/profile_state.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/station/station_event.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/components/map/custom_map_marker.dart';
import 'package:map_my_friends/components/map/horizontal_trip_planner.dart';
import 'package:map_my_friends/components/map/map_bottom_sheets.dart';
import 'package:map_my_friends/components/map/map_controls.dart';
import 'package:map_my_friends/components/map/unified_cluster_modal.dart';
import 'package:map_my_friends/l10n/app_localizations.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/screens/map/map_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

class MockPeopleBloc extends MockBloc<PeopleEvent, PeopleState>
    implements PeopleBloc {}

class MockMapSettingsCubit extends MockCubit<MapSettingsState>
    implements MapSettingsCubit {}

class MockProfileBloc extends MockBloc<ProfileEvent, ProfileState>
    implements ProfileBloc {}

class MockAirportBloc extends MockBloc<AirportEvent, AirportState>
    implements AirportBloc {}

class MockStationBloc extends MockBloc<StationEvent, StationState>
    implements StationBloc {}

class MockTripBloc extends MockBloc<TripEvent, TripState> implements TripBloc {}

/// The plain pin drawn for the user when their profile has no pin style. The
/// map controls carry a smaller my-location button, so match on size too.
final _defaultUserPin = find.byWidgetPredicate(
  (w) => w is Icon && w.icon == Icons.my_location && w.size == 40,
);

const _fallbackCenter = LatLng(37.7749, -122.4194);

Position _position(double lat, double lon) => Position(
  latitude: lat,
  longitude: lon,
  timestamp: DateTime(2026),
  accuracy: 0,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Person _person(
  String id,
  String first,
  String last, {
  double? lat = 37.7749,
  double? lon = -122.4194,
}) => Person(
  id: id,
  firstName: first,
  lastName: last,
  relationshipTag: 'FRIEND',
  city: 'San Francisco',
  state: 'CA',
  country: 'USA',
  latitude: lat,
  longitude: lon,
);

Airport _airport(
  String iata,
  String type, {
  double lat = 40,
  double lon = -100,
}) => Airport(
  id: iata.hashCode,
  name: '$iata Airport',
  iataCode: iata,
  airportType: type,
  city: 'City',
  country: 'US',
  latitude: lat,
  longitude: lon,
);

Station _station(
  int osmId,
  String name,
  String type, {
  double lat = 45,
  double lon = -90,
}) => Station(
  name: name,
  osmId: osmId,
  stationType: type,
  latitude: lat,
  longitude: lon,
);

void main() {
  late MockLocationBloc locationBloc;
  late MockPeopleBloc peopleBloc;
  late MockMapSettingsCubit settingsCubit;
  late MockProfileBloc profileBloc;
  late MockAirportBloc airportBloc;
  late MockStationBloc stationBloc;
  late MockTripBloc tripBloc;

  setUpAll(() {
    registerFallbackValue(const ClearTrip());
    registerFallbackValue(LoadPeople());
    registerFallbackValue(MapType.standard);
  });

  setUp(() {
    locationBloc = MockLocationBloc();
    peopleBloc = MockPeopleBloc();
    settingsCubit = MockMapSettingsCubit();
    profileBloc = MockProfileBloc();
    airportBloc = MockAirportBloc();
    stationBloc = MockStationBloc();
    tripBloc = MockTripBloc();

    when(() => locationBloc.state).thenReturn(LocationInitial());
    when(() => peopleBloc.state).thenReturn(const PeopleLoaded([]));
    when(() => settingsCubit.state).thenReturn(const MapSettingsState());
    when(() => profileBloc.state).thenReturn(const ProfileLoaded());
    when(() => airportBloc.state).thenReturn(const MapAirportsLoaded([]));
    when(() => stationBloc.state).thenReturn(const MapStationsLoaded([]));
    when(() => tripBloc.state).thenReturn(const TripState());
  });

  Future<void> pumpMap(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
    Locale? locale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LocationBloc>.value(value: locationBloc),
          BlocProvider<PeopleBloc>.value(value: peopleBloc),
          BlocProvider<MapSettingsCubit>.value(value: settingsCubit),
          BlocProvider<ProfileBloc>.value(value: profileBloc),
          BlocProvider<AirportBloc>.value(value: airportBloc),
          BlocProvider<StationBloc>.value(value: stationBloc),
          BlocProvider<TripBloc>.value(value: tripBloc),
        ],
        child: MaterialApp(
          // AppLocalizations has no de/fr; Material's own delegates do, and
          // nothing on screen needs app strings in those tests.
          localizationsDelegates: locale != null
              ? GlobalMaterialLocalizations.delegates
              : AppLocalizations.localizationsDelegates,
          supportedLocales: locale != null
              ? [locale]
              : AppLocalizations.supportedLocales,
          locale: locale,
          home: const MapScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  MapController controller(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

  String tileUrl(WidgetTester tester) =>
      tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate!;

  /// The trip-stop layer is the only plain [MarkerLayer] on the map; the
  /// people/hub markers live in the cluster layer.
  List<Marker> tripStopMarkers(WidgetTester tester) =>
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings));
    await _settle(tester);
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);
  }

  group('location', () {
    testWidgets('shows the locating pill while location is loading', (
      tester,
    ) async {
      when(() => locationBloc.state).thenReturn(LocationLoading());
      await pumpMap(tester);

      expect(find.text('Finding you on the map…'), findsOneWidget);
      // The map is still the canvas while we wait, at the fallback centre.
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(controller(tester).camera.center, _fallbackCenter);
    });

    testWidgets(
      'centres on the user and shows a default pin when the profile has no '
      'pin style',
      (tester) async {
        when(
          () => locationBloc.state,
        ).thenReturn(LocationLoaded(position: _position(51.5, -0.12)));
        await pumpMap(tester);

        expect(find.text('Finding you on the map…'), findsNothing);
        expect(controller(tester).camera.center, const LatLng(51.5, -0.12));
        expect(_defaultUserPin, findsOneWidget);
      },
    );

    testWidgets("uses the profile's custom pin for the user marker", (
      tester,
    ) async {
      when(
        () => locationBloc.state,
      ).thenReturn(LocationLoaded(position: _position(51.5, -0.12)));
      when(() => profileBloc.state).thenReturn(
        const ProfileLoaded(
          firstName: 'jane',
          lastName: 'doe',
          pinColor: '#00FF00',
          pinStyle: 'circle',
          pinIconType: 'initials',
        ),
      );
      await pumpMap(tester);

      expect(_defaultUserPin, findsNothing);
      final pin = tester.widget<CustomMapMarker>(
        find.byWidgetPredicate(
          (w) => w is CustomMapMarker && w.pinColorHex == '#00FF00',
        ),
      );
      expect(pin.pinStyle, 'circle');
      expect(pin.initials, 'jd');
      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('fills in defaults for a profile with only some pin fields', (
      tester,
    ) async {
      when(
        () => locationBloc.state,
      ).thenReturn(LocationLoaded(position: _position(51.5, -0.12)));
      when(
        () => profileBloc.state,
      ).thenReturn(const ProfileLoaded(pinIconType: 'none'));
      await pumpMap(tester);

      final pin = tester.widget<CustomMapMarker>(find.byType(CustomMapMarker));
      expect(pin.pinColorHex, '#3F51B5');
      expect(pin.pinStyle, 'teardrop');
      expect(pin.initials, '');
    });

    for (final entry in <String, LocationState>{
      'denied': LocationPermissionDenied(),
      'denied forever': LocationPermissionDeniedForever(),
      'error': const LocationError('GPS off'),
      'loaded without a fix': const LocationLoaded(),
    }.entries) {
      testWidgets('falls back to the default centre when location is '
          '${entry.key}', (tester) async {
        when(() => locationBloc.state).thenReturn(entry.value);
        await pumpMap(tester);

        expect(controller(tester).camera.center, _fallbackCenter);
        expect(find.text('Finding you on the map…'), findsNothing);
        expect(_defaultUserPin, findsNothing);
      });
    }

    testWidgets('moves the camera when a location fix arrives', (tester) async {
      final states = StreamController<LocationState>();
      addTearDown(states.close);
      whenListen(locationBloc, states.stream, initialState: LocationLoading());
      await pumpMap(tester);
      expect(controller(tester).camera.center, _fallbackCenter);

      states.add(LocationLoaded(position: _position(48.85, 2.35)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller(tester).camera.center, const LatLng(48.85, 2.35));
      expect(controller(tester).camera.zoom, 13.0);
      expect(find.text('Finding you on the map…'), findsNothing);
    });
  });

  group('people markers', () {
    testWidgets('places a marker for each person with coordinates', (
      tester,
    ) async {
      when(() => peopleBloc.state).thenReturn(
        PeopleLoaded([
          _person('1', 'Ann', 'Lee'),
          _person('2', 'Bob', 'Ray', lat: 40.0, lon: -100.0),
          _person('3', 'No', 'Address', lat: null, lon: null),
        ]),
      );
      await pumpMap(tester, size: const Size(1600, 1200));
      // Zoom out so both located people are on screen.
      await _moveCamera(tester, const LatLng(39, -110), 3);

      expect(find.bySemanticsLabel('Friend: Ann Lee'), findsOneWidget);
      expect(find.bySemanticsLabel('Friend: Bob Ray'), findsOneWidget);
      expect(find.bySemanticsLabel('Friend: No Address'), findsNothing);
    });

    testWidgets('shows no people markers while people are not loaded', (
      tester,
    ) async {
      when(() => peopleBloc.state).thenReturn(PeopleLoading());
      await pumpMap(tester);

      expect(find.bySemanticsLabel(RegExp('^Friend: ')), findsNothing);
    });

    testWidgets('adds markers when people finish loading', (tester) async {
      final states = StreamController<PeopleState>();
      addTearDown(states.close);
      whenListen(peopleBloc, states.stream, initialState: PeopleLoading());
      await pumpMap(tester);
      expect(find.bySemanticsLabel('Friend: Ann Lee'), findsNothing);

      states.add(PeopleLoaded([_person('1', 'Ann', 'Lee')]));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.bySemanticsLabel('Friend: Ann Lee'), findsOneWidget);
    });

    testWidgets(
      'tapping a person opens their sheet, and Add as New Stop starts a trip',
      (tester) async {
        final ann = _person('1', 'Ann', 'Lee');
        when(() => peopleBloc.state).thenReturn(PeopleLoaded([ann]));
        await pumpMap(tester);

        await tester.tap(find.bySemanticsLabel('Friend: Ann Lee'));
        await _settle(tester);

        expect(find.byType(UnifiedClusterModal), findsOneWidget);
        expect(find.text('1 Item Here'), findsOneWidget);
        expect(find.text('Ann Lee'), findsOneWidget);

        await tester.tap(find.byTooltip('Add as New Stop'));
        await tester.pump();

        verify(() => tripBloc.add(AddStop(ann))).called(1);
      },
    );
  });

  group('airport and station layers', () {
    // Spread far enough apart that none of them cluster at zoom 4.
    final jfk = _airport('JFK', 'large_airport', lat: 35, lon: -110);
    final hpn = _airport('HPN', 'medium_airport', lat: 35, lon: -90);
    final penn = _station(1, 'Penn Station', 'major_station', lon: -120);
    final metro = _station(
      2,
      'Metro North',
      'commuter_rail_station',
      lon: -110,
    );
    final subway = _station(3, 'Times Sq', 'subway_station', lon: -100);
    final local = _station(4, 'Local Halt', 'regional_station', lon: -90);
    final odd = _station(5, 'Odd Stop', 'something_else', lon: -80);

    setUp(() {
      when(() => airportBloc.state).thenReturn(MapAirportsLoaded([jfk, hpn]));
      when(
        () => stationBloc.state,
      ).thenReturn(MapStationsLoaded([penn, metro, subway, local, odd]));
    });

    Future<void> showHubs(WidgetTester tester) async {
      await _moveCamera(tester, const LatLng(40, -100), 4);
    }

    Finder airportMarker(Airport a) =>
        find.bySemanticsLabel('Airport: ${a.name} (${a.iataCode})');
    Finder stationMarker(Station s) =>
        find.bySemanticsLabel('Station: ${s.name}');

    testWidgets('hides hubs when the settings turn the layers off', (
      tester,
    ) async {
      await pumpMap(tester, size: const Size(2000, 1600));
      await showHubs(tester);

      expect(airportMarker(jfk), findsNothing);
      expect(stationMarker(penn), findsNothing);
    });

    testWidgets('shows every hub, with a distinct icon per station type', (
      tester,
    ) async {
      when(() => settingsCubit.state).thenReturn(
        const MapSettingsState(showAirports: true, showStations: true),
      );
      await pumpMap(tester, size: const Size(2000, 1600));
      await showHubs(tester);

      expect(airportMarker(jfk), findsOneWidget);
      expect(airportMarker(hpn), findsOneWidget);
      for (final s in [penn, metro, subway, local, odd]) {
        expect(stationMarker(s), findsOneWidget, reason: s.name);
      }
      Finder iconIn(Station s, IconData icon) =>
          find.descendant(of: stationMarker(s), matching: find.byIcon(icon));
      expect(iconIn(penn, Icons.train), findsOneWidget);
      expect(iconIn(metro, Icons.directions_railway), findsOneWidget);
      expect(iconIn(subway, Icons.subway), findsOneWidget);
      expect(iconIn(local, Icons.train), findsOneWidget);
      expect(iconIn(odd, Icons.train), findsOneWidget);
    });

    testWidgets('hides hubs whose bloc has not loaded map data', (
      tester,
    ) async {
      when(() => settingsCubit.state).thenReturn(
        const MapSettingsState(showAirports: true, showStations: true),
      );
      when(() => airportBloc.state).thenReturn(AirportInitial());
      when(() => stationBloc.state).thenReturn(StationInitial());
      await pumpMap(tester, size: const Size(2000, 1600));
      await showHubs(tester);

      expect(airportMarker(jfk), findsNothing);
      expect(stationMarker(penn), findsNothing);
    });

    for (final c in <(AirportFilter, bool, bool)>[
      (AirportFilter.international, true, false),
      (AirportFilter.regional, false, true),
    ]) {
      testWidgets('airport filter ${c.$1.name} keeps only matching airports', (
        tester,
      ) async {
        when(
          () => settingsCubit.state,
        ).thenReturn(MapSettingsState(showAirports: true, airportFilter: c.$1));
        await pumpMap(tester, size: const Size(2000, 1600));
        await showHubs(tester);

        expect(airportMarker(jfk), c.$2 ? findsOneWidget : findsNothing);
        expect(airportMarker(hpn), c.$3 ? findsOneWidget : findsNothing);
      });
    }

    for (final c in <(StationFilter, String)>[
      (StationFilter.major, 'Penn Station'),
      (StationFilter.commuter, 'Metro North'),
      (StationFilter.subway, 'Times Sq'),
      (StationFilter.regional, 'Local Halt'),
    ]) {
      testWidgets('station filter ${c.$1.name} keeps only ${c.$2}', (
        tester,
      ) async {
        when(
          () => settingsCubit.state,
        ).thenReturn(MapSettingsState(showStations: true, stationFilter: c.$1));
        await pumpMap(tester, size: const Size(2000, 1600));
        await showHubs(tester);

        final all = [penn, metro, subway, local, odd];
        for (final s in all) {
          expect(
            stationMarker(s),
            s.name == c.$2 ? findsOneWidget : findsNothing,
            reason: s.name,
          );
        }
      });
    }

    testWidgets(
      'toggling layers in the settings sheet shows them for this session only',
      (tester) async {
        await pumpMap(tester, size: const Size(2000, 1600));
        await showHubs(tester);
        expect(airportMarker(jfk), findsNothing);

        await openSettings(tester);
        await tester.tap(find.text('Show Airports'));
        await tester.pump();
        await tester.tap(find.text('Show Train Stations'));
        await tester.pump();
        await closeSheet(tester);

        expect(airportMarker(jfk), findsOneWidget);
        expect(stationMarker(penn), findsOneWidget);
        // The session cubit changed; the persisted settings were not touched.
        verifyNever(() => settingsCubit.toggleAirports());
        verifyNever(() => settingsCubit.toggleStations());
      },
    );

    testWidgets('tapping an airport marker opens its sheet', (tester) async {
      when(
        () => settingsCubit.state,
      ).thenReturn(const MapSettingsState(showAirports: true));
      await pumpMap(tester, size: const Size(2000, 1600));
      await showHubs(tester);

      await tester.tap(airportMarker(jfk));
      await _settle(tester);

      final sheet = tester.widget<AirportBottomSheet>(
        find.byType(AirportBottomSheet),
      );
      expect(sheet.airport, same(jfk));
    });

    testWidgets('tapping a station marker opens its sheet', (tester) async {
      when(
        () => settingsCubit.state,
      ).thenReturn(const MapSettingsState(showStations: true));
      await pumpMap(tester, size: const Size(2000, 1600));
      await showHubs(tester);

      await tester.tap(stationMarker(subway));
      await _settle(tester);

      final sheet = tester.widget<StationBottomSheet>(
        find.byType(StationBottomSheet),
      );
      expect(sheet.station, same(subway));
    });
  });

  group('clusters', () {
    testWidgets('tapping a cluster lists everything in it, and Zoom to Area '
        'fits the camera to it', (tester) async {
      // Close enough to cluster at zoom 5, but not on one point: fitting the
      // camera to a zero-area cluster is a separate, known crash.
      final ann = _person('1', 'Ann', 'Lee', lat: 37.77, lon: -122.42);
      final bob = _person('2', 'Bob', 'Ray', lat: 37.80, lon: -122.27);
      final sfo = _airport('SFO', 'large_airport', lat: 37.62, lon: -122.38);
      final caltrain = _station(
        9,
        'Caltrain',
        'major_station',
        lat: 37.78,
        lon: -122.39,
      );
      when(() => peopleBloc.state).thenReturn(PeopleLoaded([ann, bob]));
      when(() => airportBloc.state).thenReturn(MapAirportsLoaded([sfo]));
      when(() => stationBloc.state).thenReturn(MapStationsLoaded([caltrain]));
      when(() => settingsCubit.state).thenReturn(
        const MapSettingsState(showAirports: true, showStations: true),
      );
      // Tall enough that four rows fit in the sheet without overflowing.
      await pumpMap(tester, size: const Size(1200, 1600));
      await _moveCamera(tester, const LatLng(30, -110), 5);

      // The cluster pill draws its members' pins under an IgnorePointer, so
      // tapping one lands on the cluster itself.
      await tester.tap(
        find.bySemanticsLabel('Friend: Ann Lee'),
        warnIfMissed: false,
      );
      await _settle(tester);

      expect(find.text('4 Items Here'), findsOneWidget);
      expect(find.text('Ann Lee'), findsOneWidget);
      expect(find.text('Bob Ray'), findsOneWidget);
      expect(find.textContaining('SFO'), findsWidgets);
      expect(find.textContaining('Caltrain'), findsWidgets);

      await tester.tap(find.text('Zoom to Area'));
      await _settle(tester);

      expect(find.byType(UnifiedClusterModal), findsNothing);
      // The members span a few km, so fitting to them zooms right in.
      expect(controller(tester).camera.zoom, greaterThan(8));
      expect(
        controller(
          tester,
        ).camera.visibleBounds.contains(const LatLng(37.80, -122.27)),
        isTrue,
      );
    });

    testWidgets('a cluster of more than four shows three avatars and a +N', (
      tester,
    ) async {
      when(() => peopleBloc.state).thenReturn(
        PeopleLoaded([
          for (var i = 0; i < 6; i++) _person('$i', 'P$i', 'Person'),
        ]),
      );
      await pumpMap(tester);

      expect(find.text('+3'), findsOneWidget);
    });
  });

  group('trip planning', () {
    final ann = _person('1', 'Ann', 'Lee');
    final lax = _airport('LAX', 'large_airport', lat: 33.94, lon: -118.40);
    final union = _station(
      7,
      'Union Station',
      'major_station',
      lat: 34.05,
      lon: -118.24,
    );

    TripStop personStop(int order, LatLng at) =>
        TripStop(people: [ann], location: at, sequenceOrder: order);

    testWidgets('without stops there is no planner and no stop markers', (
      tester,
    ) async {
      await pumpMap(tester);

      expect(find.text('Save'), findsNothing);
      expect(tripStopMarkers(tester), isEmpty);
      expect(find.byType(PolylineLayer), findsNothing);
    });

    testWidgets(
      'draws lettered stops, hub icons, people badges and the route',
      (tester) async {
        when(() => tripBloc.state).thenReturn(
          TripState(
            stops: [
              personStop(0, const LatLng(37.77, -122.41)),
              TripStop(
                airport: lax,
                people: [ann, ann],
                location: LatLng(lax.latitude, lax.longitude),
                sequenceOrder: 1,
              ),
              TripStop(
                station: union,
                location: LatLng(union.latitude, union.longitude),
                sequenceOrder: 2,
              ),
              TripStop(location: const LatLng(36, -115), sequenceOrder: 3),
            ],
            routePoints: const [LatLng(37.77, -122.41), LatLng(33.94, -118.40)],
          ),
        );
        await pumpMap(tester);
        // Pull back so every stop is inside the viewport and gets built.
        await _moveCamera(tester, const LatLng(35, -118), 5);

        final markers = tripStopMarkers(tester);
        expect(markers.map((m) => m.point), [
          const LatLng(37.77, -122.41),
          LatLng(lax.latitude, lax.longitude),
          LatLng(union.latitude, union.longitude),
          const LatLng(36, -115),
        ]);
        // Person-only stops are the small pink pins anchored at their corner.
        expect(markers[0].width, 24);
        expect(markers[0].alignment, Alignment.bottomLeft);
        expect(markers[1].width, 30);
        expect(markers[1].alignment, Alignment.center);

        Finder inMarker(int i, Finder f) =>
            find.descendant(of: find.byWidget(markers[i].child), matching: f);
        expect(inMarker(0, find.text('A')), findsOneWidget);
        expect(inMarker(1, find.byIcon(Icons.flight)), findsOneWidget);
        expect(inMarker(1, find.text('2')), findsOneWidget);
        expect(inMarker(2, find.byIcon(Icons.train)), findsOneWidget);
        expect(inMarker(3, find.text('D')), findsOneWidget);

        final route = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
        expect(route.polylines.single.points, const [
          LatLng(37.77, -122.41),
          LatLng(33.94, -118.40),
        ]);
        expect(find.byType(HorizontalTripPlanner), findsOneWidget);
      },
    );

    testWidgets('centres on the first stop when one is added', (tester) async {
      final states = StreamController<TripState>();
      addTearDown(states.close);
      whenListen(tripBloc, states.stream, initialState: const TripState());
      await pumpMap(tester);

      states.add(TripState(stops: [personStop(0, const LatLng(10, 20))]));
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller(tester).camera.center.latitude, closeTo(10, 1e-6));
      expect(controller(tester).camera.center.longitude, closeTo(20, 1e-6));
      expect(controller(tester).camera.zoom, 13.0);
    });

    testWidgets('fits every stop on screen when there are several', (
      tester,
    ) async {
      final states = StreamController<TripState>();
      addTearDown(states.close);
      whenListen(tripBloc, states.stream, initialState: const TripState());
      await pumpMap(tester);

      states.add(
        TripState(
          stops: [
            personStop(0, const LatLng(40, -74)),
            personStop(1, const LatLng(34, -118)),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final bounds = controller(tester).camera.visibleBounds;
      expect(bounds.contains(const LatLng(40, -74)), isTrue);
      expect(bounds.contains(const LatLng(34, -118)), isTrue);
    });

    testWidgets('does not move the camera while the trip is being optimised', (
      tester,
    ) async {
      final states = StreamController<TripState>();
      addTearDown(states.close);
      whenListen(tripBloc, states.stream, initialState: const TripState());
      await pumpMap(tester);

      states.add(
        TripState(
          stops: [personStop(0, const LatLng(10, 20))],
          isOptimizing: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller(tester).camera.center, _fallbackCenter);
    });
  });

  group('tiles and chrome', () {
    for (final c in <(MapSettingsState, String)>[
      (
        const MapSettingsState(),
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      ),
      (
        const MapSettingsState(mapType: MapType.satellite),
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      ),
      (
        const MapSettingsState(mapType: MapType.minimal),
        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
      ),
      (
        const MapSettingsState(
          mapType: MapType.minimal,
          themeMode: ThemeMode.dark,
        ),
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
      ),
      (
        const MapSettingsState(themeMode: ThemeMode.dark),
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
      ),
      (
        const MapSettingsState(themeMode: ThemeMode.light),
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      ),
    ]) {
      testWidgets('uses ${c.$2} for ${c.$1.mapType.name}/'
          '${c.$1.themeMode.name}', (tester) async {
        when(() => settingsCubit.state).thenReturn(c.$1);
        await pumpMap(tester);

        expect(tileUrl(tester), c.$2);
      });
    }

    for (final c in <(Locale, String)>[
      (
        const Locale('de'),
        'https://{s}.tile.openstreetmap.de/tiles/osmde/{z}/{x}/{y}.png',
      ),
      (
        const Locale('fr'),
        'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
      ),
    ]) {
      testWidgets('uses the ${c.$1.languageCode} OSM mirror in that locale', (
        tester,
      ) async {
        await pumpMap(tester, locale: c.$1);

        expect(tileUrl(tester), c.$2);
      });
    }

    testWidgets('switching map type in settings swaps the tiles', (
      tester,
    ) async {
      await pumpMap(tester);

      await openSettings(tester);
      await tester.tap(find.text('STANDARD').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('SATELLITE').last);
      await tester.pump(const Duration(milliseconds: 300));
      await closeSheet(tester);

      expect(tileUrl(tester), contains('World_Imagery'));
      verifyNever(() => settingsCubit.setMapType(any()));
    });

    testWidgets('credits OpenStreetMap, and CartoDB only for Carto tiles, '
        'with links to their terms', (tester) async {
      final launches = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            launches.add((call.arguments as Map)['url'] as String);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      when(
        () => settingsCubit.state,
      ).thenReturn(const MapSettingsState(mapType: MapType.minimal));
      await pumpMap(tester);

      await tester.tap(find.byTooltip('Attributions'));
      await _settle(tester);
      await tester.tap(find.text('© OpenStreetMap contributors'));
      await tester.pump();
      await tester.tap(find.textContaining('CartoDB'));
      await tester.pump();

      expect(launches, [
        'https://openstreetmap.org/copyright',
        'https://carto.com/attributions',
      ]);
    });

    testWidgets('does not credit CartoDB for OpenStreetMap tiles', (
      tester,
    ) async {
      await pumpMap(tester);

      await tester.tap(find.byTooltip('Attributions'));
      await _settle(tester);

      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.textContaining('CartoDB'), findsNothing);
    });

    testWidgets('hides the map controls when the setting is off', (
      tester,
    ) async {
      when(
        () => settingsCubit.state,
      ).thenReturn(const MapSettingsState(showControls: false));
      await pumpMap(tester);

      expect(find.byType(MapControls), findsNothing);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('the compass appears once the map is rotated and resets it '
        'to north', (tester) async {
      await pumpMap(tester);
      expect(find.text('N'), findsNothing);

      controller(tester).rotate(45);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('N'), findsOneWidget);

      await tester.tap(find.text('N'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller(tester).camera.rotation, 0);
      expect(find.text('N'), findsNothing);
    });
  });
}

/// Moves the camera and lets the cluster layer finish its zoom animation; it
/// ignores taps while that runs.
Future<void> _moveCamera(
  WidgetTester tester,
  LatLng center,
  double zoom,
) async {
  tester
      .widget<FlutterMap>(find.byType(FlutterMap))
      .mapController!
      .move(center, zoom);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Runs a route transition to completion. A single long pump only draws the
/// first frame of an animation that starts in it.
///
/// The map listens for double taps, so a single tap on anything inside it is
/// only accepted once the double-tap window has passed.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 600));
}
