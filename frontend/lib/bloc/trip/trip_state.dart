import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../models/trip.dart';

class TripState extends Equatable {
  final List<TripStop> stops;
  final List<LatLng> routePoints;
  final bool isLoading;

  const TripState({
    this.stops = const [],
    this.routePoints = const [],
    this.isLoading = false,
  });

  TripState copyWith({
    List<TripStop>? stops,
    List<LatLng>? routePoints,
    bool? isLoading,
  }) {
    return TripState(
      stops: stops ?? this.stops,
      routePoints: routePoints ?? this.routePoints,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [stops, routePoints, isLoading];
}
