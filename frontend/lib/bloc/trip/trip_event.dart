import 'package:equatable/equatable.dart';
import '../../models/person.dart';

abstract class TripEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AddStop extends TripEvent {
  final Person person;
  AddStop(this.person);
  @override
  List<Object?> get props => [person];
}

class RemoveStop extends TripEvent {
  final int index;
  RemoveStop(this.index);
  @override
  List<Object?> get props => [index];
}

class ReorderStops extends TripEvent {
  final int oldIndex;
  final int newIndex;
  ReorderStops(this.oldIndex, this.newIndex);
  @override
  List<Object?> get props => [oldIndex, newIndex];
}

class OptimizeTrip extends TripEvent {}
class ClearTrip extends TripEvent {}
