import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/bloc/trip/trip_bloc.dart';
import 'package:map_my_friends/bloc/trip/trip_event.dart';
import 'package:map_my_friends/bloc/trip/trip_state.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/services/routing_service.dart';

class MockRoutingService extends Fake implements RoutingService {
  @override
  Future<List<LatLng>> getRoute(List<TripStop> stops) async {
    return stops.map((s) => s.location).toList();
  }
}

void main() {
  late TripBloc tripBloc;
  late MockRoutingService mockRoutingService;

  final person = Person(
    id: '1',
    firstName: 'Test',
    lastName: 'User',
    relationshipTag: 'Friend',
    city: 'City',
    state: 'State',
    country: 'Country',
    latitude: 10.0,
    longitude: 10.0,
  );

  setUp(() {
    mockRoutingService = MockRoutingService();
    tripBloc = TripBloc(routingService: mockRoutingService);
  });

  tearDown(() {
    tripBloc.close();
  });

  group('TripBloc', () {
    test('initial state is empty', () {
      expect(tripBloc.state, const TripState());
    });

    test('AddStop updates state and triggers routing', () async {
      tripBloc.add(AddStop(person));

      await expectLater(
        tripBloc.stream,
        emitsInOrder([
          predicate<TripState>(
            (state) => state.stops.length == 1 && state.isOptimizing,
          ),
          predicate<TripState>(
            (state) => state.stops.length == 1 && !state.isOptimizing,
          ),
        ]),
      );
    });

    test('ClearTrip resets state', () async {
      tripBloc.add(AddStop(person));
      await tripBloc.stream.firstWhere((s) => !s.isOptimizing);

      tripBloc.add(const ClearTrip());
      await expectLater(tripBloc.stream, emits(const TripState()));
    });
  });
}
