import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_state.dart';
import 'package:map_my_friends/bloc/pulse/pulse_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/models/airport.dart';
import 'package:map_my_friends/models/contact_log.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/station.dart';
import 'package:map_my_friends/models/trip.dart';

/// The sample world every catalog entry draws from.
///
/// One roster, used everywhere, so the same people appear on the People
/// screen, the Pulse roster, and the map — a catalog that invents fresh data
/// per entry hides exactly the inconsistencies a reviewer should see.
///
/// Every date hangs off [now], a fixed day, so contact recency (and with it
/// the thermal colours) reads the same on every run rather than drifting
/// toward "overdue" as the calendar moves.
abstract final class Fixtures {
  static final DateTime now = DateTime(2026, 7, 22, 10);

  static DateTime daysAgo(int days) => now.subtract(Duration(days: days));

  // --- Location --------------------------------------------------------------

  /// The device's position: Manhattan, near Sara, the sample airports and
  /// stations, so the map opens on something rather than the app's
  /// San Francisco fallback.
  static final LocationLoaded location = LocationLoaded(
    address: 'New York, NY',
    position: Position(
      latitude: 40.7484,
      longitude: -73.9857,
      timestamp: now,
      accuracy: 12,
      altitude: 10,
      altitudeAccuracy: 3,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ),
  );

  // --- Transit ---------------------------------------------------------------

  static final Airport jfk = Airport(
    id: 1,
    name: 'John F. Kennedy International Airport',
    iataCode: 'JFK',
    icaoCode: 'KJFK',
    airportType: 'large_airport',
    city: 'New York',
    country: 'US',
    continent: 'NA',
    latitude: 40.6413,
    longitude: -73.7781,
    distanceKm: 21.4,
  );

  static final Airport lga = Airport(
    id: 2,
    name: 'LaGuardia Airport',
    iataCode: 'LGA',
    icaoCode: 'KLGA',
    airportType: 'large_airport',
    city: 'New York',
    country: 'US',
    continent: 'NA',
    latitude: 40.7769,
    longitude: -73.8740,
    distanceKm: 13.2,
  );

  static final Airport hpn = Airport(
    id: 3,
    name: 'Westchester County Airport',
    iataCode: 'HPN',
    icaoCode: 'KHPN',
    airportType: 'medium_airport',
    city: 'White Plains',
    country: 'US',
    continent: 'NA',
    latitude: 41.0670,
    longitude: -73.7076,
    distanceKm: 48.9,
  );

  static final Airport fco = Airport(
    id: 4,
    name: 'Leonardo da Vinci–Fiumicino Airport',
    iataCode: 'FCO',
    icaoCode: 'LIRF',
    airportType: 'large_airport',
    city: 'Rome',
    country: 'IT',
    continent: 'EU',
    latitude: 41.8003,
    longitude: 12.2389,
  );

  static List<Airport> get airports => [lga, jfk, hpn];

  static final Station pennStation = Station(
    id: 1,
    name: 'Penn Station',
    osmId: 1001,
    stationType: 'major_station',
    city: 'New York',
    country: 'US',
    latitude: 40.7506,
    longitude: -73.9935,
    distanceKm: 1.1,
  );

  static final Station grandCentral = Station(
    id: 2,
    name: 'Grand Central Terminal',
    osmId: 1002,
    stationType: 'commuter_rail_station',
    city: 'New York',
    country: 'US',
    latitude: 40.7527,
    longitude: -73.9772,
    distanceKm: 1.9,
  );

  static final Station unionSquare = Station(
    id: 3,
    name: '14 St–Union Sq',
    osmId: 1003,
    stationType: 'subway_station',
    city: 'New York',
    country: 'US',
    latitude: 40.7359,
    longitude: -73.9906,
    distanceKm: 2.4,
  );

  static final Station stamford = Station(
    id: 4,
    name: 'Stamford',
    osmId: 1004,
    stationType: 'regional_station',
    city: 'Stamford',
    country: 'US',
    latitude: 41.0466,
    longitude: -73.5420,
    distanceKm: 53.7,
  );

  static List<Station> get stations => [
    pennStation,
    grandCentral,
    unionSquare,
    stamford,
  ];

  // --- People ----------------------------------------------------------------

