// Consumer side of the third-party contracts the app itself depends on:
// the OSRM route it requests directly, and the Auth0 tenant it signs in
// against (contracts/config/auth0.json, which Django is held to as well).
// The real OSRM server is checked against the same contract nightly by
// backend/tests/contracts/test_live_providers.py.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/services/api_config.dart';
import 'package:map_my_friends/services/routing_service.dart';

import '../helpers/fake_http_adapter.dart';
import '../services/service_test_support.dart';
import 'contract_support.dart';

Person friend(String id) => Person(
  id: id,
  firstName: id,
  lastName: 'Friend',
  relationshipTag: 'FRIEND',
  city: 'Milwaukee',
  state: 'WI',
  country: 'USA',
);

void main() {
  group('OSRM route', () {
    final contract = externalInteraction('osrm', 'route');
    late FakeHttpAdapter adapter;
    late List<LatLng> route;

    setUp(() async {
      adapter = FakeHttpAdapter()..onAny((_) => contract.reply);
      final service = RoutingService(dio: Dio()..httpClientAdapter = adapter);
      route = await service.getRoute([
        TripStop(
          people: [friend('a')],
          location: const LatLng(43.0389, -87.9065),
          sequenceOrder: 0,
        ),
        TripStop(
          people: [friend('b')],
          location: const LatLng(43.0343496, -87.9173923),
          sequenceOrder: 1,
        ),
      ]);
    });

    test('the request is the contract one, without app credentials', () {
      final sent = adapter.requests.single;
      final request = contract.request;
      expect(sent.method, request['method']);
      expect(sent.uri.replace(query: '').toString(), '${request['url']}?');
      expect(sent.uri.queryParameters, request['query']);
      expect(authHeaderOf(sent), isNull);
    });

    test('the route follows the contract geometry, as [lat, lng]', () {
      final example = contract.example as Map<String, dynamic>;
      final coordinates =
          example['routes'][0]['geometry']['coordinates'] as List<dynamic>;
      expect(route, [
        for (final c in coordinates)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ]);
    });
  });

  group('Auth0 tenant', () {
    final tenant =
        loadContractJson('config/auth0.json') as Map<String, dynamic>;

    test('the app signs in against the shared tenant and audience', () {
      expect(ApiConfig.auth0Domain, tenant['domain']);
      expect(ApiConfig.auth0ClientId, tenant['client_id']);
      expect(ApiConfig.auth0Audience, tenant['audience']);
    });
  });
}
