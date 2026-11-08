/// The signed-in user's tokens never leave for a host other than the app's
/// own API.
///
/// RoutingService once fetched OSRM routes through `ApiService.dio`, whose
/// interceptor stamps `Authorization: Bearer <access token>` on every request,
/// so every route lookup handed the user's JWT to router.project-osrm.org
/// (fixed in 39ceded). This suite makes that class of bug structural rather
/// than per-service: it installs [RecordingHttpOverrides], so every
/// `dart:io` [HttpClient] the app creates (Dio's default adapter,
/// `package:http`'s `IOClient` under flutter_map's tile providers, and
/// `NetworkImage`) records each request after every interceptor has run.
/// With access and refresh tokens stored, it drives each call site wired the
/// way `main.dart` wires it, then checks every recorded request: either its
/// origin is `ApiConfig.baseUrl`'s, or it carries no `Authorization` header
/// and neither token anywhere in its headers, URL or body. The API's own
/// requests must carry the bearer token, so the check cannot pass by
/// recording nothing.
///
/// Network call sites in `lib/` (the inventory test at the bottom fails when
/// a new one appears, so this list and the coverage stay current):
///
/// Own API (`ApiConfig.baseUrl`), Dio with the auth interceptor:
/// - `ApiService` (singleton): people, contact logs, trips, nearest
///   airports/stations. Used by PeopleBloc and PulseBloc (main.dart passes
///   `ApiService()`), TripBloc (defaults to `ApiService()`) and
///   AddEditPersonScreen.
/// - `AirportService` (singleton): `airports/nearest/` via AirportBloc.
/// - `StationService` (singleton): `stations/nearest/` via StationBloc.
/// - `AuthService` (singleton): login, register, password reset, token
///   refresh (plain Dio, no access token), and profile get/update/upload (a
///   per-call Dio with the bearer token in its BaseOptions) via ProfileBloc.
///
/// Third-party hosts, which must never see a token:
/// - `RoutingService` -> OSRM (`ApiConfig.osrmBaseUrl`,
///   router.project-osrm.org), its own plain Dio. Built by TripBloc and by
///   TripDetailsScreen when no router is injected.
/// - `MapScreen` TileLayer -> tile.openstreetmap.org/.de/.fr,
///   basemaps.cartocdn.com, server.arcgisonline.com (or
///   `ApiConfig.tileUrlOverride`), through `FMTCTileProvider` (native) or
///   `NetworkTileProvider` (web).
/// - `TripDetailsScreen` TileLayer -> the same tile servers, through the
///   default `NetworkTileProvider`.
/// - `NetworkImage` profile photos (PersonDetailsScreen, AddEditPersonScreen,
///   MeScreen, ContactRosterTile, CustomMapMarker, HorizontalTripPlanner,
///   UnifiedClusterModal): URLs come from the API and may point at media
///   storage on another host. None passes headers; the inventory test pins
///   that.
///
/// Not interceptable here, and carrying no app token by construction:
/// - Auth0 sign-in (`AuthService.loginWithAuth0`) runs in the native
///   auth0_flutter SDK and is what *issues* the token.
/// - `launchUrl` (tel:/sms: links, the OSM and CARTO attribution pages) hands
///   a fixed URL to the OS.
///
/// No Overpass or Nominatim calls exist in the frontend (the backend imports
/// stations and resolves places), so there is nothing of theirs to cover.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/bloc/airport/airport_bloc.dart';
import 'package:map_my_friends/bloc/airport/airport_event.dart';
import 'package:map_my_friends/bloc/airport/airport_state.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_event.dart';
import 'package:map_my_friends/bloc/profile/profile_state.dart';
import 'package:map_my_friends/bloc/pulse/pulse_bloc.dart';
import 'package:map_my_friends/bloc/station/station_bloc.dart';
import 'package:map_my_friends/bloc/station/station_event.dart';
import 'package:map_my_friends/bloc/station/station_state.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/l10n/app_localizations.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/screens/map/map_screen.dart';
import 'package:map_my_friends/screens/trips/trip_details_screen.dart';
import 'package:map_my_friends/services/api_config.dart';
import 'package:map_my_friends/services/api_service.dart';
import 'package:map_my_friends/services/routing_service.dart';
import 'package:mocktail/mocktail.dart';

