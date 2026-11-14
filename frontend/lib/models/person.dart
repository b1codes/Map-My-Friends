import '../utils/pin_color.dart';
import 'airport.dart';
import 'station.dart';

class Person {
  final String id;
  final String firstName;
  final String lastName;
  final String relationshipTag;
  final String city;
  final String state;
  final String country;
  final String? street;
  final DateTime? birthday;
  final String? phoneNumber;
  final double? latitude;
  final double? longitude;
  final String? profileImageUrl;
  final String? timezone;
  final String pinColor;
  final String pinStyle;
  final String pinIconType;
  final String? pinEmoji;
  final String? preferredAirportId;
  final String? preferredStationId;
  final Airport? preferredAirport;
  final Station? preferredStation;

  /// Target rhythm for staying in touch, in days. When null, the app derives a
  /// default from [relationshipTag] (see ContactRecency).
  final int? contactCadenceDays;

  /// Read-only recency summary from the server: the most recent touchpoint.
  final DateTime? lastContactedAt;
  final String? lastContactChannel;

  Person({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.relationshipTag,
    required this.city,
    required this.state,
    required this.country,
    this.street,
    this.birthday,
    this.phoneNumber,
    this.latitude,
    this.longitude,
    this.profileImageUrl,
    this.timezone,
    this.pinColor = '#F44336',
    this.pinStyle = 'teardrop',
    this.pinIconType = 'none',
    this.pinEmoji,
    this.preferredAirportId,
    this.preferredStationId,
    this.preferredAirport,
    this.preferredStation,
    this.contactCadenceDays,
    this.lastContactedAt,
    this.lastContactChannel,
  });

  /// Parses the recency summary fields shared by both JSON shapes.
  static int? _cadenceFrom(Map<String, dynamic> src) =>
      (src['contact_cadence_days'] as num?)?.toInt();

