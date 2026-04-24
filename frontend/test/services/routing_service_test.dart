import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/services/api_service.dart';
import 'package:map_my_friends/services/routing_service.dart';

class MockApiService extends Fake implements ApiService {
  @override
  final Dio dio;
  MockApiService(this.dio);
}

void main() {
  late RoutingService routingService;
  late Dio dio;
  late MockApiService mockApiService;

  setUp(() {
    dio = Dio();
    mockApiService = MockApiService(dio);
    routingService = RoutingService(apiService: mockApiService);
  });

  group('RoutingService', () {
    final personA = Person(
      id: '1',
      firstName: 'A',
      lastName: 'User',
      relationshipTag: 'Friend',
      city: 'City',
      state: 'State',
      country: 'Country',
      latitude: 10.0,
      longitude: 10.0,
    );

    final stopA = TripStop(
      id: 's1',
      person: personA,
      location: const LatLng(10.0, 10.0),
      sequenceOrder: 0,
    );

    test('getRoute returns straight line for non-person stops', () async {
      final stopStation = TripStop(
        id: 's3',
        location: const LatLng(12.0, 12.0),
        sequenceOrder: 2,
      );

      final route = await routingService.getRoute([stopA, stopStation]);

      expect(route.length, 2);
      expect(route[0], const LatLng(10.0, 10.0));
      expect(route[1], const LatLng(12.0, 12.0));
    });

    test('getRoute returns empty for less than 2 stops', () async {
      final route = await routingService.getRoute([stopA]);
      expect(route, isEmpty);
    });
  });
}
