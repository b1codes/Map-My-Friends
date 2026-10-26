import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_event.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/auth/auth_bloc.dart';
import 'package:map_my_friends/bloc/auth/auth_event.dart';
import 'package:map_my_friends/bloc/auth/auth_state.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/profile/profile_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_event.dart';
import 'package:map_my_friends/bloc/profile/profile_state.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/station/station_event.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/bloc/theme/theme_cubit.dart';
import 'package:map_my_friends/components/map/custom_map_marker.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/components/shared/image_editor_modal.dart';
import 'package:map_my_friends/components/shared/nearby_blocs.dart';
import 'package:map_my_friends/l10n/app_localizations.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/screens/profile/me_screen.dart';
import 'package:map_my_friends/screens/settings/settings_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockProfileBloc extends MockBloc<ProfileEvent, ProfileState>
    implements ProfileBloc {}

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

class MockMapSettingsCubit extends MockCubit<MapSettingsState>
    implements MapSettingsCubit {}

class MockThemeCubit extends MockCubit<ThemeMode> implements ThemeCubit {}

class MockAirportBloc extends MockBloc<AirportEvent, AirportState>
    implements AirportBloc {}

class MockStationBloc extends MockBloc<StationEvent, StationState>
    implements StationBloc {}

class MockImagePicker extends Mock implements ImagePicker {}

const _loaded = ProfileLoaded(
  username: 'ada',
  email: 'ada@example.com',
  firstName: 'Ada',
  lastName: 'Lovelace',
  city: 'London',
  state: 'England',
  country: 'UK',
  street: '12 St James Sq',
  birthDate: '1990-05-15',
  phoneNumber: '2015550123',
  pinColor: '#E91E63',
  pinStyle: 'circle',
  pinIconType: 'initials',
  pinEmoji: '🚀',
  distanceUnit: 'imperial',
);

