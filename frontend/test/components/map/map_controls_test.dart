import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/components/map/map_controls.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/screens/map/map_screen.dart';
import 'package:map_my_friends/services/api_service.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/map/local_map_settings_cubit.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mock ApiService
class MockApiService implements ApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Custom fake LocationBloc
class FakeLocationBloc extends Bloc<LocationEvent, LocationState>
    implements LocationBloc {
  FakeLocationBloc()
    : super(
        LocationLoaded(
          position: Position(
            longitude: -122.4194, // SF
            latitude: 37.7749, // SF
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0, // Added to fix compilation error
            floor: 0, // Added for safety
            isMocked: true,
          ),
        ),
      ) {
    on<LocationEvent>((event, emit) {});
  }
}

// Custom fake PeopleBloc
class FakePeopleBloc extends Bloc<PeopleEvent, PeopleState>
    implements PeopleBloc {
  FakePeopleBloc()
    : super(
        PeopleLoaded([
          Person(
            id: '1',
            firstName: 'John',
            lastName: 'Doe',
            city: 'San Francisco',
            state: 'CA',
            country: 'USA',
            relationshipTag: 'Friend',
            latitude: 37.7749,
            longitude: -122.4194,
          ),
        ]),
      ) {
    on<PeopleEvent>((event, emit) {});
  }
}

