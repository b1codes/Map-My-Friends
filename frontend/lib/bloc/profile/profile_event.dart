import 'dart:typed_data';
import 'package:equatable/equatable.dart';

abstract class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object?> get props => [];
}

/// Load the user's profile from the server
class LoadProfile extends ProfileEvent {}

/// Update profile fields (address)
class UpdateProfile extends ProfileEvent {
  final String? firstName;
  final String? lastName;
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

  const UpdateProfile({
    this.firstName,
    this.lastName,
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
    firstName,
    lastName,
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
}

/// Upload a new profile image
class UploadProfileImage extends ProfileEvent {
  final Uint8List imageBytes;
  final String imageName;

  const UploadProfileImage({
    required this.imageBytes,
    this.imageName = 'profile_image.png',
  });

  @override
  List<Object?> get props => [imageBytes, imageName];
}