final _position = Position(
  latitude: 51.5,
  longitude: -0.12,
  timestamp: DateTime(2026),
  accuracy: 1,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late MockProfileBloc profileBloc;
  late MockAuthBloc authBloc;
  late MockLocationBloc locationBloc;
  late MockMapSettingsCubit mapSettings;
  late MockThemeCubit themeCubit;
  late MockAirportBloc nearbyAirports;
  late MockStationBloc nearbyStations;
  late MockImagePicker imagePicker;

  setUpAll(() {
    registerFallbackValue(LoadProfile());
    registerFallbackValue(LogoutRequested());
    registerFallbackValue(ImageSource.gallery);
  });

  setUp(() {
    profileBloc = MockProfileBloc();
    authBloc = MockAuthBloc();
    locationBloc = MockLocationBloc();
    mapSettings = MockMapSettingsCubit();
    themeCubit = MockThemeCubit();
    nearbyAirports = MockAirportBloc();
    nearbyStations = MockStationBloc();
    imagePicker = MockImagePicker();

    whenListen(
      profileBloc,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoading(),
    );
    whenListen(
      authBloc,
      const Stream<AuthState>.empty(),
      initialState: const Authenticated(accessToken: 'a', refreshToken: 'r'),
    );
    whenListen(
      locationBloc,
      const Stream<LocationState>.empty(),
      initialState: LocationInitial(),
    );
    whenListen(
      mapSettings,
      const Stream<MapSettingsState>.empty(),
      initialState: const MapSettingsState(),
    );
    whenListen(
      themeCubit,
      const Stream<ThemeMode>.empty(),
      initialState: ThemeMode.system,
    );
    whenListen(
      nearbyAirports,
      const Stream<AirportState>.empty(),
      initialState: AirportInitial(),
    );
    whenListen(
      nearbyStations,
      const Stream<StationState>.empty(),
      initialState: StationInitial(),
    );
  });

  Future<void> pumpMe(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileBloc>.value(value: profileBloc),
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<LocationBloc>.value(value: locationBloc),
          BlocProvider<MapSettingsCubit>.value(value: mapSettings),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          // The shell owns the BackdropGroup in production.
          home: BackdropGroup(child: MeScreen(imagePicker: imagePicker)),
        ),
      ),
    );
    await tester.pump();
  }

  /// Mounts the screen, then delivers [state] as a change, the way a real
  /// LoadProfile round-trip arrives.
  Future<StreamController<ProfileState>> pumpWithProfile(
    WidgetTester tester, [
    ProfileState state = _loaded,
  ]) async {
    final controller = StreamController<ProfileState>();
    addTearDown(() => unawaited(controller.close()));
    whenListen(profileBloc, controller.stream, initialState: ProfileLoading());
    await pumpMe(tester);
    controller.add(state);
    await tester.pump();
    await tester.pump();
    return controller;
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  String fieldText(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(field(label)).controller!.text;
  final saveButton = find.widgetWithText(FilledButton, 'Save Profile');

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  UpdateProfile capturedUpdate() =>
      verify(
            () => profileBloc.add(captureAny(that: isA<UpdateProfile>())),
          ).captured.single
          as UpdateProfile;

  group('MeScreen loading', () {
    testWidgets('asks for the profile on mount', (tester) async {
      await pumpMe(tester);

      verify(() => profileBloc.add(LoadProfile())).called(1);
    });

    testWidgets('fills every field from the loaded profile', (tester) async {
      await pumpWithProfile(tester);

      expect(fieldText(tester, 'First Name'), 'Ada');
      expect(fieldText(tester, 'Last Name'), 'Lovelace');
      expect(fieldText(tester, 'Street Address (Optional)'), '12 St James Sq');
      expect(fieldText(tester, 'City (Required)'), 'London');
      expect(fieldText(tester, 'State (Required)'), 'England');
      expect(fieldText(tester, 'Country (Required)'), 'UK');
      expect(fieldText(tester, 'Birth Date (YYYY-MM-DD)'), '1990-05-15');
      expect(find.text('2015550123'), findsOneWidget);
    });

    testWidgets('applies the saved pin, unit and shape choices', (
      tester,
    ) async {
      await pumpWithProfile(tester);

      final marker = tester.widget<CustomMapMarker>(
        find.byType(CustomMapMarker),
      );
      expect(marker.pinColorHex, '#E91E63');
      expect(marker.pinStyle, 'circle');
      expect(marker.pinIconType, 'initials');
      expect(marker.initials, 'AL');
      expect(find.text('Circle'), findsOneWidget);
      expect(find.text('Initials'), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<String>>(
              find.byType(SegmentedButton<String>),
            )
            .selected,
        {'imperial'},
      );
    });

    testWidgets('does not overwrite what the user is typing when the profile '
        'reloads', (tester) async {
      final states = await pumpWithProfile(tester);

      await tester.enterText(field('City (Required)'), 'Paris');
      states.add(_loaded.copyWith(city: 'Rome', email: 'new@example.com'));
      await tester.pump();
      await tester.pump();

      expect(fieldText(tester, 'City (Required)'), 'Paris');
    });

    testWidgets('a ProfileError is shown as a toast', (tester) async {
      await pumpWithProfile(
        tester,
        const ProfileError(message: 'Session expired'),
      );

      expect(find.text('Session expired'), findsOneWidget);
    });
  });

  group('MeScreen saving', () {
    testWidgets('requires city, state and country', (tester) async {
      await pumpMe(tester);

      await tapVisible(tester, saveButton);

      expect(find.text('City is required'), findsOneWidget);
      expect(find.text('Required'), findsNWidgets(2));
      verifyNever(() => profileBloc.add(any(that: isA<UpdateProfile>())));
      expect(find.text('Profile Saved'), findsNothing);
    });

    testWidgets('sends every loaded field back unchanged', (tester) async {
      await pumpWithProfile(tester);

      await tapVisible(tester, saveButton);

      expect(
        capturedUpdate(),
        const UpdateProfile(
          firstName: 'Ada',
          lastName: 'Lovelace',
          phoneNumber: '2015550123',
          birthDate: '1990-05-15',
          city: 'London',
          state: 'England',
          country: 'UK',
          street: '12 St James Sq',
          pinColor: '#E91E63',
          pinStyle: 'circle',
          pinIconType: 'initials',
          pinEmoji: '🚀',
          distanceUnit: 'imperial',
        ),
      );
      expect(find.text('Profile Saved'), findsOneWidget);
    });

    testWidgets('empty optional fields are sent as null and defaults fill '
        'the pin', (tester) async {
      await pumpWithProfile(
        tester,
        const ProfileLoaded(city: 'Oslo', state: 'Oslo', country: 'Norway'),
      );

      await tapVisible(tester, saveButton);

      expect(
        capturedUpdate(),
        const UpdateProfile(
          city: 'Oslo',
          state: 'Oslo',
          country: 'Norway',
          pinColor: '#3F51B5',
          pinStyle: 'teardrop',
          pinIconType: 'none',
          pinEmoji: '😀',
          distanceUnit: 'metric',
        ),
      );
    });

    testWidgets('sends the edits the user made', (tester) async {
      await pumpWithProfile(tester);

      await tester.enterText(field('First Name'), 'Augusta');
      await tester.enterText(field('Street Address (Optional)'), '');
      await tester.enterText(field('City (Required)'), 'Paris');
      await tapVisible(tester, find.text('Metric (km)'));
      await tapVisible(tester, saveButton);

      final update = capturedUpdate();
      expect(update.firstName, 'Augusta');
      expect(update.street, isNull);
      expect(update.city, 'Paris');
      expect(update.distanceUnit, 'metric');
    });

    testWidgets('picking a birth date writes it as YYYY-MM-DD', (tester) async {
      await pumpWithProfile(tester);

      await tapVisible(tester, field('Birth Date (YYYY-MM-DD)'));
      await tester.pumpAndSettle();
      // Opens on the saved date's month.
      expect(find.text('May 1990'), findsOneWidget);
      await tester.tap(find.text('3'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'Birth Date (YYYY-MM-DD)'), '1990-05-03');

      await tapVisible(tester, saveButton);
      expect(capturedUpdate().birthDate, '1990-05-03');
    });

    testWidgets('cancelling the date picker keeps the old date', (
      tester,
    ) async {
      await pumpWithProfile(tester);

      await tapVisible(tester, field('Birth Date (YYYY-MM-DD)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'Birth Date (YYYY-MM-DD)'), '1990-05-15');
    });

    testWidgets('while ProfileUpdating, save and photo are disabled', (
      tester,
    ) async {
      whenListen(
        profileBloc,
        const Stream<ProfileState>.empty(),
        initialState: ProfileUpdating(),
      );
      await pumpMe(tester);

      expect(find.text('Save Profile'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      // Both the save button and the photo badge show the pulse.
      expect(find.byType(ChromaticPulse), findsNWidgets(2));
      expect(find.byIcon(Icons.camera_alt), findsNothing);
    });
  });

  group('MeScreen pin customisation', () {
    testWidgets('changing the shape updates the preview and the save', (
      tester,
    ) async {
      await pumpWithProfile(tester);

      await tapVisible(tester, find.text('Circle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diamond').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<CustomMapMarker>(find.byType(CustomMapMarker)).pinStyle,
        'diamond',
      );
      await tapVisible(tester, saveButton);
      expect(capturedUpdate().pinStyle, 'diamond');
    });

    testWidgets('choosing Emoji reveals the emoji chooser with the saved '
        'emoji', (tester) async {
      await pumpWithProfile(tester);
      expect(find.text('Selected Emoji'), findsNothing);

      await tapVisible(tester, find.text('Initials'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emoji').last);
      await tester.pumpAndSettle();

      expect(find.text('Selected Emoji'), findsOneWidget);
      expect(find.text('🚀'), findsWidgets);
      await tapVisible(tester, saveButton);
      expect(capturedUpdate().pinIconType, 'emoji');
    });

    testWidgets('a colour from the picker becomes the pin colour', (
      tester,
    ) async {
      await pumpWithProfile(tester);

      await tapVisible(
        tester,
        find
            .descendant(
              of: find.widgetWithText(ListTile, 'Pin Color'),
              matching: find.byType(GestureDetector),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Pick a Pin Color'), findsOneWidget);

      final picker = tester.widget<BlockPicker>(find.byType(BlockPicker));
      final chosen = picker.availableColors.first;
      await tester.tap(
        find
            .descendant(
              of: find.byType(BlockPicker),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pump();
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      final expected =
          '#${chosen.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
      expect(
        tester
            .widget<CustomMapMarker>(find.byType(CustomMapMarker))
            .pinColorHex,
        expected,
      );
      await tapVisible(tester, saveButton);
      expect(capturedUpdate().pinColor, expected);
    });
  });

  group('MeScreen profile photo', () {
    // A 1x1 transparent PNG: a real image, so MemoryImage can decode it.
    final png = Uint8List.fromList(const <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
      0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00,
      0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

    void stubPick(XFile? result) {
      when(
        () => imagePicker.pickImage(
          source: any(named: 'source'),
          maxWidth: any(named: 'maxWidth'),
          maxHeight: any(named: 'maxHeight'),
          imageQuality: any(named: 'imageQuality'),
        ),
      ).thenAnswer((_) async => result);
    }

    Future<void> chooseSource(WidgetTester tester, String label) async {
      await tapVisible(tester, find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();
      expect(find.text('Profile photo'), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    for (final entry in {
      'Take a Photo': ImageSource.camera,
      'Choose from Gallery': ImageSource.gallery,
    }.entries) {
      testWidgets('"${entry.key}" asks the picker for ${entry.value.name}', (
        tester,
      ) async {
        stubPick(null);
        await pumpWithProfile(tester);

        await chooseSource(tester, entry.key);

        verify(
          () => imagePicker.pickImage(
            source: entry.value,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 90,
          ),
        ).called(1);
      });
    }

    testWidgets('cancelling the picker uploads nothing', (tester) async {
      stubPick(null);
      await pumpWithProfile(tester);

      await chooseSource(tester, 'Choose from Gallery');

      expect(find.byType(ImageEditorModal), findsNothing);
      verifyNever(() => profileBloc.add(any(that: isA<UploadProfileImage>())));
    });

    testWidgets('a picked photo opens the editor, and its crop is uploaded '
        'and shown at once', (tester) async {
      stubPick(XFile.fromData(png, name: 'me.png'));
      await pumpWithProfile(tester);

      await chooseSource(tester, 'Choose from Gallery');
      // readAsBytes on an in-memory XFile is a real future.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      final editor = tester.widget<ImageEditorModal>(
        find.byType(ImageEditorModal),
      );
      expect(editor.imageBytes, png);
      expect(editor.isCircular, isTrue);

      final cropped = Uint8List.fromList(png);
      Navigator.of(tester.element(find.byType(ImageEditorModal))).pop(cropped);
      await tester.pumpAndSettle();

      verify(
        () => profileBloc.add(UploadProfileImage(imageBytes: cropped)),
      ).called(1);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isA<MemoryImage>());
    });

    testWidgets('backing out of the editor uploads nothing', (tester) async {
      stubPick(XFile.fromData(png, name: 'me.png'));
      await pumpWithProfile(tester);

      await chooseSource(tester, 'Take a Photo');
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ImageEditorModal))).pop();
      await tester.pumpAndSettle();

      verifyNever(() => profileBloc.add(any(that: isA<UploadProfileImage>())));
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);
    });
  });

  group('MeScreen nearby transport', () {
    testWidgets('hidden until the device location is known', (tester) async {
      await pumpWithProfile(tester);

      expect(find.text('Nearby Airports'), findsNothing);
      expect(find.text('Nearby Train Stations'), findsNothing);
    });

    testWidgets('a location without a position shows neither section', (
      tester,
    ) async {
      whenListen(
        locationBloc,
        const Stream<LocationState>.empty(),
        initialState: const LocationLoaded(),
      );
      await pumpWithProfile(tester);

      expect(find.text('Nearby Airports'), findsNothing);
    });

    testWidgets('with a position, lists the nearest airports and stations', (
      tester,
    ) async {
      whenListen(
        locationBloc,
        const Stream<LocationState>.empty(),
        initialState: LocationLoaded(position: _position),
      );
      whenListen(
        nearbyAirports,
        const Stream<AirportState>.empty(),
        initialState: NearestAirportsLoaded([
          Airport(
            name: 'Heathrow',
            iataCode: 'LHR',
            airportType: 'large_airport',
            city: 'London',
            country: 'GB',
            latitude: 51.47,
            longitude: -0.45,
            distanceKm: 22,
          ),
        ]),
      );
      whenListen(
        nearbyStations,
        const Stream<StationState>.empty(),
        initialState: NearestStationsLoaded([
          Station(
            name: 'Kings Cross',
            osmId: 1,
            city: 'London',
            country: 'GB',
            latitude: 51.53,
            longitude: -0.12,
            distanceKm: 3,
          ),
        ]),
      );
      await pumpWithProfile(tester);

      expect(find.text('Nearby Airports'), findsOneWidget);
      expect(find.text('LHR'), findsOneWidget);
      expect(find.text('Heathrow'), findsOneWidget);
      expect(find.text('Nearby Train Stations'), findsOneWidget);
      expect(find.text('Kings Cross'), findsOneWidget);
    });
  });

  group('MeScreen account', () {
    testWidgets('Logout dispatches LogoutRequested', (tester) async {
      await pumpWithProfile(tester);

      await tapVisible(tester, find.text('Logout'));

      verify(() => authBloc.add(LogoutRequested())).called(1);
    });

    testWidgets('the Settings action opens Settings', (tester) async {
      await pumpWithProfile(tester);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });
}