class FakeMapSettingsCubit extends Cubit<MapSettingsState>
    implements MapSettingsCubit {
  @override
  final SharedPreferences prefs;

  FakeMapSettingsCubit(this.prefs) : super(const MapSettingsState());

  @override
  void toggleControls() {}

  @override
  void setMapType(MapType type) {}

  @override
  void setMapTheme(ThemeMode mode) {}

  @override
  void toggleAirports() {}

  @override
  void toggleStations() {}

  @override
  void setAirportFilter(AirportFilter filter) {}

  @override
  void setStationFilter(StationFilter filter) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockMapController extends Mock implements MapController {}

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

void main() {
  // Use a simple test that doesn't depend on complex implementation details
  // but verifies that the UI is built after state is loaded.

  testWidgets('MapScreen shows zoom and pan controls', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final mapSettingsCubit = FakeMapSettingsCubit(prefs);

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LocationBloc>(create: (context) => FakeLocationBloc()),
          BlocProvider<PeopleBloc>(create: (context) => FakePeopleBloc()),
          BlocProvider<MapSettingsCubit>(create: (context) => mapSettingsCubit),
          BlocProvider<LocalMapSettingsCubit>(
            create: (context) =>
                LocalMapSettingsCubit(initialState: mapSettingsCubit.state),
          ),
          BlocProvider<AirportBloc>(create: (context) => AirportBloc()),
          BlocProvider<StationBloc>(create: (context) => StationBloc()),
          BlocProvider<ProfileBloc>(create: (context) => ProfileBloc()),
          BlocProvider<TripBloc>(create: (context) => TripBloc()),
        ],
        child: const MaterialApp(home: MapScreen()),
      ),
    );

    // Initial pump
    await tester.pump();
    // Allow any animations or async ops to settle
    await tester.pumpAndSettle();

    // Verify zoom buttons are present
    expect(find.byIcon(Icons.add), findsOneWidget); // Zoom In
    expect(find.byIcon(Icons.remove), findsOneWidget); // Zoom Out

    // Verify pan buttons are present
    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.byIcon(Icons.arrow_left), findsOneWidget);
    expect(find.byIcon(Icons.arrow_right), findsOneWidget);
    // Verify reset button
    expect(find.byIcon(Icons.my_location), findsAtLeastNWidgets(1));

    // Basic interaction check
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
  }, skip: false); // Ensure it runs

  group('MapControls', () {
    late MockMapController controller;
    late MockLocationBloc locationBloc;

    setUpAll(() {
      registerFallbackValue(const LatLng(0, 0));
    });

    setUp(() {
      controller = MockMapController();
      locationBloc = MockLocationBloc();
      when(() => locationBloc.state).thenReturn(LocationInitial());
      when(() => controller.camera).thenReturn(
        MapCamera(
          crs: const Epsg3857(),
          center: const LatLng(10, 20),
          zoom: 5,
          rotation: 0,
          nonRotatedSize: const Size(400, 800),
        ),
      );
      when(() => controller.move(any(), any())).thenReturn(true);
    });

    Future<void> pumpControls(
      WidgetTester tester, {
      Size size = const Size(400, 800),
      bool modal = false,
      bool reduceMotion = false,
      double bottomPadding = 0,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              disableAnimations: reduceMotion,
              padding: EdgeInsets.only(bottom: bottomPadding),
            ),
            child: BackdropGroup(
              child: Scaffold(
                body: BlocProvider<LocationBloc>.value(
                  value: locationBloc,
                  child: MapControls(
                    mapController: controller,
                    isBottomModalVisible: modal,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// The one center/zoom pair the controller was last moved to.
    (LatLng, double) lastMove() {
      final captured = verify(
        () => controller.move(captureAny(), captureAny()),
      ).captured;
      expect(captured, hasLength(2), reason: 'exactly one move');
      return (captured[0] as LatLng, captured[1] as double);
    }

    testWidgets('labels every button for assistive technology', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpControls(tester);

      for (final label in [
        'Pan Up',
        'Pan Down',
        'Pan Left',
        'Pan Right',
        'My Location',
        'Zoom In',
        'Zoom Out',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      semantics.dispose();
    });

    testWidgets('zoom in and out step the zoom by one at the same center', (
      tester,
    ) async {
      await pumpControls(tester);

      await tester.tap(find.byIcon(Icons.add));
      var (center, zoom) = lastMove();
      expect(center, const LatLng(10, 20));
      expect(zoom, 6);

      await tester.tap(find.byIcon(Icons.remove));
      (center, zoom) = lastMove();
      expect(center, const LatLng(10, 20));
      expect(zoom, 4);
    });

    for (final (icon, name, dLat, dLon) in [
      (Icons.arrow_drop_up, 'up', 0.01, 0.0),
      (Icons.arrow_drop_down, 'down', -0.01, 0.0),
      (Icons.arrow_left, 'left', 0.0, -0.01),
      (Icons.arrow_right, 'right', 0.0, 0.01),
    ]) {
      testWidgets('panning $name nudges the center and keeps the zoom', (
        tester,
      ) async {
        await pumpControls(tester);

        await tester.tap(find.byIcon(icon));
        final (center, zoom) = lastMove();
        expect(center.latitude, closeTo(10 + dLat, 1e-9));
        expect(center.longitude, closeTo(20 + dLon, 1e-9));
        expect(zoom, 5);
      });
    }

    testWidgets('my location centers on the device at street zoom', (
      tester,
    ) async {
      when(() => locationBloc.state).thenReturn(
        LocationLoaded(
          position: Position(
            latitude: 48.8566,
            longitude: 2.3522,
            timestamp: DateTime(2026),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          ),
        ),
      );
      await pumpControls(tester);

      await tester.tap(find.byIcon(Icons.my_location));
      final (center, zoom) = lastMove();
      expect(center, const LatLng(48.8566, 2.3522));
      expect(zoom, 13);
    });

    for (final state in <LocationState>[
      LocationInitial(),
      const LocationLoaded(),
      LocationPermissionDenied(),
    ]) {
      testWidgets(
        'my location falls back to San Francisco on ${state.runtimeType}'
        '${state is LocationLoaded ? ' without a position' : ''}',
        (tester) async {
          when(() => locationBloc.state).thenReturn(state);
          await pumpControls(tester);

          await tester.tap(find.byIcon(Icons.my_location));
          final (center, zoom) = lastMove();
          expect(center, const LatLng(37.7749, -122.4194));
          expect(zoom, 13);
        },
      );
    }

    List<AnimatedPositioned> positioned(WidgetTester tester) => tester
        .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
        .toList();

    testWidgets('a tall phone stacks zoom above pan, clear of the nav bar', (
      tester,
    ) async {
      await pumpControls(tester, bottomPadding: 10);

      final groups = positioned(tester);
      expect(groups, hasLength(2));
      // Bar navigation (88) plus the safe-area inset (10).
      expect(groups[0].bottom, 24 + 88 + 10);
      expect(groups[1].bottom, 192 + 88 + 10);
      expect(groups.map((g) => g.right), everyElement(16));
      expect(groups.first.duration, const Duration(milliseconds: 300));
    });

    testWidgets('both groups lift above an open bottom modal', (tester) async {
      await pumpControls(tester, modal: true);

      final groups = positioned(tester);
      expect(groups[0].bottom, 180 + 88);
      expect(groups[1].bottom, 348 + 88);
    });

    testWidgets('a wide, tall window sits beside a rail with no nav inset', (
      tester,
    ) async {
      await pumpControls(
        tester,
        size: const Size(1200, 900),
        bottomPadding: 10,
      );

      final groups = positioned(tester);
      // A rail leaves the bottom edge free: no bar inset, no safe-area inset.
      expect(groups[0].bottom, 24);
      expect(groups[1].bottom, 192);
      expect(groups.map((g) => g.right), everyElement(24));
    });

    testWidgets('a short window lays the groups side by side', (tester) async {
      await pumpControls(tester, size: const Size(800, 400));

      final groups = positioned(tester);
      expect(groups, hasLength(1));
      expect(groups.single.bottom, 24 + 88);
      final row = tester.widget<Row>(
        find
            .descendant(
              of: find.byType(AnimatedPositioned),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(row.crossAxisAlignment, CrossAxisAlignment.end);
      // Every control is still reachable.
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    });

    testWidgets('reduced motion repositions without animating', (tester) async {
      await pumpControls(tester, reduceMotion: true);

      expect(
        positioned(tester).map((g) => g.duration),
        everyElement(Duration.zero),
      );
    });
  });
}