import '../services/service_test_support.dart' show seedTokens;
import '../helpers/recording_http_overrides.dart';

// JWT-shaped and URL-safe, so a percent-encoded copy is still a substring.
const _accessToken = 'eyJhbGciOiJIUzI1NiJ9.access-SECRET-7f3a.sig';
const _refreshToken = 'eyJhbGciOiJIUzI1NiJ9.refresh-SECRET-91c2.sig';
const _secrets = {'access token': _accessToken, 'refresh token': _refreshToken};

final Uri _api = Uri.parse(ApiConfig.baseUrl);
final String _osrmHost = Uri.parse(ApiConfig.osrmBaseUrl).host;

/// Same scheme, host and port as the API. Another port on the same host is a
/// different server.
bool _isApi(Uri uri) =>
    uri.scheme == _api.scheme && uri.host == _api.host && uri.port == _api.port;

/// Why each request in [requests] leaks a token to a non-API host, if any.
List<String> _leaks(Iterable<RecordedRequest> requests) => [
  for (final r in requests)
    if (!_isApi(r.uri)) ...[
      if (r.headers.containsKey('authorization'))
        '$r sent Authorization: ${r.headers['authorization']!.join(', ')}',
      for (final MapEntry(key: label, value: secret) in _secrets.entries) ...[
        for (final MapEntry(key: name, value: values) in r.headers.entries)
          if (values.any((v) => v.contains(secret)))
            '$r sent the $label in its $name header',
        if (r.uri.toString().contains(secret)) '$r has the $label in its URL',
        if (r.bodyText.contains(secret)) '$r sent the $label in its body',
      ],
    ],
];

/// A response shape every list/detail endpoint of the API accepts: GeoJSON
/// endpoints read `features`, paginated ones `results`, profile a map.
final _apiReply = CannedResponse.json(200, {
  'type': 'FeatureCollection',
  'features': <Object>[],
  'results': <Object>[],
});

CannedResponse _respond(RecordedRequest r) {
  if (_isApi(r.uri)) return _apiReply;
  if (r.uri.host == _osrmHost) {
    return CannedResponse.json(200, {
      'routes': [
        {
          'geometry': {
            'coordinates': [
              [13.405, 52.52],
              [8.0, 50.0],
              [2.3522, 48.8566],
            ],
          },
        },
      ],
    });
  }
  if (r.uri.path.endsWith('.png') || r.uri.path.contains('/tile/')) {
    return CannedResponse(200, _transparentPixel, const {
      'content-type': ['image/png'],
      // Enough for flutter_map's cache to compute a freshness age.
      'cache-control': ['max-age=60'],
      'date': ['Thu, 05 Mar 2026 00:00:00 GMT'],
    });
  }
  return const CannedResponse(404, []);
}

/// A 1x1 transparent PNG, so tile loads succeed quietly instead of logging
/// one HTTP error per tile.
final _transparentPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

Person _person(String id, LatLng at) => Person(
  id: id,
  firstName: 'P$id',
  lastName: 'Friend',
  relationshipTag: 'FRIEND',
  city: 'City',
  state: 'State',
  country: 'Country',
  latitude: at.latitude,
  longitude: at.longitude,
);

const _berlin = LatLng(52.52, 13.405);
const _paris = LatLng(48.8566, 2.3522);

/// Two friend-to-friend stops: the only kind of leg RoutingService sends to
/// OSRM (hub legs are drawn as straight lines with no request).
final _roadTrip = Trip(
  id: 'trip-1',
  name: 'Road trip',
  date: DateTime(2026, 3, 5),
  stops: [
    TripStop(
      people: [_person('1', _berlin)],
      location: _berlin,
      sequenceOrder: 0,
    ),
    TripStop(
      people: [_person('2', _paris)],
      location: _paris,
      sequenceOrder: 1,
    ),
  ],
);

/// Lets Dio's interceptor chain, secure-storage reads and bloc handlers run.
Future<void> _settleAsync() => pumpEventQueue(times: 100);

/// A call site driven the way the app drives it, and the hosts it must reach
/// (so a call site that silently stops sending anything fails the test).
class _CallSite {
  final String name;
  final Future<void> Function() run;
  final bool expectsApi;
  final Set<String> expectsThirdPartyHosts;

