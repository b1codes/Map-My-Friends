import 'package:equatable/equatable.dart';
import '../../models/airport.dart';

abstract class AirportState extends Equatable {
  const AirportState();

  @override
  List<Object?> get props => [];
}

class AirportInitial extends AirportState {}

class AirportLoading extends AirportState {}

/// All airports loaded from asset (for map layer)
class MapAirportsLoaded extends AirportState {
  final List<Airport> airports;

  const MapAirportsLoaded(this.airports);

  @override
  List<Object?> get props => [airports];
}

/// Nearest airports loaded from backend API (for profile sections)
class NearestAirportsLoaded extends AirportState {
  final List<Airport> airports;

  const NearestAirportsLoaded(this.airports);

  @override
  List<Object?> get props => [airports];
}

class AirportError extends AirportState {
  final String message;

  const AirportError(this.message);

  @override
  List<Object?> get props => [message];
}
