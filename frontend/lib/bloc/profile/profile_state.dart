import 'package:equatable/equatable.dart';

abstract class ProfileState extends Equatable {
  const ProfileState();

  @override
  List<Object?> get props => [];
}

class ProfileInitial extends ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfileLoaded extends ProfileState {
  final String? username;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? profileImageUrl;
  final String? city;
  final String? state;
  final String? country;
  final String? street;
  final String? birthDate;
  final String? phoneNumber;
  final String? pinColor;
  final String? pinStyle;
  final String? pinIconType;
  final String? pinEmoji;
  final String? distanceUnit;

  const ProfileLoaded({
    this.username,
    this.email,
    this.firstName,
    this.lastName,
    this.profileImageUrl,
    this.city,
    this.state,
    this.country,
    this.street,
    this.birthDate,
    this.phoneNumber,
    this.pinColor,
    this.pinStyle,
    this.pinIconType,
    this.pinEmoji,
    this.distanceUnit,
  });

  @override
  List<Object?> get props => [
    username,
    email,
    firstName,
    lastName,
    profileImageUrl,
    city,
    state,
    country,
    street,
    birthDate,
    phoneNumber,
    pinColor,
    pinStyle,
    pinIconType,
    pinEmoji,
    distanceUnit,
  ];

  ProfileLoaded copyWith({
    String? username,
    String? email,
    String? firstName,
    String? lastName,
    String? profileImageUrl,
    String? city,
    String? state,
    String? country,
    String? street,
    String? birthDate,
    String? phoneNumber,
    String? pinColor,
    String? pinStyle,
    String? pinIconType,
    String? pinEmoji,
    String? distanceUnit,
  }) {
    return ProfileLoaded(
      username: username ?? this.username,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      street: street ?? this.street,
      birthDate: birthDate ?? this.birthDate,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      pinColor: pinColor ?? this.pinColor,
      pinStyle: pinStyle ?? this.pinStyle,
      pinIconType: pinIconType ?? this.pinIconType,
      pinEmoji: pinEmoji ?? this.pinEmoji,
      distanceUnit: distanceUnit ?? this.distanceUnit,
    );
  }
}

class ProfileUpdating extends ProfileState {}

class ProfileError extends ProfileState {
  final String message;

  const ProfileError({required this.message});

  @override
  List<Object?> get props => [message];
}