  const _CallSite(
    this.name,
    this.run, {
    this.expectsApi = false,
    this.expectsThirdPartyHosts = const {},
  });
}

Future<void> _drive<B extends BlocBase<Object?>>(
  B bloc,
  void Function(B) start,
) async {
  start(bloc);
  await _settleAsync();
  await bloc.close();
}

final _callSites = <_CallSite>[
  // main.dart: PeopleBloc(apiService: ApiService())..add(LoadPeople())
  _CallSite(
    'PeopleBloc (ApiService) loading people',
    () => _drive(
      PeopleBloc(apiService: ApiService()),
      (b) => b.add(LoadPeople()),
    ),
    expectsApi: true,
  ),
  // main.dart: PulseBloc(apiService: ApiService()), loaded by PulseScreen.
  _CallSite(
    'PulseBloc (ApiService) loading people and contact logs',
    () =>
        _drive(PulseBloc(apiService: ApiService()), (b) => b.add(LoadPulse())),
    expectsApi: true,
  ),
  // main.dart: ProfileBloc(), defaulting to AuthService()'s per-call Dio.
  _CallSite(
    'ProfileBloc (AuthService) loading and updating the profile',
    () => _drive(ProfileBloc(), (b) {
      b
        ..add(LoadProfile())
        ..add(const UpdateProfile(city: 'Berlin'));
    }),
    expectsApi: true,
  ),
  // main.dart: AirportBloc(), defaulting to AirportService().
  _CallSite(
    'AirportBloc (AirportService) loading nearest airports',
    () => _drive(
      AirportBloc(),
      (b) => b.add(const LoadNearestAirports(latitude: 52.5, longitude: 13.4)),
    ),
    expectsApi: true,
  ),
  // main.dart: StationBloc(), defaulting to StationService().
  _CallSite(
    'StationBloc (StationService) loading nearest stations',
    () => _drive(
      StationBloc(),
      (b) => b.add(const FetchNearestStations(latitude: 52.5, longitude: 13.4)),
    ),
    expectsApi: true,
  ),
  // main.dart: TripBloc(), defaulting to RoutingService() and ApiService().
  _CallSite(
    'TripBloc (ApiService + RoutingService) loading trips and a route',
    () => _drive(TripBloc(), (b) {
      b
        ..add(const FetchUserTrips())
        ..add(LoadTrip(_roadTrip));
    }),
    expectsApi: true,
    expectsThirdPartyHosts: {_osrmHost},
  ),
  _CallSite(
    'RoutingService() fetching a driving route',
    () async {
      expect(await RoutingService().getRoute(_roadTrip.stops), isNotEmpty);
    },
    expectsThirdPartyHosts: {_osrmHost},
  ),
];

class _MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

class _MockPeopleBloc extends MockBloc<PeopleEvent, PeopleState>
    implements PeopleBloc {}

class _MockMapSettingsCubit extends MockCubit<MapSettingsState>
    implements MapSettingsCubit {}

class _MockProfileBloc extends MockBloc<ProfileEvent, ProfileState>
    implements ProfileBloc {}

class _MockAirportBloc extends MockBloc<AirportEvent, AirportState>
    implements AirportBloc {}

class _MockStationBloc extends MockBloc<StationEvent, StationState>
    implements StationBloc {}

class _MockTripBloc extends MockBloc<TripEvent, TripState>
    implements TripBloc {}

