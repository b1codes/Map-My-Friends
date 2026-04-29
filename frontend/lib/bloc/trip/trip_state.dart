import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../models/trip.dart';

class TripState extends Equatable {
  final List<TripStop> stops;
  final List<TripLeg> legs;
  final List<LatLng> routePoints;
  final bool isOptimizing;
  final List<Trip> userTrips;
  final bool isLoading;
  final String? error;
  final int? currentTripId;

  const TripState({
    this.stops = const [],
    this.legs = const [],
    this.routePoints = const [],
    this.isOptimizing = false,
    this.userTrips = const [],
    this.isLoading = false,
    this.error,
    this.currentTripId,
  });

  TripState copyWith({
    List<TripStop>? stops,
    List<TripLeg>? legs,
    List<LatLng>? routePoints,
    bool? isOptimizing,
    List<Trip>? userTrips,
    bool? isLoading,
    String? error,
    int? currentTripId,
    bool clearError = false,
    bool clearCurrentTripId = false,
  }) {
    return TripState(
      stops: stops ?? this.stops,
      legs: legs ?? this.legs,
      routePoints: routePoints ?? this.routePoints,
      isOptimizing: isOptimizing ?? this.isOptimizing,
      userTrips: userTrips ?? this.userTrips,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      currentTripId: clearCurrentTripId
          ? null
          : (currentTripId ?? this.currentTripId),
    );
  }

  @override
  List<Object?> get props => [
    stops,
    legs,
    routePoints,
    isOptimizing,
    userTrips,
    isLoading,
    error,
    currentTripId,
  ];
}
