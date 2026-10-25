import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_event.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/auth/auth_bloc.dart';
import 'package:map_my_friends/bloc/auth/auth_event.dart';
import 'package:map_my_friends/bloc/auth/auth_state.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_event.dart';
import 'package:map_my_friends/bloc/profile/profile_state.dart';
import 'package:map_my_friends/bloc/pulse/pulse_bloc.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/station/station_event.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/bloc/theme/theme_cubit.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/l10n/app_localizations.dart';
import 'package:map_my_friends/main.dart';
import 'package:map_my_friends/screens/auth/login_screen.dart';
import 'package:map_my_friends/screens/map/map_screen.dart';
import 'package:map_my_friends/screens/people/people_screen.dart';
import 'package:map_my_friends/screens/profile/me_screen.dart';
import 'package:map_my_friends/screens/pulse/pulse_screen.dart';
import 'package:map_my_friends/screens/trips/trips_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

class MockPeopleBloc extends MockBloc<PeopleEvent, PeopleState>
    implements PeopleBloc {}

class MockPulseBloc extends MockBloc<PulseEvent, PulseState>
    implements PulseBloc {}

class MockProfileBloc extends MockBloc<ProfileEvent, ProfileState>
    implements ProfileBloc {}

class MockThemeCubit extends MockCubit<ThemeMode> implements ThemeCubit {}

class MockMapSettingsCubit extends MockCubit<MapSettingsState>
    implements MapSettingsCubit {}

class MockAirportBloc extends MockBloc<AirportEvent, AirportState>
    implements AirportBloc {}

class MockStationBloc extends MockBloc<StationEvent, StationState>
    implements StationBloc {}

class MockTripBloc extends MockBloc<TripEvent, TripState> implements TripBloc {}

const _phone = Size(390, 844);
const _tablet = Size(1112, 834);

