import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/models/airport.dart';

void main() {
  group('Airport.fromJson (bundled asset format)', () {
    test('reads the compact keys', () {
      final a = Airport.fromJson({
        'name': "O'Hare International",
        'iata': 'ORD',
        'type': 'large_airport',
        'city': 'Chicago',
        'country': 'US',
        'lat': 41.9786,
        'lon': -87.9048,
      });
      expect(a.name, "O'Hare International");
      expect(a.iataCode, 'ORD');
      expect(a.airportType, 'large_airport');
      expect(a.city, 'Chicago');
      expect(a.country, 'US');
      expect(a.latitude, 41.9786);
      expect(a.longitude, -87.9048);
      // The asset carries no backend id, ICAO code, continent or distance.
      expect(a.id, isNull);
      expect(a.icaoCode, isNull);
      expect(a.continent, isNull);
      expect(a.distanceKm, isNull);
    });

    test('defaults a missing city and country to empty strings', () {
      final a = Airport.fromJson({
        'name': 'Remote Strip',
        'iata': 'XXX',
        'type': 'small_airport',
        'lat': 1.5,
        'lon': 2.5,
      });
      expect(a.city, '');
      expect(a.country, '');
    });

    test('accepts integer coordinates', () {
      final a = Airport.fromJson({
        'name': 'Null Island',
        'iata': 'NUL',
        'type': 'small_airport',
        'lat': 0,
        'lon': 10,
      });
      expect(a.latitude, 0.0);
      expect(a.longitude, 10.0);
    });
  });

  group('Airport.fromGeoJson (backend nearest endpoint)', () {
    Map<String, dynamic> feature({Object? geometry = _point}) => {
      'id': 42,
      'type': 'Feature',
      'geometry': geometry,
      'properties': {
        'name': 'Heathrow',
        'iata_code': 'LHR',
        'icao_code': 'EGLL',
        'airport_type': 'large_airport',
        'city': 'London',
        'country': 'GB',
        'continent': 'EU',
        'distance_km': 23,
      },
    };

    test('reads properties and [lng, lat] coordinates', () {
      final a = Airport.fromGeoJson(feature());
      expect(a.id, 42);
      expect(a.name, 'Heathrow');
      expect(a.iataCode, 'LHR');
      expect(a.icaoCode, 'EGLL');
      expect(a.airportType, 'large_airport');
      expect(a.city, 'London');
      expect(a.country, 'GB');
      expect(a.continent, 'EU');
      expect(a.latitude, 51.47);
      expect(a.longitude, -0.4543);
      expect(a.distanceKm, 23.0);
    });

    test('falls back to 0,0 when the geometry is missing', () {
      final a = Airport.fromGeoJson(feature(geometry: null));
      expect(a.latitude, 0.0);
      expect(a.longitude, 0.0);
    });

    test('tolerates missing optional properties', () {
      final a = Airport.fromGeoJson({
        'geometry': _point,
        'properties': {
          'name': 'Tiny',
          'iata_code': 'TNY',
          'airport_type': 'small_airport',
        },
      });
      expect(a.id, isNull);
      expect(a.icaoCode, isNull);
      expect(a.city, '');
      expect(a.country, '');
      expect(a.continent, isNull);
      expect(a.distanceKm, isNull);
    });
  });
}

const _point = {
  'type': 'Point',
  'coordinates': [-0.4543, 51.47],
};
