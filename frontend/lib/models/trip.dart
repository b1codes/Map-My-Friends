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
  final String? snapshotAddress;
  final Map<String, dynamic>? snapshotMetadata;

  const TripStop({
    this.id,
    this.people = const [],
    this.airport,
    this.station,
    required this.location,
    required this.sequenceOrder,
    this.snapshotAddress,
    this.snapshotMetadata,
  });

  TripStop copyWith({
    int? sequenceOrder,
    List<Person>? people,
    Airport? airport,
    Station? station,
    LatLng? location,
    String? snapshotAddress,
    Map<String, dynamic>? snapshotMetadata,
  }) {
    return TripStop(
      id: id,
      people: people ?? this.people,
      airport: airport ?? this.airport,
      station: station ?? this.station,
      location: location ?? this.location,
      sequenceOrder: sequenceOrder ?? this.sequenceOrder,
      snapshotAddress: snapshotAddress ?? this.snapshotAddress,
      snapshotMetadata: snapshotMetadata ?? this.snapshotMetadata,
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
      'snapshot_address': snapshotAddress,
      'snapshot_metadata': snapshotMetadata,
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
      snapshotAddress: json['snapshot_address'] as String?,
      snapshotMetadata: json['snapshot_metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    people,
    airport,
    station,
    location,
    sequenceOrder,
    snapshotAddress,
    snapshotMetadata,
  ];
}

class TripLeg extends Equatable {
  final int? id;
  final int departureStopId;
  final int arrivalStopId;
  final DateTime? departureTime;
  final DateTime? arrivalTime;
  final String transportType;
  final String bookingReference;
  final Map<String, dynamic> ticketData;

  const TripLeg({
    this.id,
    required this.departureStopId,
    required this.arrivalStopId,
    this.departureTime,
    this.arrivalTime,
    this.transportType = 'CAR',
    this.bookingReference = '',
    this.ticketData = const {},
  });

  TripLeg copyWith({
    DateTime? departureTime,
    DateTime? arrivalTime,
    String? transportType,
    String? bookingReference,
    Map<String, dynamic>? ticketData,
  }) {
    return TripLeg(
      id: id,
      departureStopId: departureStopId,
      arrivalStopId: arrivalStopId,
      departureTime: departureTime ?? this.departureTime,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      transportType: transportType ?? this.transportType,
      bookingReference: bookingReference ?? this.bookingReference,
      ticketData: ticketData ?? this.ticketData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'departure_stop': departureStopId,
      'arrival_stop': arrivalStopId,
      'departure_time': departureTime?.toIso8601String(),
      'arrival_time': arrivalTime?.toIso8601String(),
      'transport_type': transportType,
      'booking_reference': bookingReference,
      'ticket_data': ticketData,
    };
  }

  factory TripLeg.fromJson(Map<String, dynamic> json) {
    return TripLeg(
      id: json['id'] as int?,
      departureStopId: json['departure_stop'] as int,
      arrivalStopId: json['arrival_stop'] as int,
      departureTime: json['departure_time'] != null
          ? DateTime.parse(json['departure_time'] as String)
          : null,
      arrivalTime: json['arrival_time'] != null
          ? DateTime.parse(json['arrival_time'] as String)
          : null,
      transportType: json['transport_type'] as String? ?? 'CAR',
      bookingReference: json['booking_reference'] as String? ?? '',
      ticketData: (json['ticket_data'] as Map<String, dynamic>?) ?? const {},
    );
  }

  @override
  List<Object?> get props => [
    id,
    departureStopId,
    arrivalStopId,
    departureTime,
    arrivalTime,
    transportType,
    bookingReference,
    ticketData,
  ];
}

class Trip extends Equatable {
  final int? id;
  final String name;
  final DateTime date; // Legacy
  final DateTime? startDate;
  final DateTime? endDate;
  final TripStatus status;
  final List<TripStop> stops;
  final List<TripLeg> legs;

  const Trip({
    this.id,
    required this.name,
    required this.date,
    this.startDate,
    this.endDate,
    this.status = TripStatus.draft,
    this.stops = const [],
    this.legs = const [],
  });

  Trip copyWith({
    int? id,
    String? name,
    DateTime? date,
    DateTime? startDate,
    DateTime? endDate,
    TripStatus? status,
    List<TripStop>? stops,
    List<TripLeg>? legs,
  }) {
    return Trip(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      stops: stops ?? this.stops,
      legs: legs ?? this.legs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'date': date.toIso8601String().split('T')[0],
      if (startDate != null)
        'start_date': startDate!.toIso8601String().split('T')[0],
      if (endDate != null) 'end_date': endDate!.toIso8601String().split('T')[0],
      'status': status.value,
      'stops': stops.map((s) => s.toJson()).toList(),
      'legs': legs.map((l) => l.toJson()).toList(),
    };
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as int?,
      name: json['name'] as String,
      date: DateTime.parse(json['date'] as String),
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : null,
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      status: TripStatus.fromString(json['status'] as String),
      stops: (json['stops'] as List)
          .map((s) => TripStop.fromJson(s as Map<String, dynamic>))
          .toList(),
      legs: (json['legs'] as List? ?? [])
          .map((l) => TripLeg.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    date,
    startDate,
    endDate,
    status,
    stops,
    legs,
  ];
}
