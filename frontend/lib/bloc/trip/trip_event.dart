import 'package:equatable/equatable.dart';
import '../../models/person.dart';

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
