import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:map_my_friends/main.dart';
import 'package:map_my_friends/utils/app_theme.dart';

class MockLocationBloc extends Mock implements LocationBloc {}

class MockPeopleBloc extends Mock implements PeopleBloc {}

class MockMapSettingsCubit extends Mock implements MapSettingsCubit {}

class MockProfileBloc extends Mock implements ProfileBloc {}

class MockAirportBloc extends Mock implements AirportBloc {}

class MockStationBloc extends Mock implements StationBloc {}

class MockTripBloc extends Mock implements TripBloc {}

/// Device classes this project actually ships to. The pair that matters is
/// phone portrait vs phone landscape: they are the same device, and only one
/// of them is narrow.
const phonePortrait = Size(390, 844);
const phoneLandscape = Size(844, 390);
const smallPhoneLandscape = Size(667, 375);
const tabletPortrait = Size(834, 1112);
const tabletLandscape = Size(1112, 834);

/// The shell ([MainScreen]) over mocked blocs, each settled on an empty,
/// loaded state. Shared by the layout tests and the goldens.
class ShellHarness {
  ShellHarness() {
    when(() => locationBloc.state).thenReturn(const LocationLoaded());
    when(
      () => locationBloc.stream,
    ).thenAnswer((_) => const Stream<LocationState>.empty());
    when(() => locationBloc.close()).thenAnswer((_) => Future.value());

    when(() => peopleBloc.state).thenReturn(const PeopleLoaded([]));
    when(
      () => peopleBloc.stream,
    ).thenAnswer((_) => const Stream<PeopleState>.empty());
    when(() => peopleBloc.close()).thenAnswer((_) => Future.value());

    when(() => mapSettingsCubit.state).thenReturn(const MapSettingsState());
    when(
      () => mapSettingsCubit.stream,
    ).thenAnswer((_) => const Stream<MapSettingsState>.empty());
    when(() => mapSettingsCubit.close()).thenAnswer((_) => Future.value());

    when(
      () => profileBloc.state,
    ).thenReturn(ProfileLoaded(username: 'test', email: 'test@test.com'));
    when(
      () => profileBloc.stream,
    ).thenAnswer((_) => const Stream<ProfileState>.empty());
    when(() => profileBloc.close()).thenAnswer((_) => Future.value());

    when(() => airportBloc.state).thenReturn(const MapAirportsLoaded([]));
    when(
      () => airportBloc.stream,
    ).thenAnswer((_) => const Stream<AirportState>.empty());
    when(() => airportBloc.close()).thenAnswer((_) => Future.value());

    when(() => stationBloc.state).thenReturn(const MapStationsLoaded([]));
    when(
      () => stationBloc.stream,
    ).thenAnswer((_) => const Stream<StationState>.empty());
    when(() => stationBloc.close()).thenAnswer((_) => Future.value());

    when(() => tripBloc.state).thenReturn(const TripState());
    when(
      () => tripBloc.stream,
    ).thenAnswer((_) => const Stream<TripState>.empty());
    when(() => tripBloc.close()).thenAnswer((_) => Future.value());
  }

  /// Call once, from `setUpAll`.
  static void registerFallbacks() {
    registerFallbackValue(LoadLocation());
    registerFallbackValue(LoadPeople());
    registerFallbackValue(LoadProfile());
    registerFallbackValue(LoadMapAirports());
    registerFallbackValue(const MapStationsLoaded([]));
    registerFallbackValue(const ClearTrip());
  }

  final LocationBloc locationBloc = MockLocationBloc();
  final PeopleBloc peopleBloc = MockPeopleBloc();
  final MapSettingsCubit mapSettingsCubit = MockMapSettingsCubit();
  final ProfileBloc profileBloc = MockProfileBloc();
  final AirportBloc airportBloc = MockAirportBloc();
  final StationBloc stationBloc = MockStationBloc();
  final TripBloc tripBloc = MockTripBloc();

  /// Pumps the shell in a [size] window at 1x.
  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: locationBloc),
          BlocProvider.value(value: peopleBloc),
          BlocProvider.value(value: mapSettingsCubit),
          BlocProvider.value(value: profileBloc),
          BlocProvider.value(value: airportBloc),
          BlocProvider.value(value: stationBloc),
          BlocProvider.value(value: tripBloc),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: const MainScreen(),
        ),
      ),
    );
    await tester.pump();
  }
}
