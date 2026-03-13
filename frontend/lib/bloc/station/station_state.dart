import 'package:equatable/equatable.dart';
import '../../models/station.dart';

abstract class StationState extends Equatable {
  const StationState();

  @override
  List<Object?> get props => [];
}

class StationInitial extends StationState {}

class StationLoading extends StationState {}

class MapStationsLoaded extends StationState {
  final List<Station> stations;

  const MapStationsLoaded(this.stations);

  @override
  List<Object?> get props => [stations];
}

class NearestStationsLoaded extends StationState {
  final List<Station> stations;

  const NearestStationsLoaded(this.stations);

  @override
  List<Object?> get props => [stations];
}

class StationError extends StationState {
  final String message;

  const StationError(this.message);

  @override
  List<Object?> get props => [message];
}
