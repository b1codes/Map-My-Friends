import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/models/trip.dart';

void main() {
  group('TripStop Model', () {
    test('copyWith should update sequenceOrder', () {
      final stop = TripStop(
        id: '1',
        location: const LatLng(0, 0),
        sequenceOrder: 1,
      );

      final updatedStop = stop.copyWith(sequenceOrder: 2);

      expect(updatedStop.id, '1');
      expect(updatedStop.location, const LatLng(0, 0));
      expect(updatedStop.sequenceOrder, 2);
    });

    test('copyWith without arguments should return exact copy', () {
      final stop = TripStop(
        id: '1',
        location: const LatLng(0, 0),
        sequenceOrder: 1,
      );

      final updatedStop = stop.copyWith();

      expect(updatedStop.id, '1');
      expect(updatedStop.location, const LatLng(0, 0));
      expect(updatedStop.sequenceOrder, 1);
    });
  });

  Map<String, dynamic> personJson(String id) => {
    'id': id,
    'first_name': 'F$id',
    'last_name': 'L',
    'tag': 'FRIEND',
    'city': 'C',
    'state': 'S',
    'country': 'X',
  };

  Map<String, dynamic> stopJson([Map<String, dynamic> extra = const {}]) => {
    'id': 5,
    'sequence_order': 2,
    'location': {
      'type': 'Point',
      'coordinates': [-87.6298, 41.8781],
    },
    ...extra,
  };

  group('TripStatus.fromString', () {
    test('maps API values and defaults unknown ones to draft', () {
      expect(TripStatus.fromString('DRAFT'), TripStatus.draft);
      expect(TripStatus.fromString('BOOKED'), TripStatus.booked);
      expect(TripStatus.fromString('CANCELLED'), TripStatus.cancelled);
      expect(TripStatus.fromString('ARCHIVED'), TripStatus.draft);
    });
  });

  group('TripStop.fromJson', () {
    test('reads people, hubs and snapshots', () {
      final stop = TripStop.fromJson(
        stopJson({
          'people_detail': [personJson('a'), personJson('b')],
          'airport_detail': {
            'id': 7,
            'geometry': {
              'type': 'Point',
              'coordinates': [-87.9, 41.97],
            },
            'properties': {
              'name': "O'Hare",
              'iata_code': 'ORD',
              'airport_type': 'large_airport',
            },
          },
          'station_detail': {
            'id': 9,
            'geometry': {
              'type': 'Point',
              'coordinates': [-87.64, 41.87],
            },
            'properties': {'name': 'Union', 'osm_id': 1},
          },
          'snapshot_address': 'Chicago, IL',
          'snapshot_metadata': {'note': 'hi'},
        }),
      );
      expect(stop.id, '5');
      expect(stop.sequenceOrder, 2);
      expect(stop.people.map((p) => p.id), ['a', 'b']);
      expect(stop.airport!.iataCode, 'ORD');
      expect(stop.station!.name, 'Union');
      expect(stop.location, const LatLng(41.8781, -87.6298));
      expect(stop.snapshotAddress, 'Chicago, IL');
      expect(stop.snapshotMetadata, {'note': 'hi'});
    });

    // Regression: coordinates were cast `as double`, but JSON has one number
    // type and Dart decodes `41` as an int. The web build serialises 41.0 as
    // `41`, so one whole-degree stop made the whole trips list fail to load.
    test('accepts whole-number coordinates', () {
      final stop = TripStop.fromJson(
        jsonDecode(
              '{"sequence_order": 0, '
              '"location": {"type": "Point", "coordinates": [-87, 41]}}',
            )
            as Map<String, dynamic>,
      );
      expect(stop.location, const LatLng(41.0, -87.0));
    });

    test('falls back to the legacy single person_detail', () {
      final stop = TripStop.fromJson(
        stopJson({'person_detail': personJson('legacy')}),
      );
      expect(stop.people.single.id, 'legacy');
    });

    test('has no people or hubs when the details are absent', () {
      final stop = TripStop.fromJson(stopJson());
      expect(stop.people, isEmpty);
      expect(stop.airport, isNull);
      expect(stop.station, isNull);
      expect(stop.snapshotAddress, isNull);
    });
  });

  group('TripStop.toJson', () {
    test('sends ids, [lng, lat] and snapshots', () {
      final stop = TripStop.fromJson(
        stopJson({
          'people_detail': [personJson('a')],
          'snapshot_address': 'Addr',
        }),
      );
      expect(stop.toJson(), {
        'people': ['a'],
        'airport': null,
        'station': null,
        'sequence_order': 2,
        'location': {
          'type': 'Point',
          'coordinates': [-87.6298, 41.8781],
        },
        'snapshot_address': 'Addr',
        'snapshot_metadata': null,
      });
    });
  });

  test('TripStop.copyWith replaces each field and keeps the id', () {
    const stop = TripStop(
      id: 's',
      location: LatLng(1, 1),
      sequenceOrder: 0,
      snapshotAddress: 'old',
    );
    final changed = stop.copyWith(
      location: const LatLng(2, 2),
      snapshotAddress: 'new',
      snapshotMetadata: {'k': 'v'},
    );
    expect(changed.id, 's');
    expect(changed.location, const LatLng(2, 2));
    expect(changed.snapshotAddress, 'new');
    expect(changed.snapshotMetadata, {'k': 'v'});
    expect(stop.copyWith(), stop);
  });

  group('TripLeg', () {
    test('fromJson reads every field and stringifies ids', () {
      final leg = TripLeg.fromJson({
        'id': 3,
        'departure_stop': 1,
        'arrival_stop': 2,
        'departure_time': '2026-08-01T09:00:00.000',
        'arrival_time': '2026-08-01T11:30:00.000',
        'transport_type': 'FLIGHT',
        'booking_reference': 'ABC123',
        'ticket_data': {'seat': '12A'},
      });
      expect(leg.id, '3');
      expect(leg.departureStopId, '1');
      expect(leg.arrivalStopId, '2');
      expect(leg.departureTime, DateTime(2026, 8, 1, 9));
      expect(leg.arrivalTime, DateTime(2026, 8, 1, 11, 30));
      expect(leg.transportType, 'FLIGHT');
      expect(leg.bookingReference, 'ABC123');
      expect(leg.ticketData, {'seat': '12A'});
    });

    test('fromJson applies defaults for missing optional fields', () {
      final leg = TripLeg.fromJson({
        'departure_stop': 'a',
        'arrival_stop': 'b',
      });
      expect(leg.id, isNull);
      expect(leg.departureTime, isNull);
      expect(leg.arrivalTime, isNull);
      expect(leg.transportType, 'CAR');
      expect(leg.bookingReference, '');
      expect(leg.ticketData, isEmpty);
    });

    test('toJson omits a null id and round-trips', () {
      const unsaved = TripLeg(departureStopId: 'a', arrivalStopId: 'b');
      expect(unsaved.toJson().containsKey('id'), isFalse);
      expect(unsaved.toJson()['departure_time'], isNull);

      final saved = TripLeg(
        id: 'leg-1',
        departureStopId: 'a',
        arrivalStopId: 'b',
        departureTime: DateTime(2026, 8, 1, 9),
        transportType: 'TRAIN',
        ticketData: const {'car': 4},
      );
      final json = saved.toJson();
      expect(json['id'], 'leg-1');
      expect(json['departure_time'], '2026-08-01T09:00:00.000');
      expect(TripLeg.fromJson(json), saved);
    });

    test('copyWith keeps identity fields', () {
      const leg = TripLeg(id: 'l', departureStopId: 'a', arrivalStopId: 'b');
      final changed = leg.copyWith(
        departureTime: DateTime(2026),
        arrivalTime: DateTime(2026, 1, 2),
        transportType: 'BUS',
        bookingReference: 'R',
        ticketData: const {'x': 1},
      );
      expect(changed.id, 'l');
      expect(changed.departureStopId, 'a');
      expect(changed.arrivalStopId, 'b');
      expect(changed.arrivalTime, DateTime(2026, 1, 2));
      expect(changed.transportType, 'BUS');
      expect(changed.bookingReference, 'R');
      expect(changed.ticketData, {'x': 1});
      expect(leg.copyWith(), leg);
    });
  });

  group('Trip', () {
    test('toJson sends dates as yyyy-MM-dd and omits unset ranges', () {
      final trip = Trip(name: 'Day trip', date: DateTime(2026, 8, 1, 15, 30));
      expect(trip.toJson(), {
        'name': 'Day trip',
        'date': '2026-08-01',
        'status': 'DRAFT',
        'stops': <Object>[],
        'legs': <Object>[],
      });
    });

    test('toJson includes the range, status, stops and legs', () {
      final trip = Trip(
        name: 'Tour',
        date: DateTime(2026, 8, 1),
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 9),
        status: TripStatus.booked,
        stops: const [TripStop(location: LatLng(1, 2), sequenceOrder: 0)],
        legs: const [TripLeg(departureStopId: 'a', arrivalStopId: 'b')],
      );
      final json = trip.toJson();
      expect(json['start_date'], '2026-08-01');
      expect(json['end_date'], '2026-08-09');
      expect(json['status'], 'BOOKED');
      expect((json['stops'] as List).single['location']['coordinates'], [
        2.0,
        1.0,
      ]);
      expect((json['legs'] as List).single['departure_stop'], 'a');
    });

    test('fromJson tolerates a missing legs list and null dates', () {
      final trip = Trip.fromJson({
        'id': 77,
        'name': 'Legless',
        'date': '2026-08-01',
        'status': 'CANCELLED',
        'stops': [stopJson()],
      });
      expect(trip.id, '77');
      expect(trip.startDate, isNull);
      expect(trip.endDate, isNull);
      expect(trip.status, TripStatus.cancelled);
      expect(trip.stops, hasLength(1));
      expect(trip.legs, isEmpty);
    });

    test('copyWith replaces each field it is given', () {
      final trip = Trip(name: 'A', date: DateTime(2026));
      final changed = trip.copyWith(
        id: 'x',
        name: 'B',
        date: DateTime(2027),
        startDate: DateTime(2027, 2),
        endDate: DateTime(2027, 3),
        status: TripStatus.booked,
        stops: const [TripStop(location: LatLng(0, 0), sequenceOrder: 0)],
        legs: const [TripLeg(departureStopId: 'a', arrivalStopId: 'b')],
      );
      expect(changed.id, 'x');
      expect(changed.name, 'B');
      expect(changed.date, DateTime(2027));
      expect(changed.startDate, DateTime(2027, 2));
      expect(changed.endDate, DateTime(2027, 3));
      expect(changed.status, TripStatus.booked);
      expect(changed.stops, hasLength(1));
      expect(changed.legs, hasLength(1));
      expect(trip.copyWith(), trip);
    });
  });
}
