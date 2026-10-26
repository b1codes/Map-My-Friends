// Consumer side of the app API contracts in the repo-root contracts/api/.
//
// For every interaction file, a driver below calls the real service (or bloc)
// the way the app does. The test then checks that the request it sent is
// exactly the contract's, and the driver checks what the app parsed out of
// the contract's example response. The Django provider tests replay the
// same requests against the real API and hold its responses to the same
// schema, so together the two sides cannot drift apart unnoticed.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/bloc/profile/profile_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_event.dart';
import 'package:map_my_friends/bloc/profile/profile_state.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/contact_log.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/services/airport_service.dart';
import 'package:map_my_friends/services/api_service.dart';
import 'package:map_my_friends/services/auth_service.dart';
import 'package:map_my_friends/services/station_service.dart';

import '../helpers/fake_http_adapter.dart';
import '../services/service_test_support.dart';
import 'contract_support.dart';

// Ids from contracts/api/fixtures.json.
const personId = 'Pp5ltxR4W9tpvZTZUlY7';
const contactLogId = 'MdSXYBzGfdyHp1R17jee';
const tripId = 'CPczK4heHksu4O9ODudG';
const firstStopId = 'B0HgfWm6ArmpJaNJdqGN';
const secondStopId = 'Pxxx4iCAa0bd1A6mYVzL';
const legId = 'TzgYzOtSeqrdtWScrbVF';

final Map<String, dynamic> fixtureUser =
    contractFixtures['user'] as Map<String, dynamic>;
final Uint8List png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);

/// Grace Hopper as the app holds her before saving.
Person grace({String id = '', String tag = 'FRIEND'}) => Person(
  id: id,
  firstName: 'Grace',
  lastName: 'Hopper',
  relationshipTag: tag,
  city: 'Milwaukee',
  state: 'WI',
  country: 'USA',
  street: '500 N Harbor Dr',
  birthday: DateTime(1906, 12, 9),
  phoneNumber: '+14145550100',
  pinColor: '#2196F3',
  pinStyle: 'circle',
  pinIconType: 'emoji',
  pinEmoji: '🚢',
  preferredAirportId: '2364',
  preferredStationId: '1753',
  contactCadenceDays: 14,
);

final midway = Airport(
  id: 2364,
  name: 'Chicago Midway International Airport',
  iataCode: 'MDW',
  airportType: 'large_airport',
  city: 'Chicago',
  country: 'US',
  latitude: 41.785999,
  longitude: -87.752403,
);

/// The planner's two stops: Grace, then Midway.
List<TripStop> plannedStops() => [
  TripStop(
    people: [grace(id: personId)],
    location: const LatLng(43.0389, -87.9065),
    sequenceOrder: 0,
  ),
  TripStop(
    airport: midway,
    location: const LatLng(41.785999, -87.752403),
    sequenceOrder: 1,
  ),
];

Trip plannedTrip({String? id, TripStatus status = TripStatus.draft}) => Trip(
  id: id,
  name: 'Milwaukee weekend',
  date: DateTime(2026, 11, 14),
  startDate: DateTime(2026, 11, 14),
  endDate: DateTime(2026, 11, 16),
  status: status,
  stops: plannedStops(),
);

/// Everything a driver needs: real services on a fake HTTP adapter.
class Harness {
  Harness(this.interaction);

  final Interaction interaction;
  final adapter = FakeHttpAdapter();
  late final AuthService auth = authServiceOn(adapter);
  late final ApiService api = ApiService.forTesting(
    dio: fakeDio(adapter),
    authService: auth,
  );
  late final AirportService airports = AirportService.forTesting(
    dio: fakeDio(adapter),
    authService: auth,
  );
  late final StationService stations = StationService.forTesting(
    dio: fakeDio(adapter),
    authService: auth,
  );

  /// Serves [other]'s contract response, for flows that span interactions.
  void serve(Interaction other) =>
      adapter.on(other.method, other.path, (_) => other.reply);

  Future<ProfileState> profileAfter(ProfileEvent event) async {
    final bloc = ProfileBloc(authService: auth);
    addTearDown(bloc.close);
    bloc.add(event);
    return bloc.stream.firstWhere(
      (state) => state is ProfileLoaded || state is ProfileError,
    );
  }
}

typedef Driver = Future<void> Function(Harness h);

