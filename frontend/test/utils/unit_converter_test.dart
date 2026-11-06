import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/utils/unit_converter.dart';

void main() {
  group('kmToMiles', () {
    test('uses the statute-mile factor', () {
      expect(UnitConverter.kmToMiles(0), 0);
      expect(UnitConverter.kmToMiles(1), closeTo(0.621371, 1e-9));
      expect(UnitConverter.kmToMiles(42.195), closeTo(26.2188, 1e-4));
    });
  });

  group('formatDistance', () {
    test('is empty when the distance is unknown', () {
      expect(UnitConverter.formatDistance(null, DistanceUnit.metric), '');
      expect(UnitConverter.formatDistance(null, DistanceUnit.imperial), '');
    });

    test('rounds kilometres in metric', () {
      expect(UnitConverter.formatDistance(12.4, DistanceUnit.metric), '12 km');
      expect(UnitConverter.formatDistance(12.5, DistanceUnit.metric), '13 km');
      expect(UnitConverter.formatDistance(0.2, DistanceUnit.metric), '0 km');
    });

    test('converts and rounds to miles in imperial', () {
      // 100 km = 62.14 mi; 1.0 km = 0.62 mi rounds up to 1.
      expect(UnitConverter.formatDistance(100, DistanceUnit.imperial), '62 mi');
      expect(UnitConverter.formatDistance(1, DistanceUnit.imperial), '1 mi');
      expect(UnitConverter.formatDistance(0.5, DistanceUnit.imperial), '0 mi');
    });
  });
}
