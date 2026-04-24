import 'package:equatable/equatable.dart';
import '../../models/person.dart';
import '../../models/trip.dart';

abstract class TripEvent extends Equatable {
  const TripEvent();
  @override
  List<Object?> get props => [];
}

class AddStop extends TripEvent {
  final Person person;
  const AddStop(this.person);
  @override
  List<Object?> get props => [person];
}

class RemoveStop extends TripEvent {
  final int index;
  const RemoveStop(this.index);
  @override
  List<Object?> get props => [index];
}

class ReorderStops extends TripEvent {
  final int oldIndex;
  final int newIndex;
  const ReorderStops(this.oldIndex, this.newIndex);
  @override
  List<Object?> get props => [oldIndex, newIndex];
}

class OptimizeTrip extends TripEvent {
  const OptimizeTrip();
}

class ClearTrip extends TripEvent {
  const ClearTrip();
}

class SaveTrip extends TripEvent {
  final String name;
  final DateTime date;
  final TripStatus status;
  const SaveTrip({required this.name, required this.date, required this.status});
  @override
  List<Object?> get props => [name, date, status];
}

class FetchUserTrips extends TripEvent {
  const FetchUserTrips();
}

class LoadTrip extends TripEvent {
  final Trip trip;
  const LoadTrip(this.trip);
  @override
  List<Object?> get props => [trip];
}

class DeleteTrip extends TripEvent {
  final int tripId;
  const DeleteTrip(this.tripId);
  @override
  List<Object?> get props => [tripId];
}
