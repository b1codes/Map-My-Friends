import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_my_friends/models/trip.dart';
import 'package:map_my_friends/screens/trips/trip_details_screen.dart';

void main() {
  testWidgets('TripDetailsScreen builds successfully', (
    WidgetTester tester,
  ) async {
    final trip = Trip(
      id: 1,
      name: 'Test Trip',
      date: DateTime.now(),
      status: TripStatus.booked,
      stops: [
        TripStop(
          id: '1',
          location: const LatLng(52.5200, 13.4050),
          sequenceOrder: 0,
          snapshotAddress: 'Berlin, Germany',
          snapshotMetadata: {'people': 'John Doe'},
        ),
        TripStop(
          id: '2',
          location: const LatLng(48.8566, 2.3522),
          sequenceOrder: 1,
          snapshotAddress: 'Paris, France',
          snapshotMetadata: {'people': 'Jane Smith'},
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: TripDetailsScreen(trip: trip)));

    expect(find.text('Test Trip'), findsOneWidget);
    expect(find.text('BOOKED'), findsOneWidget);
    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('Berlin, Germany'), findsOneWidget);
    expect(find.text('Jane Smith'), findsOneWidget);
    expect(find.text('Paris, France'), findsOneWidget);
  });
}