  static DateTime? _lastContactedFrom(Map<String, dynamic> src) {
    final raw = src['last_contacted_at'] as String?;
    if (raw == null) return null;
    return DateTime.parse(raw).toLocal();
  }

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      relationshipTag: json['tag'] as String,
      city: json['city'] as String,
      state: json['state'] as String,
      country: json['country'] as String,
      street: json['street'] as String?,
      birthday: json['birthday'] != null
          ? DateTime.parse(json['birthday'] as String)
          : null,
      phoneNumber: json['phone_number'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      profileImageUrl: json['profile_image'] as String?,
      timezone: json['timezone'] as String?,
      pinColor: pinColorHexOrDefault(json['pin_color'] as String?, '#F44336'),
      pinStyle: json['pin_style'] as String? ?? 'teardrop',
      pinIconType: json['pin_icon_type'] as String? ?? 'none',
      pinEmoji: json['pin_emoji'] as String?,
      preferredAirportId: json['preferred_airport']?.toString(),
      preferredStationId: json['preferred_station']?.toString(),
      preferredAirport: json['preferred_airport_detail'] != null
          ? Airport.fromGeoJson(
              json['preferred_airport_detail'] as Map<String, dynamic>,
            )
          : null,
      preferredStation: json['preferred_station_detail'] != null
          ? Station.fromGeoJson(
              json['preferred_station_detail'] as Map<String, dynamic>,
            )
          : null,
      contactCadenceDays: _cadenceFrom(json),
      lastContactedAt: _lastContactedFrom(json),
      lastContactChannel: json['last_contact_channel'] as String?,
    );
  }

  factory Person.fromGeoJson(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>;
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List<dynamic>?;

    return Person(
      id: json['id'].toString(),
      firstName: properties['first_name'] as String,
      lastName: properties['last_name'] as String,
      relationshipTag: properties['tag'] as String,
      city: properties['city'] as String,
      state: properties['state'] as String,
      country: properties['country'] as String,
      street: properties['street'] as String?,
      birthday: properties['birthday'] != null
          ? DateTime.parse(properties['birthday'] as String)
          : null,
      phoneNumber: properties['phone_number'] as String?,
      // GeoJSON Point coordinates are [longitude, latitude]
      latitude: coordinates != null ? (coordinates[1] as num).toDouble() : null,
      longitude: coordinates != null
          ? (coordinates[0] as num).toDouble()
          : null,
      profileImageUrl: properties['profile_image'] as String?,
      timezone: properties['timezone'] as String?,
      pinColor: pinColorHexOrDefault(
        properties['pin_color'] as String?,
        '#F44336',
      ),
      pinStyle: properties['pin_style'] as String? ?? 'teardrop',
      pinIconType: properties['pin_icon_type'] as String? ?? 'none',
      pinEmoji: properties['pin_emoji'] as String?,
      preferredAirportId: properties['preferred_airport']?.toString(),
      preferredStationId: properties['preferred_station']?.toString(),
      preferredAirport: properties['preferred_airport_detail'] != null
          ? Airport.fromGeoJson(
              properties['preferred_airport_detail'] as Map<String, dynamic>,
            )
          : null,
      preferredStation: properties['preferred_station_detail'] != null
          ? Station.fromGeoJson(
              properties['preferred_station_detail'] as Map<String, dynamic>,
            )
          : null,
      contactCadenceDays: _cadenceFrom(properties),
      lastContactedAt: _lastContactedFrom(properties),
      lastContactChannel: properties['last_contact_channel'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'first_name': firstName,
      'last_name': lastName,
      'tag': relationshipTag,
      'city': city,
      'state': state,
      'country': country,
      'pin_color': pinColor,
      'pin_style': pinStyle,
      'pin_icon_type': pinIconType,
    };
    // Only include optional fields if they have values to avoid
    // FormData sending the string "null" for null values.
    if (street != null) data['street'] = street;
    if (birthday != null) data['birthday'] = birthday!.toIso8601String();
    if (phoneNumber != null) data['phone_number'] = phoneNumber;
    if (pinEmoji != null) data['pin_emoji'] = pinEmoji;
    if (preferredAirportId != null) {
      data['preferred_airport'] = preferredAirportId;
    }
    if (preferredStationId != null) {
      data['preferred_station'] = preferredStationId;
    }
    // last_contacted_at / last_contact_channel are server-derived (read-only),
    // so they are intentionally never sent back.
    if (contactCadenceDays != null) {
      data['contact_cadence_days'] = contactCadenceDays.toString();
    }
    return data;
  }

  Person copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? relationshipTag,
    String? city,
    String? state,
    String? country,
    String? street,
    DateTime? birthday,
    String? phoneNumber,
    double? latitude,
    double? longitude,
    String? profileImageUrl,
    String? timezone,
    String? pinColor,
    String? pinStyle,
    String? pinIconType,
    String? pinEmoji,
    String? preferredAirportId,
    String? preferredStationId,
    Airport? preferredAirport,
    Station? preferredStation,
    int? contactCadenceDays,
    DateTime? lastContactedAt,
    String? lastContactChannel,
  }) {
    return Person(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      relationshipTag: relationshipTag ?? this.relationshipTag,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      street: street ?? this.street,
      birthday: birthday ?? this.birthday,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      timezone: timezone ?? this.timezone,
      pinColor: pinColor ?? this.pinColor,
      pinStyle: pinStyle ?? this.pinStyle,
      pinIconType: pinIconType ?? this.pinIconType,
      pinEmoji: pinEmoji ?? this.pinEmoji,
      preferredAirportId: preferredAirportId ?? this.preferredAirportId,
      preferredStationId: preferredStationId ?? this.preferredStationId,
      preferredAirport: preferredAirport ?? this.preferredAirport,
      preferredStation: preferredStation ?? this.preferredStation,
      contactCadenceDays: contactCadenceDays ?? this.contactCadenceDays,
      lastContactedAt: lastContactedAt ?? this.lastContactedAt,
      lastContactChannel: lastContactChannel ?? this.lastContactChannel,
    );
  }
}