  /// A friend contacted recently: fresh on the thermal scale.
  static final Person marco = Person(
    id: 'p-marco',
    firstName: 'Marco',
    lastName: 'Rossi',
    relationshipTag: 'FRIEND',
    street: 'Via del Corso 12',
    city: 'Rome',
    state: 'Lazio',
    country: 'Italy',
    latitude: 41.9028,
    longitude: 12.4964,
    timezone: 'Europe/Rome',
    phoneNumber: '+39 06 1234 5678',
    birthday: DateTime(1991, 3, 14),
    pinColor: '#3F51B5',
    pinStyle: 'teardrop',
    pinIconType: 'initials',
    preferredAirport: fco,
    preferredAirportId: '4',
    lastContactedAt: daysAgo(3),
    lastContactChannel: 'MESSAGE',
  );

  /// A friend drifting toward due.
  static final Person sara = Person(
    id: 'p-sara',
    firstName: 'Sara',
    lastName: 'Lin',
    relationshipTag: 'FRIEND',
    city: 'New York',
    state: 'NY',
    country: 'USA',
    latitude: 40.7128,
    longitude: -74.0060,
    timezone: 'America/New_York',
    phoneNumber: '+1 212 555 0142',
    pinColor: '#FF4081',
    pinStyle: 'circle',
    pinIconType: 'emoji',
    pinEmoji: '🎨',
    preferredStation: pennStation,
    preferredStationId: '1',
    lastContactedAt: daysAgo(19),
    lastContactChannel: 'CALL',
  );

  /// Family, past their tighter cadence: overdue.
  static final Person dev = Person(
    id: 'p-dev',
    firstName: 'Dev',
    lastName: 'Patel',
    relationshipTag: 'FAMILY',
    city: 'London',
    state: 'England',
    country: 'UK',
    latitude: 51.5074,
    longitude: -0.1278,
    timezone: 'Europe/London',
    pinColor: '#4CAF50',
    pinStyle: 'square',
    pinIconType: 'picture',
    lastContactedAt: daysAgo(31),
    lastContactChannel: 'VIDEO',
  );

  /// A custom weekly cadence, comfortably inside it.
  static final Person mom = Person(
    id: 'p-mom',
    firstName: 'Mom',
    lastName: '',
    relationshipTag: 'FAMILY',
    city: 'Denver',
    state: 'CO',
    country: 'USA',
    latitude: 39.7392,
    longitude: -104.9903,
    timezone: 'America/Denver',
    pinColor: '#FF9800',
    pinStyle: 'diamond',
    pinIconType: 'emoji',
    pinEmoji: '🏡',
    contactCadenceDays: 7,
    lastContactedAt: daysAgo(2),
    lastContactChannel: 'CALL',
  );

  /// Never contacted: the silent state.
  static final Person noah = Person(
    id: 'p-noah',
    firstName: 'Noah',
    lastName: 'Kim',
    relationshipTag: 'FRIEND',
    city: 'Seoul',
    state: '',
    country: 'South Korea',
    latitude: 37.5665,
    longitude: 126.9780,
    timezone: 'Asia/Seoul',
    pinColor: '#9C27B0',
    pinStyle: 'triangle',
    pinIconType: 'none',
  );

  /// Long names and no coordinates — the layout stress case.
  static final Person maximiliane = Person(
    id: 'p-maxi',
    firstName: 'Maximiliane-Josephine',
    lastName: 'von Hohenzollern-Sigmaringen',
    relationshipTag: 'FRIEND',
    city: 'Garmisch-Partenkirchen',
    state: 'Bavaria',
    country: 'Germany',
    timezone: 'Europe/Berlin',
    lastContactedAt: daysAgo(64),
    lastContactChannel: 'MESSAGE',
  );

  static List<Person> get people => [marco, sara, dev, mom, noah, maximiliane];

  static Person personById(String id) =>
      people.firstWhere((p) => p.id == id, orElse: () => marco);

  // --- Pulse -----------------------------------------------------------------

  /// Final rather than a getter: Equatable compares these by identity, so a
  /// fresh list per build would read as a new Pulse state on every rebuild.
  static final List<ContactLog> contactLogs = [
    ContactLog(
      id: 'log-1',
      personId: mom.id,
      channel: ContactChannel.call,
      contactedAt: daysAgo(2),
      note: 'Talked through the garden plans.',
    ),
    ContactLog(
      id: 'log-2',
      personId: marco.id,
      channel: ContactChannel.message,
      contactedAt: daysAgo(3),
    ),
    ContactLog(
      id: 'log-3',
      personId: sara.id,
      channel: ContactChannel.call,
      contactedAt: daysAgo(19),
      note: 'Gallery opening is in September.',
    ),
    ContactLog(
      id: 'log-4',
      personId: dev.id,
      channel: ContactChannel.video,
      contactedAt: daysAgo(31),
    ),
    ContactLog(
      id: 'log-5',
      personId: marco.id,
      channel: ContactChannel.video,
      contactedAt: daysAgo(19),
    ),
  ];

