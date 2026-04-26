import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import 'person.dart';
import 'airport.dart';
import 'station.dart';

enum TripStatus {
  draft('DRAFT'),
  booked('BOOKED'),
  cancelled('CANCELLED');

  final String value;
  const TripStatus(this.value);

  static TripStatus fromString(String value) {
    return TripStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TripStatus.draft,
    );
  }
}

class TripStop extends Equatable {
  final String? id;
  final List<Person> people;
  final Airport? airport;
  final Station? station;
  final LatLng location;
  final int sequenceOrder;

  const TripStop({
    this.id,
    this.people = const [],
    this.airport,
    this.station,
    required this.location,
    required this.sequenceOrder,
  });

  TripStop copyWith({
    int? sequenceOrder,
    List<Person>? people,
    Airport? airport,
    Station? station,
    LatLng? location,
  }) {
    return TripStop(
      id: id,
      people: people ?? this.people,
      airport: airport ?? this.airport,
      station: station ?? this.station,
      location: location ?? this.location,
      sequenceOrder: sequenceOrder ?? this.sequenceOrder,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'people': people.map((p) => p.id).toList(),
      'airport': airport?.id,
      'station': station?.id,
      'sequence_order': sequenceOrder,
      'location': {
        'type': 'Point',
        'coordinates': [location.longitude, location.latitude],
      },
    };
  }

  factory TripStop.fromJson(Map<String, dynamic> json) {
    final locationData = json['location'] as Map<String, dynamic>;
    final coordinates = locationData['coordinates'] as List;

    List<Person> peopleList = [];
    if (json['people_detail'] != null) {
      peopleList = (json['people_detail'] as List)
          .map((p) => Person.fromJson(p as Map<String, dynamic>))
          .toList();
    } else if (json['person_detail'] != null) {
      // Legacy support/fallback
      peopleList = [Person.fromJson(json['person_detail'])];
    }

    return TripStop(
      id: json['id']?.toString(),
      people: peopleList,
      airport: json['airport_detail'] != null
          ? Airport.fromGeoJson(json['airport_detail'])
          : null,
      station: json['station_detail'] != null
          ? Station.fromGeoJson(json['station_detail'])
          : null,
      location: LatLng(coordinates[1] as double, coordinates[0] as double),
      sequenceOrder: json['sequence_order'] as int,
    );
  }

  @override
  List<Object?> get props =>
      [id, people, airport, station, location, sequenceOrder];
}

class Trip extends Equatable {
  final int? id;
  final String name;
  final DateTime date;
  final TripStatus status;
  final List<TripStop> stops;

  const Trip({
    this.id,
    required this.name,
    required this.date,
    this.status = TripStatus.draft,
    this.stops = const [],
  });

  Trip copyWith({
    int? id,
    String? name,
    DateTime? date,
    TripStatus? status,
    List<TripStop>? stops,
  }) {
    return Trip(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      status: status ?? this.status,
      stops: stops ?? this.stops,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'date': date.toIso8601String().split('T')[0],
      'status': status.value,
      'stops': stops.map((s) => s.toJson()).toList(),
    };
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as int?,
      name: json['name'] as String,
      date: DateTime.parse(json['date'] as String),
      status: TripStatus.fromString(json['status'] as String),
      stops: (json['stops'] as List)
          .map((s) => TripStop.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [id, name, date, status, stops];
}
