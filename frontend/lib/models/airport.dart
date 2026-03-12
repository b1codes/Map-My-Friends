class Airport {
  final int? id;
  final String name;
  final String iataCode;
  final String? icaoCode;
  final String airportType;
  final String city;
  final String country;
  final String? continent;
  final double latitude;
  final double longitude;
  final double? distanceKm;

  Airport({
    this.id,
    required this.name,
    required this.iataCode,
    this.icaoCode,
    required this.airportType,
    required this.city,
    required this.country,
    this.continent,
    required this.latitude,
    required this.longitude,
    this.distanceKm,
  });

  /// Parse from bundled airports.json (compact format)
  factory Airport.fromJson(Map<String, dynamic> json) {
    return Airport(
      name: json['name'] as String,
      iataCode: json['iata'] as String,
      airportType: json['type'] as String,
      city: json['city'] as String? ?? '',
      country: json['country'] as String? ?? '',
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
    );
  }

  /// Parse from backend GeoJSON response (nearest airports endpoint)
  factory Airport.fromGeoJson(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>;
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List<dynamic>?;

    return Airport(
      id: json['id'] as int?,
      name: properties['name'] as String,
      iataCode: properties['iata_code'] as String,
      icaoCode: properties['icao_code'] as String?,
      airportType: properties['airport_type'] as String,
      city: properties['city'] as String? ?? '',
      country: properties['country'] as String? ?? '',
      continent: properties['continent'] as String?,
      // GeoJSON Point coordinates are [longitude, latitude]
      latitude: coordinates != null ? (coordinates[1] as num).toDouble() : 0.0,
      longitude: coordinates != null ? (coordinates[0] as num).toDouble() : 0.0,
      distanceKm: (properties['distance_km'] as num?)?.toDouble(),
    );
  }
}