  static PulseLoaded pulseLoaded({List<Person>? people}) =>
      PulseLoaded(people: people ?? Fixtures.people, logs: contactLogs);

  // --- Profile ---------------------------------------------------------------

  static const ProfileLoaded profile = ProfileLoaded(
    username: 'alex',
    email: 'alex@example.com',
    firstName: 'Alex',
    lastName: 'Rivera',
    street: '350 5th Ave',
    city: 'New York',
    state: 'NY',
    country: 'USA',
    birthDate: '1990-05-17',
    phoneNumber: '+12125550199',
    pinColor: '#3F51B5',
    pinStyle: 'teardrop',
    pinIconType: 'initials',
    distanceUnit: 'imperial',
  );

  // --- Trips -----------------------------------------------------------------

  static final TripStop homeStop = TripStop(
    id: 'stop-1',
    location: const LatLng(40.7128, -74.0060),
    sequenceOrder: 0,
    people: [sara],
    snapshotAddress: 'New York, NY, USA',
    snapshotMetadata: const {'people': 'Sara Lin'},
  );

  static final TripStop airportStop = TripStop(
    id: 'stop-2',
    location: LatLng(jfk.latitude, jfk.longitude),
    sequenceOrder: 1,
    airport: jfk,
    snapshotAddress: 'JFK — New York',
  );

  static final TripStop romeStop = TripStop(
    id: 'stop-3',
    location: const LatLng(41.9028, 12.4964),
    sequenceOrder: 2,
    people: [marco],
    snapshotAddress: 'Rome, Lazio, Italy',
    snapshotMetadata: const {'people': 'Marco Rossi'},
  );

  static final TripStop stationStop = TripStop(
    id: 'stop-4',
    location: LatLng(pennStation.latitude, pennStation.longitude),
    sequenceOrder: 3,
    station: pennStation,
    snapshotAddress: 'Penn Station — New York',
  );

  static List<TripStop> get plannedStops => [homeStop, airportStop, romeStop];

  static List<TripLeg> get legs => [
    TripLeg(
      id: 'leg-1',
      departureStopId: homeStop.id!,
      arrivalStopId: airportStop.id!,
      departureTime: DateTime(2026, 9, 4, 14),
      arrivalTime: DateTime(2026, 9, 4, 15, 10),
      transportType: 'CAR',
    ),
    TripLeg(
      id: 'leg-2',
      departureStopId: airportStop.id!,
      arrivalStopId: romeStop.id!,
      departureTime: DateTime(2026, 9, 4, 18, 30),
      arrivalTime: DateTime(2026, 9, 5, 8, 45),
      transportType: 'FLIGHT',
      bookingReference: 'AZ6107',
      ticketData: const {'seat': '23A', 'terminal': '1'},
    ),
  ];

  static final Trip romeTrip = Trip(
    id: 'trip-1',
    name: 'Rome in September',
    date: DateTime(2026, 9, 4),
    startDate: DateTime(2026, 9, 4),
    endDate: DateTime(2026, 9, 12),
    status: TripStatus.booked,
    stops: plannedStops,
    legs: legs,
  );

  static final Trip weekendDraft = Trip(
    id: 'trip-2',
    name: 'Denver long weekend',
    date: DateTime(2026, 10, 9),
    status: TripStatus.draft,
    stops: [
      TripStop(
        id: 'stop-5',
        location: const LatLng(39.7392, -104.9903),
        sequenceOrder: 0,
        people: [mom],
        snapshotAddress: 'Denver, CO, USA',
        snapshotMetadata: const {'people': 'Mom'},
      ),
    ],
  );

  static final Trip cancelledTrip = Trip(
    id: 'trip-3',
    name: 'Seoul (postponed)',
    date: DateTime(2026, 4, 2),
    status: TripStatus.cancelled,
    stops: [
      TripStop(
        id: 'stop-6',
        location: const LatLng(37.5665, 126.9780),
        sequenceOrder: 0,
        people: [noah],
        snapshotAddress: 'Seoul, South Korea',
      ),
    ],
  );

  static List<Trip> get trips => [romeTrip, weekendDraft, cancelledTrip];

  /// A trip being planned on the map: stops chosen, nothing saved yet.
  static TripState get planningTrip => TripState(
    stops: [homeStop, airportStop, romeStop, stationStop],
    userTrips: trips,
  );
}
