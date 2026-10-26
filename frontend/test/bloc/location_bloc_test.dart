import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';

/// A scripted [GeolocatorPlatform]: each answer is set per test, and calls are
/// counted so a test can assert which platform APIs the bloc touched.
class FakeGeolocator extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestResult = LocationPermission.whileInUse;
  Object? positionError;
  Position position = _position(41.8781, -87.6298);

  int requestCalls = 0;
  int positionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCalls++;
    return requestResult;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    positionCalls++;
    final error = positionError;
    if (error != null) throw error;
    return position;
  }
}

Position _position(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.utc(2026, 1, 1),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late FakeGeolocator geo;
  late GeolocatorPlatform original;

  setUpAll(() {
    original = GeolocatorPlatform.instance;
  });

  setUp(() {
    geo = FakeGeolocator();
    GeolocatorPlatform.instance = geo;
  });

  tearDownAll(() {
    GeolocatorPlatform.instance = original;
  });

  test('initial state is LocationInitial', () {
    final bloc = LocationBloc();
    expect(bloc.state, LocationInitial());
    bloc.close();
  });

  group('LoadLocation', () {
    blocTest<LocationBloc, LocationState>(
      'emits the current position when permission is already granted',
      build: LocationBloc.new,
      act: (bloc) => bloc.add(LoadLocation()),
      expect: () => [LocationLoading(), LocationLoaded(position: geo.position)],
      verify: (_) {
        expect(geo.requestCalls, 0);
        expect(geo.positionCalls, 1);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'reports disabled location services without asking for permission',
      build: () {
        geo.serviceEnabled = false;
        return LocationBloc();
      },
      act: (bloc) => bloc.add(LoadLocation()),
      expect: () => [
        LocationLoading(),
        const LocationError('Location services are disabled.'),
      ],
      verify: (_) {
        expect(geo.requestCalls, 0);
        expect(geo.positionCalls, 0);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'asks once when denied and stops if the user denies again',
      build: () {
        geo.permission = LocationPermission.denied;
        geo.requestResult = LocationPermission.denied;
        return LocationBloc();
      },
      act: (bloc) => bloc.add(LoadLocation()),
      expect: () => [LocationLoading(), LocationPermissionDenied()],
      verify: (_) {
        expect(geo.requestCalls, 1);
        expect(geo.positionCalls, 0);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'reads the position once the request is granted',
      build: () {
        geo.permission = LocationPermission.denied;
        geo.requestResult = LocationPermission.always;
        geo.position = _position(51.5074, -0.1278);
        return LocationBloc();
      },
      act: (bloc) => bloc.add(LoadLocation()),
      expect: () => [
        LocationLoading(),
        LocationLoaded(position: _position(51.5074, -0.1278)),
      ],
      verify: (_) {
        expect(geo.requestCalls, 1);
        expect(geo.positionCalls, 1);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'reports permanent denial without prompting',
      build: () {
        geo.permission = LocationPermission.deniedForever;
        return LocationBloc();
      },
      act: (bloc) => bloc.add(LoadLocation()),
      expect: () => [LocationLoading(), LocationPermissionDeniedForever()],
      verify: (_) {
        expect(geo.requestCalls, 0);
        expect(geo.positionCalls, 0);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'reports permanent denial chosen during the request',
      build: () {
        geo.permission = LocationPermission.denied;
        geo.requestResult = LocationPermission.deniedForever;
        return LocationBloc();
      },
      act: (bloc) => bloc.add(LoadLocation()),
      expect: () => [LocationLoading(), LocationPermissionDeniedForever()],
    );

    blocTest<LocationBloc, LocationState>(
      'surfaces a platform error as LocationError',
      build: () {
        geo.positionError = const LocationServiceDisabledException();
        return LocationBloc();
      },
      act: (bloc) => bloc.add(LoadLocation()),
      expect: () => [
        LocationLoading(),
        const LocationError('The location service on the device is disabled.'),
      ],
    );
  });

  blocTest<LocationBloc, LocationState>(
    'RequestPermission re-runs the LoadLocation flow',
    build: LocationBloc.new,
    act: (bloc) => bloc.add(RequestPermission()),
    expect: () => [LocationLoading(), LocationLoaded(position: geo.position)],
    verify: (_) {
      expect(geo.positionCalls, 1);
    },
  );

  blocTest<LocationBloc, LocationState>(
    'UpdateUserAddress is a no-op',
    build: LocationBloc.new,
    act: (bloc) => bloc.add(
      const UpdateUserAddress(
        city: 'Chicago',
        state: 'IL',
        country: 'USA',
        street: '1 Main St',
      ),
    ),
    expect: () => <LocationState>[],
    verify: (_) {
      expect(geo.positionCalls, 0);
    },
  );

  test('UpdateUserAddress compares by every address field', () {
    const a = UpdateUserAddress(city: 'A', state: 'B', country: 'C');
    expect(a, const UpdateUserAddress(city: 'A', state: 'B', country: 'C'));
    expect(
      a,
      isNot(
        const UpdateUserAddress(
          city: 'A',
          state: 'B',
          country: 'C',
          street: 'D',
        ),
      ),
    );
  });

  test('LocationLoaded without a position still has value equality', () {
    expect(const LocationLoaded(), const LocationLoaded());
    expect(
      const LocationLoaded(address: 'Home'),
      isNot(const LocationLoaded(address: 'Work')),
    );
  });
}
