import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/screens/map/map_screen.dart';
import 'package:map_my_friends/services/api_service.dart';
import 'package:map_my_friends/components/map/person_map_marker.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/station/station_event.dart';
import 'package:map_my_friends/bloc/profile/profile_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:map_my_friends/components/map/map_controls.dart'; // Implicitly tested via MapScreen

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
}

void main() {
  // Use a simple test that doesn't depend on complex implementation details
  // but verifies that the UI is built after state is loaded.

  testWidgets('MapScreen shows zoom and pan controls', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LocationBloc>(create: (context) => FakeLocationBloc()),
          BlocProvider<PeopleBloc>(create: (context) => FakePeopleBloc()),
          BlocProvider<MapSettingsCubit>(
            create: (context) => FakeMapSettingsCubit(prefs),
          ),
          BlocProvider<AirportBloc>(create: (context) => AirportBloc()),
          BlocProvider<StationBloc>(create: (context) => StationBloc()),
          BlocProvider<ProfileBloc>(create: (context) => ProfileBloc()),
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

    // Verify PersonMapMarker (User location pin)
    expect(
      find.byType(PersonMapMarker),
      findsOneWidget,
    ); // One on map (marker) maybe, one on button

    // Basic interaction check
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
  }, skip: false); // Ensure it runs
}
