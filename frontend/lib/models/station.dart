class Station {
  final int? id;
  final String name;
  final int osmId;
  final String? stationType;
  final String? uicRef;
  final String? city;
  final String? country;
  final double latitude;
  final double longitude;
  final double? distanceKm;

  Station({
    this.id,
    required this.name,
    required this.osmId,
    this.stationType,
    this.uicRef,
    this.city,
    this.country,
    required this.latitude,
    required this.longitude,
    this.distanceKm,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      id: json['id'],
      name: json['name'],
      osmId: json['osm_id'],
      stationType: json['station_type'],
      uicRef: json['uic_ref'],
      city: json['city'],
      country: json['country'],
      latitude: json['latitude'] ?? 0.0,
      longitude: json['longitude'] ?? 0.0,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
    );
  }

  factory Station.fromGeoJson(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>;
    final geometry = json['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>?;

    return Station(
      id: json['id'],
      name: properties['name'],
      osmId: properties['osm_id'],
      stationType: properties['station_type'],
      uicRef: properties['uic_ref'],
      city: properties['city'],
      country: properties['country'],
      latitude: coordinates != null ? (coordinates[1] as num).toDouble() : 0.0,
      longitude: coordinates != null ? (coordinates[0] as num).toDouble() : 0.0,
      distanceKm: (properties['distance_km'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'osm_id': osmId,
      'station_type': stationType,
      'uic_ref': uicRef,
      'city': city,
      'country': country,
      'latitude': latitude,
      'longitude': longitude,
      'distance_km': distanceKm,
    };
  }
}
