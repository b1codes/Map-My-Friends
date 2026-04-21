import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../models/trip.dart';

class TripState extends Equatable {
  final List<TripStop> stops;
  final List<LatLng> routePoints;
  final bool isOptimizing;

  const TripState({
    this.stops = const [],
    this.routePoints = const [],
    this.isOptimizing = false,
  });

  TripState copyWith({
    List<TripStop>? stops,
    List<LatLng>? routePoints,
    bool? isOptimizing,
  }) {
    return TripState(
      stops: stops ?? this.stops,
      routePoints: routePoints ?? this.routePoints,
      isOptimizing: isOptimizing ?? this.isOptimizing,
    );
  }

  @override
  List<Object?> get props => [stops, routePoints, isOptimizing];
}
