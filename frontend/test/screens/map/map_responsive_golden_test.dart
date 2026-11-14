// The Map screen's chrome at phone and tablet width. Tiles load from the
// network, which tests can't reach, so the map itself is blank.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_harness/golden_harness.dart';
import 'package:mocktail/mocktail.dart';
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
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/screens/map/map_screen.dart';

class MockLocationBloc extends Mock implements LocationBloc {}

class MockPeopleBloc extends Mock implements PeopleBloc {}

class MockMapSettingsCubit extends Mock implements MapSettingsCubit {}

class MockProfileBloc extends Mock implements ProfileBloc {}

class MockAirportBloc extends Mock implements AirportBloc {}

class MockStationBloc extends Mock implements StationBloc {}

class MockTripBloc extends Mock implements TripBloc {}

void main() {
  setUpGoldens();

  late LocationBloc locationBloc;
  late PeopleBloc peopleBloc;
  late MapSettingsCubit mapSettingsCubit;
  late ProfileBloc profileBloc;
  late AirportBloc airportBloc;
  late StationBloc stationBloc;
  late TripBloc tripBloc;

  setUpAll(() {
    registerFallbackValue(LoadLocation());
    registerFallbackValue(LoadPeople());
    registerFallbackValue(LoadProfile());
    registerFallbackValue(LoadMapAirports());
    registerFallbackValue(const MapStationsLoaded([]));
    registerFallbackValue(const ClearTrip());
  });

  setUp(() {
    locationBloc = MockLocationBloc();
    peopleBloc = MockPeopleBloc();
    mapSettingsCubit = MockMapSettingsCubit();
    profileBloc = MockProfileBloc();
    airportBloc = MockAirportBloc();
    stationBloc = MockStationBloc();
    tripBloc = MockTripBloc();

    when(() => locationBloc.state).thenReturn(const LocationLoaded());
    when(
      () => locationBloc.stream,
    ).thenAnswer((_) => Stream<LocationState>.empty());
    when(() => locationBloc.close()).thenAnswer((_) => Future.value());

    when(() => peopleBloc.state).thenReturn(const PeopleLoaded([]));
    when(
      () => peopleBloc.stream,
    ).thenAnswer((_) => Stream<PeopleState>.empty());
    when(() => peopleBloc.close()).thenAnswer((_) => Future.value());

    when(() => mapSettingsCubit.state).thenReturn(const MapSettingsState());
    when(
      () => mapSettingsCubit.stream,
    ).thenAnswer((_) => Stream<MapSettingsState>.empty());
    when(() => mapSettingsCubit.close()).thenAnswer((_) => Future.value());

    when(
      () => profileBloc.state,
    ).thenReturn(ProfileLoaded(username: 'test', email: 'test@test.com'));
    when(
      () => profileBloc.stream,
    ).thenAnswer((_) => Stream<ProfileState>.empty());
    when(() => profileBloc.close()).thenAnswer((_) => Future.value());

    when(() => airportBloc.state).thenReturn(const MapAirportsLoaded([]));
    when(
      () => airportBloc.stream,
    ).thenAnswer((_) => Stream<AirportState>.empty());
    when(() => airportBloc.close()).thenAnswer((_) => Future.value());

    when(() => stationBloc.state).thenReturn(const MapStationsLoaded([]));
    when(
      () => stationBloc.stream,
    ).thenAnswer((_) => Stream<StationState>.empty());
    when(() => stationBloc.close()).thenAnswer((_) => Future.value());

    when(() => tripBloc.state).thenReturn(const TripState());
    when(() => tripBloc.stream).thenAnswer((_) => Stream<TripState>.empty());
    when(() => tripBloc.close()).thenAnswer((_) => Future.value());
  });

  Widget createWidgetUnderTest() {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: locationBloc),
        BlocProvider.value(value: peopleBloc),
        BlocProvider.value(value: mapSettingsCubit),
        BlocProvider.value(value: profileBloc),
        BlocProvider.value(value: airportBloc),
        BlocProvider.value(value: stationBloc),
        BlocProvider.value(value: tripBloc),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MapScreen(),
      ),
    );
  }

  goldenTest('MapScreen Golden Test - Mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    await expectGolden(
      tester,
      find.byType(MapScreen),
      'goldens/map_screen_mobile.png',
    );
  });

  goldenTest('MapScreen Golden Test - Tablet', (tester) async {
    tester.view.physicalSize = const Size(820, 1180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    await expectGolden(
      tester,
      find.byType(MapScreen),
      'goldens/map_screen_tablet.png',
    );
  });
}
