import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/models/contact_log.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/services/api_config.dart';
import 'package:map_my_friends/services/api_service.dart';

import '../helpers/fake_http_adapter.dart';
import 'service_test_support.dart';

Map<String, dynamic> personFeature(String id, {String first = 'Ada'}) => {
  'type': 'Feature',
  'id': id,
  'geometry': {
    'type': 'Point',
    'coordinates': [-0.1276, 51.5072],
  },
  'properties': {
    'first_name': first,
    'last_name': 'Lovelace',
    'tag': 'Friend',
    'city': 'London',
    'state': 'England',
    'country': 'UK',
  },
};

Map<String, dynamic> personJson(String id) => {
  'id': id,
  'first_name': 'Grace',
  'last_name': 'Hopper',
  'tag': 'Family',
  'city': 'New York',
  'state': 'NY',
  'country': 'USA',
  'latitude': 40.7,
  'longitude': -74.0,
};

Map<String, dynamic> contactLogJson(String id) => {
  'id': id,
  'person': 'p1',
  'channel': 'CALL',
  'contacted_at': '2026-01-02T10:00:00Z',
  'note': 'caught up',
};

Map<String, dynamic> tripJson(String id, {String name = 'Road trip'}) => {
  'id': id,
  'name': name,
  'date': '2026-05-01',
  'status': 'BOOKED',
  'stops': [
    {
      'id': 's1',
      'sequence_order': 0,
      'location': {
        'type': 'Point',
        'coordinates': [2.35, 48.85],
      },
    },
  ],
  'legs': [],
};

Map<String, dynamic> airportFeature(int id) => {
  'type': 'Feature',
  'id': id,
  'geometry': {
    'type': 'Point',
    'coordinates': [-0.4543, 51.47],
  },
  'properties': {
    'name': 'Heathrow',
    'iata_code': 'LHR',
    'airport_type': 'large_airport',
    'city': 'London',
    'country': 'GB',
    'distance_km': 23.5,
  },
};

Map<String, dynamic> stationFeature(int id) => {
  'type': 'Feature',
  'id': id,
  'geometry': {
    'type': 'Point',
    'coordinates': [-0.1233, 51.5320],
  },
  'properties': {
    'name': 'King\'s Cross',
    'osm_id': 42,
    'station_type': 'train_station',
    'distance_km': 1.2,
  },
};

final person = Person(
  id: 'p1',
  firstName: 'Ada',
  lastName: 'Lovelace',
  relationshipTag: 'Friend',
  city: 'London',
  state: 'England',
  country: 'UK',
);

/// FormData fields as a map, for readable assertions.
Map<String, String> fieldsOf(RequestOptions request) => {
  for (final entry in (request.data as FormData).fields) entry.key: entry.value,
};

