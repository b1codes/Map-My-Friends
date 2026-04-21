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
}
