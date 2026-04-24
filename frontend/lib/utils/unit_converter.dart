import '../bloc/map/map_settings_cubit.dart';

class UnitConverter {
  static double kmToMiles(double km) => km * 0.621371;

  static String formatDistance(double? km, DistanceUnit unit) {
    if (km == null) return '';
    if (unit == DistanceUnit.imperial) {
      final miles = kmToMiles(km);
      return '${miles.round()} mi';
    }
    return '${km.round()} km';
  }
}
