import 'package:equatable/equatable.dart';

abstract class AirportEvent extends Equatable {
  const AirportEvent();

  @override
  List<Object?> get props => [];
}

/// Load all airports from bundled asset (for map layer)
class LoadMapAirports extends AirportEvent {}

/// Load nearest airports for a given coordinate (for profile views)
class LoadNearestAirports extends AirportEvent {
  final double latitude;
  final double longitude;
  final int count;

  const LoadNearestAirports({
    required this.latitude,
    required this.longitude,
    this.count = 3,
  });

  @override
  List<Object?> get props => [latitude, longitude, count];
}
