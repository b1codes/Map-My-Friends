import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import 'person.dart';

class TripStop extends Equatable {
  final String id;
  final Person? person;
  final LatLng location;
  final int sequenceOrder;

  const TripStop({
    required this.id,
    this.person,
    required this.location,
    required this.sequenceOrder,
  });

  TripStop copyWith({int? sequenceOrder}) {
    return TripStop(
      id: id,
      person: person,
      location: location,
      sequenceOrder: sequenceOrder ?? this.sequenceOrder,
    );
  }

  @override
  List<Object?> get props => [id, person, location, sequenceOrder];
}
