import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/models/person.dart';

void main() {
  group('Person Model Serialization Fix', () {
    test('toJson should use "tag" key instead of "relationship_tag"', () {
      final person = Person(
        id: '1',
        firstName: 'John',
        lastName: 'Doe',
        relationshipTag: 'FRIEND',
        city: 'NY',
        state: 'NY',
        country: 'USA',
      );

      final json = person.toJson();

      expect(
        json.containsKey('tag'),
        isTrue,
        reason: 'JSON should contain key "tag"',
      );
      expect(
        json.containsKey('relationship_tag'),
        isFalse,
        reason: 'JSON should NOT contain key "relationship_tag"',
      );
      expect(json['tag'], 'FRIEND');
    });

    test('fromJson should populate from "tag" key', () {
      final json = {
        'id': '1',
        'first_name': 'Jane',
        'last_name': 'Doe',
        'tag': 'FAMILY',
        'city': 'LA',
        'state': 'CA',
        'country': 'USA',
      };

      final person = Person.fromJson(json);

      expect(person.relationshipTag, 'FAMILY');
    });
  });

  final airportDetail = {
    'id': 7,
    'geometry': {
      'type': 'Point',
      'coordinates': [-87.9048, 41.9786],
    },
    'properties': {
      'name': "O'Hare",
      'iata_code': 'ORD',
      'airport_type': 'large_airport',
    },
  };
  final stationDetail = {
    'id': 9,
    'geometry': {
      'type': 'Point',
      'coordinates': [-87.64, 41.8789],
    },
    'properties': {'name': 'Union Station', 'osm_id': 1},
  };

  group('Person.fromJson', () {
    test('reads every field from the flat payload', () {
      final p = Person.fromJson({
        'id': 'p1',
        'first_name': 'Ana',
        'last_name': 'Lee',
        'tag': 'FRIEND',
        'city': 'Chicago',
        'state': 'IL',
        'country': 'USA',
        'street': '1 Main St',
        'birthday': '1990-05-17',
        'phone_number': '+15555550100',
        'latitude': 41,
        'longitude': -87.5,
        'profile_image': 'https://cdn/ana.png',
        'timezone': 'America/Chicago',
        'pin_color': '#00FF00',
        'pin_style': 'circle',
        'pin_icon_type': 'emoji',
        'pin_emoji': '🎸',
        'preferred_airport': 7,
        'preferred_station': 9,
        'preferred_airport_detail': airportDetail,
        'preferred_station_detail': stationDetail,
        'contact_cadence_days': 21.0,
        'last_contacted_at': '2026-07-20T15:00:00Z',
        'last_contact_channel': 'CALL',
      });
      expect(p.id, 'p1');
      expect(p.street, '1 Main St');
      expect(p.birthday, DateTime(1990, 5, 17));
      expect(p.phoneNumber, '+15555550100');
      expect(p.latitude, 41.0);
      expect(p.longitude, -87.5);
      expect(p.profileImageUrl, 'https://cdn/ana.png');
      expect(p.timezone, 'America/Chicago');
      expect(p.pinColor, '#00FF00');
      expect(p.pinStyle, 'circle');
      expect(p.pinIconType, 'emoji');
      expect(p.pinEmoji, '🎸');
      expect(p.preferredAirportId, '7');
      expect(p.preferredStationId, '9');
      expect(p.preferredAirport!.iataCode, 'ORD');
      expect(p.preferredAirport!.latitude, 41.9786);
      expect(p.preferredStation!.name, 'Union Station');
      expect(p.contactCadenceDays, 21);
      expect(p.lastContactedAt, DateTime.utc(2026, 7, 20, 15).toLocal());
      expect(p.lastContactedAt!.isUtc, isFalse);
      expect(p.lastContactChannel, 'CALL');
    });

    test('applies pin defaults and leaves optional fields null', () {
      final p = Person.fromJson({
        'id': 'p2',
        'first_name': 'Ben',
        'last_name': 'Ng',
        'tag': 'FAMILY',
        'city': 'LA',
        'state': 'CA',
        'country': 'USA',
      });
      expect(p.pinColor, '#F44336');
      expect(p.pinStyle, 'teardrop');
      expect(p.pinIconType, 'none');
      expect(p.birthday, isNull);
      expect(p.latitude, isNull);
      expect(p.longitude, isNull);
      expect(p.preferredAirport, isNull);
      expect(p.preferredStation, isNull);
      expect(p.preferredAirportId, isNull);
      expect(p.contactCadenceDays, isNull);
      expect(p.lastContactedAt, isNull);
    });
  });

  group('Person.fromGeoJson', () {
    Map<String, dynamic> feature({Object? geometry}) => {
      'id': 12,
      'geometry': geometry,
      'properties': {
        'first_name': 'Cy',
        'last_name': 'Ro',
        'tag': 'FRIEND',
        'city': 'London',
        'state': '',
        'country': 'GB',
        'street': 'Baker St',
        'birthday': '1985-12-01',
        'phone_number': '123',
        'profile_image': 'img',
        'timezone': 'Europe/London',
        'pin_color': '#111111',
        'pin_style': 'square',
        'pin_icon_type': 'initials',
        'pin_emoji': null,
        'preferred_airport': 'apt-1',
        'preferred_station': 'stn-1',
        'preferred_airport_detail': airportDetail,
        'preferred_station_detail': stationDetail,
        'contact_cadence_days': 10,
        'last_contacted_at': '2026-07-01T00:00:00Z',
        'last_contact_channel': 'VIDEO',
      },
    };

    test('reads properties, stringifies the id and flips [lng, lat]', () {
      final p = Person.fromGeoJson(
        feature(
          geometry: {
            'type': 'Point',
            'coordinates': [-0.1585, 51.5237],
          },
        ),
      );
      expect(p.id, '12');
      expect(p.firstName, 'Cy');
      expect(p.street, 'Baker St');
      expect(p.birthday, DateTime(1985, 12, 1));
      expect(p.phoneNumber, '123');
      expect(p.latitude, 51.5237);
      expect(p.longitude, -0.1585);
      expect(p.profileImageUrl, 'img');
      expect(p.timezone, 'Europe/London');
      expect(p.pinColor, '#111111');
      expect(p.pinStyle, 'square');
      expect(p.pinIconType, 'initials');
      expect(p.pinEmoji, isNull);
      expect(p.preferredAirportId, 'apt-1');
      expect(p.preferredStationId, 'stn-1');
      expect(p.preferredAirport!.iataCode, 'ORD');
      expect(p.preferredStation!.osmId, 1);
      expect(p.contactCadenceDays, 10);
      expect(p.lastContactedAt, DateTime.utc(2026, 7, 1).toLocal());
      expect(p.lastContactChannel, 'VIDEO');
    });

    test('leaves coordinates null when there is no geometry', () {
      final p = Person.fromGeoJson(feature());
      expect(p.latitude, isNull);
      expect(p.longitude, isNull);
    });

    test('applies pin defaults when the properties omit them', () {
      final p = Person.fromGeoJson({
        'id': 'x',
        'properties': {
          'first_name': 'A',
          'last_name': 'B',
          'tag': 'FRIEND',
          'city': 'C',
          'state': 'S',
          'country': 'X',
        },
      });
      expect(p.pinColor, '#F44336');
      expect(p.pinStyle, 'teardrop');
      expect(p.pinIconType, 'none');
      expect(p.birthday, isNull);
      expect(p.preferredAirport, isNull);
      expect(p.lastContactedAt, isNull);
    });
  });

  group('Person.toJson', () {
    Person minimal() => Person(
      id: '1',
      firstName: 'A',
      lastName: 'B',
      relationshipTag: 'FRIEND',
      city: 'C',
      state: 'S',
      country: 'X',
    );

    test('sends only the required fields and pin defaults when empty', () {
      expect(minimal().toJson(), {
        'first_name': 'A',
        'last_name': 'B',
        'tag': 'FRIEND',
        'city': 'C',
        'state': 'S',
        'country': 'X',
        'pin_color': '#F44336',
        'pin_style': 'teardrop',
        'pin_icon_type': 'none',
      });
    });

    test('includes optional fields that are set, cadence as a string', () {
      final json = minimal()
          .copyWith(
            street: '1 Main',
            birthday: DateTime(1990, 5, 17),
            phoneNumber: '555',
            pinEmoji: '🙂',
            preferredAirportId: 'apt',
            preferredStationId: 'stn',
            contactCadenceDays: 14,
            lastContactedAt: DateTime(2026, 1, 1),
            lastContactChannel: 'CALL',
            latitude: 1,
            longitude: 2,
          )
          .toJson();
      expect(json['street'], '1 Main');
      expect(json['birthday'], '1990-05-17T00:00:00.000');
      expect(json['phone_number'], '555');
      expect(json['pin_emoji'], '🙂');
      expect(json['preferred_airport'], 'apt');
      expect(json['preferred_station'], 'stn');
      expect(json['contact_cadence_days'], '14');
      // Server-derived and location fields are never sent back.
      expect(json.containsKey('last_contacted_at'), isFalse);
      expect(json.containsKey('last_contact_channel'), isFalse);
      expect(json.containsKey('latitude'), isFalse);
      expect(json.containsKey('id'), isFalse);
    });
  });

  test('copyWith replaces every field it is given and keeps the rest', () {
    final base = Person(
      id: '1',
      firstName: 'A',
      lastName: 'B',
      relationshipTag: 'FRIEND',
      city: 'C',
      state: 'S',
      country: 'X',
      timezone: 'UTC',
    );
    expect(base.copyWith().timezone, 'UTC');
    final changed = base.copyWith(
      id: '2',
      firstName: 'A2',
      lastName: 'B2',
      relationshipTag: 'FAMILY',
      city: 'C2',
      state: 'S2',
      country: 'X2',
      profileImageUrl: 'img',
      timezone: 'Europe/Paris',
      pinColor: '#000000',
      pinStyle: 'circle',
      pinIconType: 'emoji',
    );
    expect(changed.id, '2');
    expect(changed.firstName, 'A2');
    expect(changed.lastName, 'B2');
    expect(changed.relationshipTag, 'FAMILY');
    expect(changed.city, 'C2');
    expect(changed.state, 'S2');
    expect(changed.country, 'X2');
    expect(changed.profileImageUrl, 'img');
    expect(changed.timezone, 'Europe/Paris');
    expect(changed.pinColor, '#000000');
    expect(changed.pinStyle, 'circle');
    expect(changed.pinIconType, 'emoji');
  });
}