void main() {
  late FakeHttpAdapter api;
  late FakeHttpAdapter authBackend;
  late ApiService service;

  setUp(() {
    seedTokens(access: 'tok', refresh: 'ref', username: 'ada');
    api = FakeHttpAdapter();
    authBackend = FakeHttpAdapter();
    service = ApiService.forTesting(
      dio: fakeDio(api),
      authService: authServiceOn(authBackend),
    );
  });

  test('the app-wide instance is a singleton on the configured backend', () {
    final shared = ApiService();

    expect(ApiService(), same(shared));
    expect(shared.dio.options.baseUrl, ApiConfig.baseUrl);
    expect(shared.dio.options.connectTimeout, const Duration(seconds: 5));
    expect(shared.dio.options.receiveTimeout, const Duration(seconds: 3));
  });

  test('exposes the Dio it was built with', () {
    expect(service.dio.httpClientAdapter, same(api));
  });

  group('auth interceptor', () {
    test('attaches the stored access token as a Bearer header', () async {
      api.reply('GET', 'people/', 200, <Object>[]);

      await service.getPeople();

      expect(authHeaderOf(api.requests.single), 'Bearer tok');
    });

    test('sends no Authorization header when no token is stored', () async {
      seedTokens();
      api.reply('GET', 'people/', 200, <Object>[]);

      await service.getPeople();

      expect(api.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'on a 401, refreshes the token and retries with the new one',
      () async {
        // The retry reuses the same RequestOptions, so record each header as
        // it is sent rather than reading the mutated objects afterwards.
        final sentHeaders = <String?>[];
        api.on('GET', 'people/', (r) {
          sentHeaders.add(authHeaderOf(r));
          return const FakeResponse(401, {'detail': 'expired'});
        });
        api.on('GET', 'people/', (r) {
          sentHeaders.add(authHeaderOf(r));
          return FakeResponse(200, [personJson('p1')]);
        });
        authBackend.reply('POST', 'user/auth/token/refresh/', 200, {
          'access': 'fresh',
        });

        final people = await service.getPeople();

        expect(people.single.id, 'p1');
        expect(sentHeaders, ['Bearer tok', 'Bearer fresh']);
        expect(
          authBackend
              .requestsTo('POST', 'user/auth/token/refresh/')
              .single
              .data,
          {'refresh': 'ref'},
        );
        expect((await storedValues())[accessKey], 'fresh');
      },
    );

    test('propagates the 401 and logs out when the refresh fails', () async {
      api.reply('GET', 'people/', 401, {'detail': 'expired'});
      authBackend.reply('POST', 'user/auth/token/refresh/', 401);

      await expectLater(
        service.getPeople(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(
              startsWith('Exception: Failed to load people: '),
              contains('401'),
            ),
          ),
        ),
      );
      expect(api.requests, hasLength(1));
      expect(await storedValues(), isEmpty);
    });

    test('does not try to refresh on non-401 errors', () async {
      api.reply('GET', 'trips/', 500);

      await expectLater(service.getTrips(), throwsA(isA<Exception>()));
      expect(authBackend.requests, isEmpty);
    });
  });

  group('getPeople', () {
    test('parses a GeoJSON FeatureCollection', () async {
      api.reply('GET', 'people/', 200, {
        'type': 'FeatureCollection',
        'features': [personFeature('p1'), personFeature('p2', first: 'Bob')],
      });

      final people = await service.getPeople();

      expect(people.map((p) => p.id), ['p1', 'p2']);
      expect(people.first.firstName, 'Ada');
      expect(people.first.latitude, 51.5072);
      expect(people.first.longitude, -0.1276);
      expect(people.last.firstName, 'Bob');
      expect(api.requests.single.method, 'GET');
    });

    test('parses a bare list of people', () async {
      api.reply('GET', 'people/', 200, [personJson('p9')]);

      final people = await service.getPeople();

      expect(people.single.id, 'p9');
      expect(people.single.firstName, 'Grace');
      expect(people.single.latitude, 40.7);
    });

    test('rejects an unexpected response shape', () async {
      api.reply('GET', 'people/', 200, {'type': 'Feature'});

      await expectLater(
        service.getPeople(),
        throwsA(
          exceptionWith(
            'Failed to load people: Exception: Unexpected response format',
          ),
        ),
      );
    });

    test('rejects a non-200 success status', () async {
      api.reply('GET', 'people/', 204);

      await expectLater(
        service.getPeople(),
        throwsA(
          exceptionWith(
            'Failed to load people: Exception: Failed to load people',
          ),
        ),
      );
    });

    test('wraps an HTTP error', () async {
      api.reply('GET', 'people/', 500, {'detail': 'boom'});

      await expectLater(
        service.getPeople(),
        throwsA(exceptionStartingWith('Failed to load people: DioException')),
      );
    });
  });

  group('addPerson', () {
    test('posts the person as multipart fields and parses the reply', () async {
      api.reply('POST', 'people/', 201, personFeature('new-id'));

      final created = await service.addPerson(person);

      expect(created.id, 'new-id');
      final request = api.requestsTo('POST', 'people/').single;
      expect(authHeaderOf(request), 'Bearer tok');
      expect(fieldsOf(request), {
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'tag': 'Friend',
        'city': 'London',
        'state': 'England',
        'country': 'UK',
        'pin_color': '#F44336',
        'pin_style': 'teardrop',
        'pin_icon_type': 'none',
      });
      expect((request.data as FormData).files, isEmpty);
    });

    test('sends optional fields only when they are set', () async {
      api.reply('POST', 'people/', 201, personFeature('new-id'));

      await service.addPerson(
        person.copyWith(
          street: '12 Baker St',
          birthday: DateTime(1990, 4, 5),
          phoneNumber: '+44 1',
          pinEmoji: '🎉',
          preferredAirportId: '7',
          preferredStationId: '8',
          contactCadenceDays: 30,
        ),
      );

      final fields = fieldsOf(api.requests.single);
      expect(fields['street'], '12 Baker St');
      expect(fields['birthday'], '1990-04-05T00:00:00.000');
      expect(fields['phone_number'], '+44 1');
      expect(fields['pin_emoji'], '🎉');
      expect(fields['preferred_airport'], '7');
      expect(fields['preferred_station'], '8');
      expect(fields['contact_cadence_days'], '30');
      expect(fields.values, isNot(contains('null')));
    });

    test('attaches raw image bytes as profile_image', () async {
      api.reply('POST', 'people/', 201, personFeature('new-id'));
      final bytes = Uint8List.fromList([9, 8, 7]);

      await service.addPerson(person, imageBytes: bytes);

      final part = (api.requests.single.data as FormData).files.single;
      expect(part.key, 'profile_image');
      expect(part.value.filename, 'person_image.png');
      expect(part.value.contentType.toString(), 'image/png');
      expect(part.value.length, 3);
    });

    test('reads the bytes and name from an XFile', () async {
      api.reply('POST', 'people/', 201, personFeature('new-id'));
      final file = XFile.fromData(
        Uint8List.fromList([1, 2, 3, 4, 5]),
        path: 'picked/avatar.png',
      );

      await service.addPerson(person, profileImage: file);

      final part = (api.requests.single.data as FormData).files.single;
      expect(part.key, 'profile_image');
      expect(part.value.filename, 'avatar.png');
      expect(part.value.length, 5);
    });

    test('prefers explicit bytes over the XFile contents', () async {
      api.reply('POST', 'people/', 201, personFeature('new-id'));
      final file = XFile.fromData(
        Uint8List.fromList([1, 2, 3, 4, 5]),
        path: 'picked/original.png',
      );

      await service.addPerson(
        person,
        profileImage: file,
        imageBytes: Uint8List.fromList([1, 2]),
      );

      final part = (api.requests.single.data as FormData).files.single;
      expect(part.value.length, 2);
      expect(part.value.filename, 'original.png');
    });

    test('rejects a non-201 success status', () async {
      api.reply('POST', 'people/', 200, personFeature('x'));

      await expectLater(
        service.addPerson(person),
        throwsA(
          exceptionWith(
            'Failed to add person: Exception: Failed to add person',
          ),
        ),
      );
    });

    test('wraps an HTTP error', () async {
      api.reply('POST', 'people/', 400, {
        'city': ['required'],
      });

      await expectLater(
        service.addPerson(person),
        throwsA(exceptionStartingWith('Failed to add person: DioException')),
      );
    });
  });

  group('updatePerson', () {
    test('patches people/<id>/ with multipart fields', () async {
      api.reply('PATCH', 'people/p1/', 200, personFeature('p1', first: 'Ava'));

      final updated = await service.updatePerson(person);

      expect(updated.firstName, 'Ava');
      final request = api.requestsTo('PATCH', 'people/p1/').single;
      expect(fieldsOf(request)['first_name'], 'Ada');
      expect(fieldsOf(request).containsKey('street'), isFalse);
      expect((request.data as FormData).files, isEmpty);
    });

    test('attaches an XFile image', () async {
      api.reply('PATCH', 'people/p1/', 200, personFeature('p1'));
      final file = XFile.fromData(
        Uint8List.fromList([4, 4]),
        path: 'x/new.png',
      );

      await service.updatePerson(person, profileImage: file);

      final part = (api.requests.single.data as FormData).files.single;
      expect(part.key, 'profile_image');
      expect(part.value.filename, 'new.png');
    });

    test('attaches raw bytes with the default filename', () async {
      api.reply('PATCH', 'people/p1/', 200, personFeature('p1'));

      await service.updatePerson(person, imageBytes: Uint8List.fromList([1]));

      final part = (api.requests.single.data as FormData).files.single;
      expect(part.value.filename, 'person_image.png');
    });

    test('rejects a non-200 success status', () async {
      api.reply('PATCH', 'people/p1/', 202, personFeature('p1'));

      await expectLater(
        service.updatePerson(person),
        throwsA(
          exceptionWith(
            'Failed to update person: Exception: Failed to update person',
          ),
        ),
      );
    });

    test('wraps an HTTP error', () async {
      api.reply('PATCH', 'people/p1/', 404);

      await expectLater(
        service.updatePerson(person),
        throwsA(exceptionStartingWith('Failed to update person: DioException')),
      );
    });
  });

  group('deletePerson', () {
    test('deletes people/<id>/', () async {
      api.reply('DELETE', 'people/p1/', 204);

      await service.deletePerson('p1');

      expect(api.requestsTo('DELETE', 'people/p1/'), hasLength(1));
    });

    test('rejects a status other than 204', () async {
      api.reply('DELETE', 'people/p1/', 200);

      await expectLater(
        service.deletePerson('p1'),
        throwsA(
          exceptionWith(
            'Failed to delete person: Exception: Failed to delete person',
          ),
        ),
      );
    });

    test('wraps an HTTP error', () async {
      api.reply('DELETE', 'people/p1/', 403);

      await expectLater(
        service.deletePerson('p1'),
        throwsA(exceptionStartingWith('Failed to delete person: DioException')),
      );
    });
  });

  group('getContactLogs', () {
    test(
      'parses a paginated response and sends no filter by default',
      () async {
        api.reply('GET', 'contact-logs/', 200, {
          'count': 2,
          'results': [contactLogJson('c1'), contactLogJson('c2')],
        });

        final logs = await service.getContactLogs();

        expect(logs.map((l) => l.id), ['c1', 'c2']);
        expect(logs.first.channel, ContactChannel.call);
        expect(logs.first.note, 'caught up');
        expect(api.requests.single.queryParameters, isEmpty);
      },
    );

    test('parses a bare list and filters by person', () async {
      api.reply('GET', 'contact-logs/', 200, [contactLogJson('c3')]);

      final logs = await service.getContactLogs(personId: 'p1');

      expect(logs.single.id, 'c3');
      expect(logs.single.personId, 'p1');
      expect(api.requests.single.queryParameters, {'person': 'p1'});
    });

    test('rejects a non-200 success status', () async {
      api.reply('GET', 'contact-logs/', 204);

      await expectLater(
        service.getContactLogs(),
        throwsA(
          exceptionWith(
            'Failed to load contact logs: Exception: Failed to load contact logs',
          ),
        ),
      );
    });

    test('wraps an HTTP error', () async {
      api.reply('GET', 'contact-logs/', 500);

      await expectLater(
        service.getContactLogs(),
        throwsA(exceptionStartingWith('Failed to load contact logs: ')),
      );
    });
  });

  group('addContactLog', () {
    final log = ContactLog(
      id: '',
      personId: 'p1',
      channel: ContactChannel.video,
      contactedAt: DateTime.utc(2026, 3, 4, 12),
      note: 'birthday',
    );

    test('posts the create payload and parses the reply', () async {
      api.reply('POST', 'contact-logs/', 201, {
        ...contactLogJson('c9'),
        'channel': 'VIDEO',
      });

      final created = await service.addContactLog(log);

      expect(created.id, 'c9');
      expect(created.channel, ContactChannel.video);
      expect(api.requestsTo('POST', 'contact-logs/').single.data, {
        'person': 'p1',
        'channel': 'VIDEO',
        'contacted_at': '2026-03-04T12:00:00.000Z',
        'note': 'birthday',
      });
    });

    test('rejects a non-201 success status', () async {
      api.reply('POST', 'contact-logs/', 200, contactLogJson('c9'));

      await expectLater(
        service.addContactLog(log),
        throwsA(
          exceptionWith(
            'Failed to log contact: Exception: Failed to log contact',
          ),
        ),
      );
    });

    test('wraps an HTTP error', () async {
      api.reply('POST', 'contact-logs/', 400);

      await expectLater(
        service.addContactLog(log),
        throwsA(exceptionStartingWith('Failed to log contact: DioException')),
      );
    });
  });

  group('trips', () {
    final trip = Trip(
      id: 't1',
      name: 'Road trip',
      date: DateTime(2026, 5, 1),
      stops: const [TripStop(location: LatLng(48.85, 2.35), sequenceOrder: 0)],
    );

    group('getTrips', () {
      test('parses a paginated response', () async {
        api.reply('GET', 'trips/', 200, {
          'results': [tripJson('t1'), tripJson('t2', name: 'Weekend')],
        });

        final trips = await service.getTrips();

        expect(trips.map((t) => t.id), ['t1', 't2']);
        expect(trips.last.name, 'Weekend');
        expect(trips.first.status, TripStatus.booked);
        expect(trips.first.stops.single.location, const LatLng(48.85, 2.35));
      });

      test('parses a bare list', () async {
        api.reply('GET', 'trips/', 200, [tripJson('t3')]);

        expect((await service.getTrips()).single.id, 't3');
      });

      test('rejects a non-200 success status', () async {
        api.reply('GET', 'trips/', 204);

        await expectLater(
          service.getTrips(),
          throwsA(
            exceptionWith(
              'Failed to load trips: Exception: Failed to load trips',
            ),
          ),
        );
      });

      test('wraps an HTTP error', () async {
        api.reply('GET', 'trips/', 500);

        await expectLater(
          service.getTrips(),
          throwsA(exceptionStartingWith('Failed to load trips: DioException')),
        );
      });
    });

    group('createTrip', () {
      test('posts the trip JSON and parses the reply', () async {
        api.reply('POST', 'trips/', 201, tripJson('t-new'));

        final created = await service.createTrip(trip);

        expect(created.id, 't-new');
        expect(api.requestsTo('POST', 'trips/').single.data, trip.toJson());
      });

      test('rejects a non-201 success status', () async {
        api.reply('POST', 'trips/', 200, tripJson('t-new'));

        await expectLater(
          service.createTrip(trip),
          throwsA(
            exceptionWith(
              'Failed to create trip: Exception: Failed to create trip',
            ),
          ),
        );
      });

      test('wraps an HTTP error', () async {
        api.reply('POST', 'trips/', 400);

        await expectLater(
          service.createTrip(trip),
          throwsA(exceptionStartingWith('Failed to create trip: DioException')),
        );
      });
    });

    group('updateTrip', () {
      test('patches trips/<id>/ with the trip JSON', () async {
        api.reply('PATCH', 'trips/t1/', 200, tripJson('t1', name: 'Renamed'));

        final updated = await service.updateTrip(trip);

        expect(updated.name, 'Renamed');
        expect(api.requestsTo('PATCH', 'trips/t1/').single.data, trip.toJson());
      });

      test('requires an id and sends nothing without one', () async {
        final unsaved = Trip(name: 'Draft', date: DateTime(2026));

        await expectLater(
          service.updateTrip(unsaved),
          throwsA(
            exceptionWith(
              'Failed to update trip: Exception: Trip ID is required for update',
            ),
          ),
        );
        expect(api.requests, isEmpty);
      });

      test('rejects a non-200 success status', () async {
        api.reply('PATCH', 'trips/t1/', 201, tripJson('t1'));

        await expectLater(
          service.updateTrip(trip),
          throwsA(
            exceptionWith(
              'Failed to update trip: Exception: Failed to update trip',
            ),
          ),
        );
      });

      test('wraps an HTTP error', () async {
        api.reply('PATCH', 'trips/t1/', 409);

        await expectLater(
          service.updateTrip(trip),
          throwsA(exceptionStartingWith('Failed to update trip: DioException')),
        );
      });
    });

    group('deleteTrip', () {
      test('deletes trips/<id>/', () async {
        api.reply('DELETE', 'trips/t1/', 204);

        await service.deleteTrip('t1');

        expect(api.requestsTo('DELETE', 'trips/t1/'), hasLength(1));
      });

      test('rejects a status other than 204', () async {
        api.reply('DELETE', 'trips/t1/', 200);

        await expectLater(
          service.deleteTrip('t1'),
          throwsA(
            exceptionWith(
              'Failed to delete trip: Exception: Failed to delete trip',
            ),
          ),
        );
      });

      test('wraps an HTTP error', () async {
        api.reply('DELETE', 'trips/t1/', 404);

        await expectLater(
          service.deleteTrip('t1'),
          throwsA(exceptionStartingWith('Failed to delete trip: DioException')),
        );
      });
    });
  });

  group('getNearestAirports', () {
    test(
      'sends lat, lon and the default count of 5, parsing the features',
      () async {
        api.reply('GET', 'airports/nearest/', 200, {
          'type': 'FeatureCollection',
          'features': [airportFeature(1), airportFeature(2)],
        });

        final airports = await service.getNearestAirports(51.5, -0.12);

        expect(airports, hasLength(2));
        expect(airports.first.iataCode, 'LHR');
        expect(airports.first.latitude, 51.47);
        expect(airports.first.distanceKm, 23.5);
        expect(api.requests.single.queryParameters, {
          'lat': 51.5,
          'lon': -0.12,
          'count': 5,
        });
      },
    );

    test('passes a custom count', () async {
      api.reply('GET', 'airports/nearest/', 200, {'features': <Object>[]});

      expect(await service.getNearestAirports(1, 2, count: 2), isEmpty);
      expect(api.requests.single.queryParameters['count'], 2);
    });

    test('rejects a non-200 success status', () async {
      api.reply('GET', 'airports/nearest/', 204);

      await expectLater(
        service.getNearestAirports(1, 2),
        throwsA(exceptionStartingWith('Failed to load nearest airports: ')),
      );
    });

    test('wraps an HTTP error', () async {
      api.reply('GET', 'airports/nearest/', 400);

      await expectLater(
        service.getNearestAirports(1, 2),
        throwsA(
          exceptionStartingWith(
            'Failed to load nearest airports: DioException',
          ),
        ),
      );
    });
  });

  group('getNearestStations', () {
    test(
      'sends lat, lon and the default count of 5, parsing the features',
      () async {
        api.reply('GET', 'stations/nearest/', 200, {
          'type': 'FeatureCollection',
          'features': [stationFeature(3)],
        });

        final stations = await service.getNearestStations(51.5, -0.12);

        expect(stations.single.name, 'King\'s Cross');
        expect(stations.single.osmId, 42);
        expect(stations.single.longitude, -0.1233);
        expect(api.requests.single.queryParameters, {
          'lat': 51.5,
          'lon': -0.12,
          'count': 5,
        });
      },
    );

    test('passes a custom count', () async {
      api.reply('GET', 'stations/nearest/', 200, {'features': <Object>[]});

      await service.getNearestStations(1, 2, count: 9);
      expect(api.requests.single.queryParameters['count'], 9);
    });

    test('rejects a non-200 success status', () async {
      api.reply('GET', 'stations/nearest/', 204);

      await expectLater(
        service.getNearestStations(1, 2),
        throwsA(exceptionStartingWith('Failed to load nearest stations: ')),
      );
    });

    test('wraps an HTTP error', () async {
      api.reply('GET', 'stations/nearest/', 503);

      await expectLater(
        service.getNearestStations(1, 2),
        throwsA(
          exceptionStartingWith(
            'Failed to load nearest stations: DioException',
          ),
        ),
      );
    });
  });
}
