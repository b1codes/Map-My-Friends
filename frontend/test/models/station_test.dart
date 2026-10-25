import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/models/station.dart';

void main() {
  group('Station.fromJson (bundled asset format)', () {
    test('reads every field', () {
      final s = Station.fromJson({
        'id': 3,
        'name': 'Union Station',
        'osm_id': 7966411005,
        'station_type': 'major_station',
        'uic_ref': '8800001',
        'city': 'Chicago',
        'country': 'USA',
        'latitude': 41.8789,
        'longitude': -87.64,
        'distance_km': 2,
      });
      expect(s.id, 3);
      expect(s.name, 'Union Station');
      expect(s.osmId, 7966411005);
      expect(s.stationType, 'major_station');
      expect(s.uicRef, '8800001');
      expect(s.city, 'Chicago');
      expect(s.country, 'USA');
      expect(s.latitude, 41.8789);
      expect(s.longitude, -87.64);
      expect(s.distanceKm, 2.0);
    });

    test('defaults the type to regional_station and coordinates to 0', () {
      final s = Station.fromJson({'name': '1', 'osm_id': 1});
      expect(s.stationType, 'regional_station');
      expect(s.latitude, 0.0);
      expect(s.longitude, 0.0);
      expect(s.id, isNull);
      expect(s.uicRef, isNull);
      expect(s.distanceKm, isNull);
    });
  });

  group('Station.fromGeoJson (backend nearest endpoint)', () {
    test('reads properties and [lng, lat] coordinates', () {
      final s = Station.fromGeoJson({
        'id': 11,
        'geometry': {
          'type': 'Point',
          'coordinates': [-0.1233, 51.5308],
        },
        'properties': {
          'name': "King's Cross",
          'osm_id': 99,
          'station_type': 'major_station',
          'uic_ref': '7000001',
          'city': 'London',
          'country': 'GB',
          'distance_km': 1.25,
        },
      });
      expect(s.id, 11);
      expect(s.name, "King's Cross");
      expect(s.osmId, 99);
      expect(s.stationType, 'major_station');
      expect(s.uicRef, '7000001');
      expect(s.city, 'London');
      expect(s.country, 'GB');
      expect(s.latitude, 51.5308);
      expect(s.longitude, -0.1233);
      expect(s.distanceKm, 1.25);
    });

    test('falls back to 0,0 when the geometry has no coordinates', () {
      final s = Station.fromGeoJson({
        'geometry': {'type': 'Point'},
        'properties': {'name': 'Ghost', 'osm_id': 1},
      });
      expect(s.latitude, 0.0);
      expect(s.longitude, 0.0);
      // Unlike the asset parser, GeoJSON leaves a missing type null.
      expect(s.stationType, isNull);
      expect(s.distanceKm, isNull);
    });
  });

  test('toJson round-trips through fromJson', () {
    final original = Station(
      id: 5,
      name: 'Ogilvie',
      osmId: 102,
      stationType: 'commuter_station',
      uicRef: 'abc',
      city: 'Chicago',
      country: 'USA',
      latitude: 41.8826,
      longitude: -87.6406,
      distanceKm: 0.5,
    );
    final json = original.toJson();
    expect(json, {
      'id': 5,
      'name': 'Ogilvie',
      'osm_id': 102,
      'station_type': 'commuter_station',
      'uic_ref': 'abc',
      'city': 'Chicago',
      'country': 'USA',
      'latitude': 41.8826,
      'longitude': -87.6406,
      'distance_km': 0.5,
    });
    final back = Station.fromJson(json);
    expect(back.toJson(), json);
  });
}