final Map<String, Driver> drivers = {
  'auth.token': (h) async {
    final example = h.interaction.example as Map<String, dynamic>;
    final tokens = await h.auth.login('ada', fixtureUser['password'] as String);
    expect(tokens['access'], example['access']);
    expect((await storedValues())[refreshKey], example['refresh']);
  },
  'auth.token.invalid': (h) async {
    await expectLater(
      h.auth.login('ada', 'not-the-password'),
      throwsA(exceptionWith('Invalid username or password')),
    );
  },
  'auth.token.refresh': (h) async {
    final example = h.interaction.example as Map<String, dynamic>;
    expect(await h.auth.refreshAccessToken(), example['access']);
    final stored = await storedValues();
    expect(stored[accessKey], example['access']);
    // The server rotates refresh tokens; reusing the old one fails once it
    // is blacklisted, which would sign the user out at the next refresh.
    expect(stored[refreshKey], example['refresh']);
  },
  'auth.token.not_valid': (h) async {
    final refresh = apiInteractions['auth.token.refresh']!;
    final trips = apiInteractions['trips.list']!;
    h.serve(refresh);
    h.serve(trips);
    final loaded = await h.api.getTrips();
    expect(loaded.single.id, tripId);
    final retry = h.adapter.requestsTo('GET', 'trips/').last;
    expect(
      authHeaderOf(retry),
      'Bearer ${(refresh.example as Map<String, dynamic>)['access']}',
    );
  },
  'auth.register': (h) async {
    await h.auth.register(
      username: 'ada',
      email: 'ada@example.com',
      password: fixtureUser['password'] as String,
      passwordConfirm: fixtureUser['password'] as String,
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
  },
  'auth.register.invalid': (h) async {
    await expectLater(
      h.auth.register(
        username: 'ada',
        email: 'another-ada@example.com',
        password: fixtureUser['password'] as String,
        passwordConfirm: fixtureUser['password'] as String,
      ),
      throwsA(
        exceptionWith('username: A user with that username already exists.'),
      ),
    );
  },
  'auth.password_reset': (h) async {
    await h.auth.requestPasswordReset('nobody@example.com');
  },
  'profile.get': (h) async {
    final state = await h.profileAfter(LoadProfile());
    expect(
      state,
      isA<ProfileLoaded>()
          .having((s) => s.username, 'username', 'ada')
          .having((s) => s.firstName, 'firstName', 'Ada')
          .having((s) => s.lastName, 'lastName', 'Lovelace')
          .having((s) => s.profileImageUrl, 'profileImageUrl', isNull)
          .having((s) => s.pinStyle, 'pinStyle', 'teardrop')
          .having((s) => s.distanceUnit, 'distanceUnit', 'metric'),
    );
  },
  'profile.update': (h) async {
    final state = await h.profileAfter(
      const UpdateProfile(
        firstName: 'Ada',
        city: 'London',
        country: 'UK',
        birthDate: '1815-12-10',
        pinColor: '#9C27B0',
        pinStyle: 'diamond',
        pinIconType: 'emoji',
        pinEmoji: '🧮',
        distanceUnit: 'imperial',
      ),
    );
    expect(
      state,
      isA<ProfileLoaded>()
          .having((s) => s.city, 'city', 'London')
          .having((s) => s.birthDate, 'birthDate', '1815-12-10')
          .having((s) => s.pinEmoji, 'pinEmoji', '🧮')
          .having((s) => s.distanceUnit, 'distanceUnit', 'imperial'),
    );
  },
  'profile.upload_image': (h) async {
    final state = await h.profileAfter(
      UploadProfileImage(imageBytes: png, imageName: 'avatar.png'),
    );
    final url =
        (h.interaction.example as Map<String, dynamic>)['profile_image']
            as String;
    expect(
      state,
      isA<ProfileLoaded>().having(
        (s) => s.profileImageUrl,
        'profileImageUrl',
        startsWith(url),
      ),
    );
  },
  'people.list': (h) async {
    final person = (await h.api.getPeople()).single;
    expect(person.id, personId);
    expect(person.latitude, 43.0389);
    expect(person.longitude, -87.9065);
    expect(person.relationshipTag, 'FRIEND');
    expect(person.birthday, DateTime(1906, 12, 9));
    expect(person.contactCadenceDays, 14);
    expect(person.preferredAirport?.iataCode, 'MDW');
    expect(person.preferredStation?.name, 'Milwaukee Airport');
    expect(person.lastContactedAt?.toUtc(), DateTime.utc(2026, 10, 20, 18, 30));
    expect(person.lastContactChannel, 'CALL');
  },
  'people.create': (h) async {
    final created = await h.api.addPerson(
      grace(),
      profileImage: XFile.fromData(png, path: 'picked/grace.png'),
    );
    expect(created.id, personId);
    expect(created.latitude, 43.0389);
    expect(created.timezone, 'America/Chicago');
    expect(created.profileImageUrl, startsWith('http'));
  },
  'people.update': (h) async {
    final updated = await h.api.updatePerson(
      grace(id: personId, tag: 'FAMILY'),
    );
    expect(updated.relationshipTag, 'FAMILY');
  },
  'people.delete': (h) async {
    await h.api.deletePerson(personId);
  },
  'contact_logs.list': (h) async {
    final log = (await h.api.getContactLogs()).single;
    expect(log.id, contactLogId);
    expect(log.personId, personId);
    expect(log.channel, ContactChannel.call);
    expect(log.contactedAt.toUtc(), DateTime.utc(2026, 10, 20, 18, 30));
    expect(log.note, 'Caught up about COBOL');
  },
  'contact_logs.list_for_person': (h) async {
    final logs = await h.api.getContactLogs(personId: personId);
    expect(logs.single.personId, personId);
  },
  'contact_logs.create': (h) async {
    final saved = await h.api.addContactLog(
      ContactLog(
        id: 'optimistic',
        personId: personId,
        channel: ContactChannel.call,
        contactedAt: DateTime.utc(2026, 10, 20, 18, 30),
        note: 'Caught up about COBOL',
      ),
    );
    expect(saved.id, contactLogId);
  },
  'trips.list': (h) async {
    final trip = (await h.api.getTrips()).single;
    expect(trip.id, tripId);
    expect(trip.status, TripStatus.draft);
    // What the planner draws and routes with after a reload.
    expect(trip.stops.first.people.single.firstName, 'Grace');
    expect(trip.stops.first.location, const LatLng(43.0389, -87.9065));
    expect(trip.stops.last.airport?.iataCode, 'MDW');
    expect(trip.legs.single.departureStopId, firstStopId);
    expect(trip.legs.single.arrivalStopId, secondStopId);
  },
  'trips.create': (h) async {
    final saved = await h.api.createTrip(plannedTrip());
    expect(saved.id, tripId);
    expect(saved.stops.first.people.single.id, personId);
    expect(saved.stops.last.airport?.id, 2364);
    expect(saved.legs.single.id, legId);
  },
  'trips.update': (h) async {
    final trip = plannedTrip(id: tripId, status: TripStatus.booked).copyWith(
      legs: const [
        TripLeg(
          id: legId,
          departureStopId: firstStopId,
          arrivalStopId: secondStopId,
          transportType: 'BUS',
          bookingReference: 'MKE-0914',
        ),
      ],
    );
    final saved = await h.api.updateTrip(trip);
    expect(saved.status, TripStatus.booked);
    expect(saved.legs.single.transportType, 'BUS');
    expect(saved.legs.single.bookingReference, 'MKE-0914');
  },
  'trips.delete': (h) async {
    await h.api.deleteTrip(tripId);
  },
  'airports.nearest': (h) async {
    final viaBloc = await h.airports.getNearestAirports(43.0389, -87.9065);
    expect(viaBloc.first.iataCode, 'MKE');
    expect(viaBloc.first.distanceKm, 10.2);
    final viaForm = await h.api.getNearestAirports(43.0389, -87.9065, count: 3);
    expect(viaForm.map((a) => a.id), viaBloc.map((a) => a.id));
  },
  'stations.nearest': (h) async {
    final viaBloc = await h.stations.getNearestStations(43.0389, -87.9065);
    expect(viaBloc.first.name, 'Milwaukee');
    expect(viaBloc.first.osmId, 2367479990);
    final viaForm = await h.api.getNearestStations(43.0389, -87.9065, count: 3);
    expect(viaForm.map((s) => s.id), viaBloc.map((s) => s.id));
  },
};

/// Gaps between the contract and what the app does, found by this suite and
/// not yet fixed. Each driver must still fail, so fixing one fails the suite
/// until its entry is removed.
const knownGaps = <String, String>{};

void main() {
  test('every contract has a consumer driver, and every driver a contract', () {
    expect(drivers.keys.toSet(), apiInteractions.keys.toSet());
  });

  for (final interaction in apiInteractions.values) {
    test('${interaction.id}: ${interaction.spec['description']}', () async {
      final auth = interaction.request['auth'];
      seedTokens(
        access: auth == 'invalid'
            ? 'expired-access-token'
            : contractAccessToken,
        refresh: contractRefreshToken,
        username: 'ada',
      );
      final h = Harness(interaction);
      h.serve(interaction);

      final driver = drivers[interaction.id];
      expect(driver, isNotNull, reason: 'no consumer driver');
      final gap = knownGaps[interaction.id];
      if (gap != null) {
        await expectLater(driver!(h), throwsA(isA<TestFailure>()), reason: gap);
        return;
      }
      await driver!(h);

      final sent = h.adapter.requestsTo(interaction.method, interaction.path);
      expect(sent, isNotEmpty, reason: 'the app never sent this request');
      for (final request in sent) {
        expectRequestMatches(request, interaction);
      }
    });
  }
}