void main() {
  late MockAuthBloc authBloc;
  late MockLocationBloc locationBloc;
  late MockPeopleBloc peopleBloc;
  late MockPulseBloc pulseBloc;
  late MockProfileBloc profileBloc;
  late MockThemeCubit themeCubit;
  late MockMapSettingsCubit mapSettings;
  late MockAirportBloc airportBloc;
  late MockStationBloc stationBloc;
  late MockTripBloc tripBloc;

  setUpAll(() {
    registerFallbackValue(LoadProfile());
    registerFallbackValue(DistanceUnit.metric);
  });

  setUp(() {
    authBloc = MockAuthBloc();
    locationBloc = MockLocationBloc();
    peopleBloc = MockPeopleBloc();
    pulseBloc = MockPulseBloc();
    profileBloc = MockProfileBloc();
    themeCubit = MockThemeCubit();
    mapSettings = MockMapSettingsCubit();
    airportBloc = MockAirportBloc();
    stationBloc = MockStationBloc();
    tripBloc = MockTripBloc();

    whenListen(
      authBloc,
      const Stream<AuthState>.empty(),
      initialState: const Authenticated(accessToken: 'a', refreshToken: 'r'),
    );
    whenListen(
      locationBloc,
      const Stream<LocationState>.empty(),
      initialState: const LocationLoaded(),
    );
    whenListen(
      peopleBloc,
      const Stream<PeopleState>.empty(),
      initialState: const PeopleLoaded([]),
    );
    whenListen(
      pulseBloc,
      const Stream<PulseState>.empty(),
      initialState: const PulseLoaded(people: [], logs: []),
    );
    whenListen(
      profileBloc,
      const Stream<ProfileState>.empty(),
      initialState: const ProfileLoaded(username: 'ada'),
    );
    whenListen(
      themeCubit,
      const Stream<ThemeMode>.empty(),
      initialState: ThemeMode.system,
    );
    whenListen(
      mapSettings,
      const Stream<MapSettingsState>.empty(),
      initialState: const MapSettingsState(),
    );
    whenListen(
      airportBloc,
      const Stream<AirportState>.empty(),
      initialState: const MapAirportsLoaded([]),
    );
    whenListen(
      stationBloc,
      const Stream<StationState>.empty(),
      initialState: const MapStationsLoaded([]),
    );
    whenListen(
      tripBloc,
      const Stream<TripState>.empty(),
      initialState: const TripState(),
    );
  });

  /// Everything [MyApp] provides, as mocks, around [home].
  Future<void> pumpUnder(
    WidgetTester tester,
    Widget home, {
    Size size = _phone,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<LocationBloc>.value(value: locationBloc),
          BlocProvider<PeopleBloc>.value(value: peopleBloc),
          BlocProvider<PulseBloc>.value(value: pulseBloc),
          BlocProvider<ProfileBloc>.value(value: profileBloc),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
          BlocProvider<MapSettingsCubit>.value(value: mapSettings),
          BlocProvider<AirportBloc>.value(value: airportBloc),
          BlocProvider<StationBloc>.value(value: stationBloc),
          BlocProvider<TripBloc>.value(value: tripBloc),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  group('AuthWrapper', () {
    for (final state in <AuthState>[AuthInitial(), AuthLoading()]) {
      testWidgets('${state.runtimeType} shows only the pulse', (tester) async {
        whenListen(
          authBloc,
          const Stream<AuthState>.empty(),
          initialState: state,
        );
        await pumpUnder(tester, const AuthWrapper(), size: _tablet);

        expect(find.byType(PulseIndicator), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(MainScreen), findsNothing);
      });
    }

    testWidgets('Authenticated shows the shell', (tester) async {
      await pumpUnder(tester, const AuthWrapper(), size: _tablet);

      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    for (final state in <AuthState>[
      const Unauthenticated(),
      const AuthError(message: 'nope'),
      const PasswordResetSent(message: 'sent'),
      const RegistrationSuccess(),
    ]) {
      testWidgets('${state.runtimeType} shows the login screen', (
        tester,
      ) async {
        whenListen(
          authBloc,
          const Stream<AuthState>.empty(),
          initialState: state,
        );
        await pumpUnder(tester, const AuthWrapper(), size: _tablet);
        // The login card's sign-up row overflows under the test font; see
        // login_screen_dev_test.dart.
        tester.takeException();

        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(MainScreen), findsNothing);
      });
    }

    testWidgets('signing in swaps login for the shell, and logging out swaps '
        'it back', (tester) async {
      final states = StreamController<AuthState>();
      addTearDown(() => unawaited(states.close()));
      whenListen(
        authBloc,
        states.stream,
        initialState: const Unauthenticated(),
      );
      await pumpUnder(tester, const AuthWrapper(), size: _tablet);
      tester.takeException();
      expect(find.byType(LoginScreen), findsOneWidget);

      states.add(const Authenticated(accessToken: 'a', refreshToken: 'r'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      states.add(const Unauthenticated(message: 'You have been logged out.'));
      await tester.pump();
      await tester.pump();
      tester.takeException();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
    });
  });

  group('MainScreen', () {
    testWidgets('loads the profile on launch', (tester) async {
      await pumpUnder(tester, const MainScreen());

      verify(() => profileBloc.add(LoadProfile())).called(1);
    });

    testWidgets('opens on the map', (tester) async {
      await pumpUnder(tester, const MainScreen());

      expect(find.byType(MapScreen), findsOneWidget);
    });

    bool tabSelected(WidgetTester tester, String label) {
      final semantics = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '$label Tab',
        ),
      );
      return semantics.properties.selected ?? false;
    }

    for (final entry in {'phone bar': _phone, 'tablet rail': _tablet}.entries) {
      testWidgets('every tab shows its screen on the ${entry.key}', (
        tester,
      ) async {
        await pumpUnder(tester, const MainScreen(), size: entry.value);
        expect(tabSelected(tester, 'Map'), isTrue);

        final screens = <String, Type>{
          'People': PeopleScreen,
          'Pulse': PulseScreen,
          'Trips': TripsScreen,
          'Me': MeScreen,
          'Map': MapScreen,
        };
        for (final tab in screens.entries) {
          await tester.tap(find.text(tab.key).last);
          await tester.pump();
          await tester.pump();

          expect(
            find.byType(tab.value),
            findsOneWidget,
            reason: '${tab.key} tab',
          );
          expect(tabSelected(tester, tab.key), isTrue);
          for (final other in screens.keys.where((k) => k != tab.key)) {
            expect(tabSelected(tester, other), isFalse);
          }
        }
      });
    }

    testWidgets('Trips can send the user back to the map', (tester) async {
      await pumpUnder(tester, const MainScreen());
      await tester.tap(find.text('Trips'));
      await tester.pump();

      tester.widget<TripsScreen>(find.byType(TripsScreen)).onNavigateToMap();
      await tester.pump();

      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.byType(TripsScreen), findsNothing);
    });

    group('distance unit sync', () {
      Future<void> deliverProfile(
        WidgetTester tester,
        ProfileLoaded profile,
      ) async {
        final states = StreamController<ProfileState>();
        addTearDown(() => unawaited(states.close()));
        whenListen(profileBloc, states.stream, initialState: ProfileLoading());
        await pumpUnder(tester, const MainScreen());
        states.add(profile);
        await tester.pump();
        await tester.pump();
      }

      testWidgets('a profile saved as imperial switches the map to imperial', (
        tester,
      ) async {
        await deliverProfile(
          tester,
          const ProfileLoaded(distanceUnit: 'imperial'),
        );

        verify(
          () => mapSettings.setDistanceUnit(DistanceUnit.imperial),
        ).called(1);
      });

      testWidgets('a profile saved as metric switches the map back', (
        tester,
      ) async {
        whenListen(
          mapSettings,
          const Stream<MapSettingsState>.empty(),
          initialState: const MapSettingsState(
            distanceUnit: DistanceUnit.imperial,
          ),
        );
        await deliverProfile(
          tester,
          const ProfileLoaded(distanceUnit: 'metric'),
        );

        verify(
          () => mapSettings.setDistanceUnit(DistanceUnit.metric),
        ).called(1);
      });

      testWidgets('a unit that already matches is not rewritten', (
        tester,
      ) async {
        await deliverProfile(
          tester,
          const ProfileLoaded(distanceUnit: 'metric'),
        );

        verifyNever(() => mapSettings.setDistanceUnit(any()));
      });

      testWidgets('a profile with no unit leaves the setting alone', (
        tester,
      ) async {
        await deliverProfile(tester, const ProfileLoaded(username: 'ada'));

        verifyNever(() => mapSettings.setDistanceUnit(any()));
      });
    });
  });

  group('MyApp', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> pumpApp(WidgetTester tester) async {
      // Wide enough that only the known sign-up row overflows under the test
      // font; at phone width the social buttons do too.
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 1000),
            disableAnimations: true,
          ),
          child: MyApp(prefs: prefs),
        ),
      );
      // CheckAuthStatus reads secure storage before settling.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      tester.takeException();
    }

    MaterialApp app(WidgetTester tester) =>
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    testWidgets('with no stored session, lands on the login screen', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(app(tester).title, 'Map My Friends');
      expect(app(tester).supportedLocales, const [Locale('en'), Locale('es')]);
    });

    testWidgets('the app theme follows ThemeCubit', (tester) async {
      await pumpApp(tester);
      expect(app(tester).themeMode, ThemeMode.system);

      final cubit = tester.element(find.byType(LoginScreen)).read<ThemeCubit>();
      cubit.setTheme(ThemeMode.dark);
      await tester.pump();
      await tester.pump();
      tester.takeException();
      expect(app(tester).themeMode, ThemeMode.dark);

      cubit.setTheme(ThemeMode.light);
      await tester.pump();
      await tester.pump();
      tester.takeException();
      expect(app(tester).themeMode, ThemeMode.light);
    });
  });
}