/// The tile layer's request config never carries a token: no Authorization
/// header, and neither token in any header value or the URL template.
void _expectTileLayerTokenFree(WidgetTester tester) {
  final layers = tester.widgetList<TileLayer>(find.byType(TileLayer));
  expect(layers, isNotEmpty, reason: 'no TileLayer was built');
  for (final layer in layers) {
    final headers = layer.tileProvider.headers;
    expect(
      headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('authorization')),
      reason: '${layer.tileProvider.runtimeType} sends an Authorization header',
    );
    for (final secret in _secrets.values) {
      expect(
        headers.values.where((v) => v.contains(secret)),
        isEmpty,
        reason: '${layer.tileProvider.runtimeType} headers carry a token',
      );
      expect(layer.urlTemplate, isNot(contains(secret)));
      expect(layer.fallbackUrl ?? '', isNot(contains(secret)));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final transport = RecordingHttpOverrides();
  HttpOverrides? previousOverrides;

  setUpAll(() {
    // After the binding's own override (which answers 400 to everything), and
    // before any singleton service creates its HttpClient.
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = transport;
  });

  tearDownAll(() => HttpOverrides.global = previousOverrides);

  setUp(() {
    transport.requests.clear();
    transport.responder = _respond;
    seedTokens(access: _accessToken, refresh: _refreshToken, username: 'u');
  });

  test('the API and OSRM are on different hosts, so the checks mean '
      'something', () {
    expect(_isApi(Uri.parse(ApiConfig.osrmBaseUrl)), isFalse);
  });

  group('every request a call site sends', () {
    for (final site in _callSites) {
      test(site.name, () async {
        await site.run();
        final sent = transport.requests;

        expect(sent, isNotEmpty, reason: '${site.name} sent no request');
        final thirdPartyHosts = {
          for (final r in sent)
            if (!_isApi(r.uri)) r.uri.host,
        };
        expect(thirdPartyHosts, containsAll(site.expectsThirdPartyHosts));

        expect(_leaks(sent), isEmpty);

        final apiRequests = sent.where((r) => _isApi(r.uri)).toList();
        if (site.expectsApi) {
          expect(apiRequests, isNotEmpty, reason: 'no request reached the API');
        }
        // Positive control: the API itself is sent the token, so the leak
        // check above is looking at requests the interceptors did run on.
        for (final r in apiRequests) {
          expect(
            r.headers['authorization'],
            ['Bearer $_accessToken'],
            reason: '$r to the app API went without the access token',
          );
        }
      });
    }
  });

  test(
    'the check catches the original leak: OSRM through ApiService.dio',
    () async {
      // What RoutingService did before 39ceded. If this ever passes the leak
      // check, the recording or the check has stopped working.
      await ApiService().dio.get<dynamic>(
        '${ApiConfig.osrmBaseUrl}/13.405,52.52;2.3522,48.8566',
      );

      final osrm = transport.requests.single;
      expect(osrm.uri.host, _osrmHost);
      expect(_leaks(transport.requests), [
        '$osrm sent Authorization: Bearer $_accessToken',
        '$osrm sent the access token in its authorization header',
      ]);
    },
  );

  group('map tiles', () {
    testWidgets(
      'TripDetailsScreen: tiles and its default router get no token',
      (tester) async {
        final settings = _MockMapSettingsCubit();
        when(() => settings.state).thenReturn(const MapSettingsState());

        // NetworkTileProvider consults flutter_map's tile cache before the
        // network. Its default directory comes from path_provider, which has
        // no plugin under test, so create the singleton on a temp directory
        // first; the screen's TileLayer then reuses it. It is created outside
        // the fake clock, so its worker isolate's messages are delivered.
        final cacheDir = Directory.systemTemp.createTempSync('tile_cache');
        final cache = (await tester.runAsync(
          () async => BuiltInMapCachingProvider.getOrCreateInstance(
            cacheDirectory: cacheDir.path,
            maxCacheSize: null,
            readOnly: true,
          ),
        ))!;
        addTearDown(
          () => tester.runAsync(() => cache.destroy(deleteCache: true)),
        );

        // No routingService: the screen builds its own RoutingService(), as
        // TripsScreen does when it opens a saved trip.
        await tester.pumpWidget(
          BlocProvider<MapSettingsCubit>.value(
            value: settings,
            child: MaterialApp(home: TripDetailsScreen(trip: _roadTrip)),
          ),
        );
        // Tile loads first ask flutter_map's built-in tile cache, which does
        // real file I/O; that only completes outside the fake clock.
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }

        _expectTileLayerTokenFree(tester);

        final sent = transport.requests;
        final hosts = sent.map((r) => r.uri.host).toSet();
        expect(hosts, contains(_osrmHost));
        // NetworkTileProvider's requests reach the transport too, so their
        // actual headers are checked, not just the layer's config.
        expect(hosts, contains('tile.openstreetmap.org'));
        expect(_leaks(sent), isEmpty);
      },
    );

    for (final mapType in MapType.values) {
      for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('MapScreen ${mapType.name} ${themeMode.name}: tile layer '
            'carries no token', (tester) async {
          final settings = _MockMapSettingsCubit();
          final location = _MockLocationBloc();
          final people = _MockPeopleBloc();
          final profile = _MockProfileBloc();
          final airports = _MockAirportBloc();
          final stations = _MockStationBloc();
          final trips = _MockTripBloc();
          when(() => settings.state).thenReturn(
            MapSettingsState(mapType: mapType, themeMode: themeMode),
          );
          when(() => location.state).thenReturn(LocationInitial());
          when(() => people.state).thenReturn(const PeopleLoaded([]));
          when(() => profile.state).thenReturn(const ProfileLoaded());
          when(() => airports.state).thenReturn(const MapAirportsLoaded([]));
          when(() => stations.state).thenReturn(const MapStationsLoaded([]));
          when(() => trips.state).thenReturn(const TripState());

          tester.view.physicalSize = const Size(1200, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<LocationBloc>.value(value: location),
                BlocProvider<PeopleBloc>.value(value: people),
                BlocProvider<MapSettingsCubit>.value(value: settings),
                BlocProvider<ProfileBloc>.value(value: profile),
                BlocProvider<AirportBloc>.value(value: airports),
                BlocProvider<StationBloc>.value(value: stations),
                BlocProvider<TripBloc>.value(value: trips),
              ],
              child: const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: MapScreen(),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));

          _expectTileLayerTokenFree(tester);
          // FMTCTileProvider has no store backend under test, so it may not
          // reach the network; whatever it does send is checked too.
          expect(_leaks(transport.requests), isEmpty);
        });
      }
    }
  });

  group('call-site inventory', () {
    /// Source files under lib/, comment lines dropped.
    final sources = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart') && !f.path.contains('/l10n/'))
          f.path: f
              .readAsLinesSync()
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n'),
    };

    Set<String> filesMatching(Pattern pattern) => {
      for (final MapEntry(key: path, value: text) in sources.entries)
        if (text.contains(pattern)) path,
    };

    const reason =
        'A network call site was added or moved. Cover it in '
        'test/security/third_party_token_test.dart (and list it in the doc '
        'comment there), then update this expectation.';

    test('Dio clients are built only by the known services', () {
      expect(filesMatching(RegExp(r'\bDio\(|\bDio\.new\b')), {
        'lib/services/api_service.dart',
        'lib/services/airport_service.dart',
        'lib/services/station_service.dart',
        'lib/services/auth_service.dart',
        'lib/services/routing_service.dart',
      }, reason: reason);
    });

    test('nothing talks HTTP outside Dio, tile layers and NetworkImage', () {
      expect(
        filesMatching(
          RegExp(
            r"package:http/|\bHttpClient\(|\bWebSocket\b|"
            r"WebSocketChannel|\bhttp\.(get|post|put|patch|delete|Client)\b",
          ),
        ),
        isEmpty,
        reason: reason,
      );
    });

    test('tile layers live only in MapScreen and TripDetailsScreen', () {
      expect(filesMatching(RegExp(r'\bTileLayer\(')), {
        'lib/screens/map/map_screen.dart',
        'lib/screens/trips/trip_details_screen.dart',
      }, reason: reason);
    });

    test('network images never send headers', () {
      // A NetworkImage's URL comes from the API but can name any host, so
      // it must not be handed the bearer header the API wants.
      final call = RegExp(r'\b(NetworkImage|Image\.network)\(');
      final withHeaders = <String>[];
      for (final MapEntry(key: path, value: text) in sources.entries) {
        for (final m in call.allMatches(text)) {
          // The argument list, up to the matching close paren.
          var depth = 0;
          var end = m.end - 1;
          for (; end < text.length; end++) {
            if (text[end] == '(') depth++;
            if (text[end] == ')' && --depth == 0) break;
          }
          final args = text.substring(m.end, end);
          if (args.contains('headers')) withHeaders.add('$path: ${m[0]}$args)');
        }
      }
      expect(withHeaders, isEmpty);
      expect(filesMatching(call), {
        'lib/screens/people/person_details_screen.dart',
        'lib/screens/people/add_edit_person_screen.dart',
        'lib/screens/profile/me_screen.dart',
        'lib/components/pulse/contact_roster_tile.dart',
        'lib/components/map/custom_map_marker.dart',
        'lib/components/map/horizontal_trip_planner.dart',
        'lib/components/map/unified_cluster_modal.dart',
      }, reason: reason);
    });
  });
}
