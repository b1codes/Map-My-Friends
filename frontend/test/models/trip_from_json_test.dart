import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/models/trip.dart';

/// Captured verbatim from a real `POST /api/trips/` response against the
/// running backend. These tests exist because three API-shape regressions
/// shipped undetected: the backend suite asserted whatever shape the backend
/// produced, and the Dart tests built model objects directly, so neither side
/// ever checked they agreed. Parsing a recorded server payload is what closes
/// that gap — if the backend contract drifts, this fails.
const String realTripResponse = r'''
{
        "id": "trip-1",
        "name": "Fixture",
        "date": "2026-08-01",
        "start_date": "2026-08-01",
        "end_date": "2026-08-01",
        "status": "DRAFT",
        "user": "fixture",
        "stops": [
          {
            "id": "stop-1",
            "trip": "trip-1",
            "sequence_order": 0,
            "location": {
              "type": "Point",
              "coordinates": [
                -87.6298,
                41.8781
              ]
            },
            "people": [],
            "airport": null,
            "station": null,
            "snapshot_address": "",
            "snapshot_metadata": {}
          },
          {
            "id": "stop-2",
            "trip": "trip-1",
            "sequence_order": 1,
            "location": {
              "type": "Point",
              "coordinates": [
                -0.1278,
                51.5074
              ]
            },
            "people": [],
            "airport": null,
            "station": null,
            "snapshot_address": "",
            "snapshot_metadata": {}
          }
        ],
        "legs": [
          {
            "id": "leg-1",
            "trip": "trip-1",
            "departure_stop": "stop-1",
            "arrival_stop": "stop-2",
            "departure_time": null,
            "arrival_time": null,
            "transport_type": "CAR",
            "booking_reference": "",
            "ticket_data": {}
          }
        ]
      }
''';

void main() {
  group('Trip.fromJson against a real backend payload', () {
    late Map<String, dynamic> json;

    setUp(() {
      json = jsonDecode(realTripResponse) as Map<String, dynamic>;
    });

    test('parses without throwing', () {
      expect(() => Trip.fromJson(json), returnsNormally);
    });

    test('parses nested stops and legs', () {
      final trip = Trip.fromJson(json);
      expect(trip.stops, hasLength(2));
      expect(trip.legs, hasLength(1));
    });

    test('reads stop coordinates as [lng, lat]', () {
      final trip = Trip.fromJson(json);
      // Chicago: lat 41.8781, lng -87.6298. Reversed order would silently
      // place this stop in the wrong hemisphere.
      expect(trip.stops.first.location.latitude, closeTo(41.8781, 0.0001));
      expect(trip.stops.first.location.longitude, closeTo(-87.6298, 0.0001));
    });

    test('keeps stops in sequence order', () {
      final trip = Trip.fromJson(json);
      final orders = trip.stops.map((s) => s.sequenceOrder).toList();
      expect(orders, orderedEquals(<int>[0, 1]));
    });

    test('parses document IDs as strings', () {
      final trip = Trip.fromJson(json);
      expect(trip.id, isA<String>());
      expect(trip.stops.first.id, isA<String>());
      expect(trip.legs.first.id, isA<String>());
      expect(trip.legs.first.departureStopId, isA<String>());
    });

    test('throws if stops is missing entirely', () {
      // Trip.fromJson does `json['stops'] as List` with no null guard, so a
      // flat trip payload is a hard failure, not a degraded one. This asserts
      // the sharp edge that made the regression severe.
      json.remove('stops');
      expect(() => Trip.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('round-trips a stop back to the wire shape', () {
      final trip = Trip.fromJson(json);
      final wire = trip.stops.first.toJson();
      final location = wire['location'] as Map<String, dynamic>;
      expect(location['type'], 'Point');
      expect(
        (location['coordinates'] as List).cast<double>(),
        orderedEquals(<double>[-87.6298, 41.8781]),
      );
    });
  });
}
