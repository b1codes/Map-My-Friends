import 'package:equatable/equatable.dart';

abstract class StationEvent extends Equatable {
  const StationEvent();

  @override
  List<Object?> get props => [];
}

class LoadMapStations extends StationEvent {}

class FetchNearestStations extends StationEvent {
  final double latitude;
  final double longitude;
  final int count;

  const FetchNearestStations({
    required this.latitude,
    required this.longitude,
    this.count = 3,
  });

  @override
  List<Object?> get props => [latitude, longitude, count];
}
