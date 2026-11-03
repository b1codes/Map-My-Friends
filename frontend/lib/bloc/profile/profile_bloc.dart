import 'package:flutter_bloc/flutter_bloc.dart';
import 'profile_event.dart';
import 'profile_state.dart';
import '../../services/auth_service.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final AuthService _authService;

  ProfileBloc({AuthService? authService})
    : _authService = authService ?? AuthService(),
      super(ProfileInitial()) {
    on<LoadProfile>(_onLoadProfile);
    on<UpdateProfile>(_onUpdateProfile);
    on<UploadProfileImage>(_onUploadProfileImage);
  }

  Future<void> _onLoadProfile(
    LoadProfile event,
    Emitter<ProfileState> emit,
  ) async {
    emit(ProfileLoading());

    try {
      final profile = await _authService.getProfile();
      emit(_loaded(profile));
    } catch (e) {
      emit(ProfileError(message: e.toString().replaceFirst('Exception: ', '')));
    }
  }

  Future<void> _onUpdateProfile(
    UpdateProfile event,
    Emitter<ProfileState> emit,
  ) async {
    final currentState = state;
    emit(ProfileUpdating());

    try {
      final profile = await _authService.updateProfile(
        firstName: event.firstName,
        lastName: event.lastName,
        city: event.city,
        state: event.state,
        country: event.country,
        street: event.street,
        birthDate: event.birthDate,
        phoneNumber: event.phoneNumber,
        pinColor: event.pinColor,
        pinStyle: event.pinStyle,
        pinIconType: event.pinIconType,
        pinEmoji: event.pinEmoji,
        distanceUnit: event.distanceUnit,
      );
      emit(_loaded(profile));
    } catch (e) {
      if (currentState is ProfileLoaded) {
        emit(currentState);
      }
      emit(ProfileError(message: e.toString().replaceFirst('Exception: ', '')));
    }
  }

  Future<void> _onUploadProfileImage(
    UploadProfileImage event,
    Emitter<ProfileState> emit,
  ) async {
    final currentState = state;
    emit(ProfileUpdating());

    try {
      final profile = await _authService.uploadProfileImage(
        event.imageBytes,
        event.imageName,
      );
      emit(_loaded(profile));
    } catch (e) {
      if (currentState is ProfileLoaded) {
        emit(currentState);
      }
      emit(ProfileError(message: e.toString().replaceFirst('Exception: ', '')));
    }
  }

  /// Builds the loaded state from a profile response. A field of the wrong
  /// type throws, which the caller reports as a [ProfileError].
  ProfileLoaded _loaded(Map<String, dynamic> profile) => ProfileLoaded(
    username: profile['username'] as String?,
    email: profile['email'] as String?,
    firstName: profile['first_name'] as String?,
    lastName: profile['last_name'] as String?,
    profileImageUrl: _processImageUrl(profile['profile_image'] as String?),
    city: profile['city'] as String?,
    state: profile['state'] as String?,
    country: profile['country'] as String?,
    street: profile['street'] as String?,
    birthDate: profile['birth_date'] as String?,
    phoneNumber: profile['phone_number'] as String?,
    pinColor: profile['pin_color'] as String?,
    pinStyle: profile['pin_style'] as String?,
    pinIconType: profile['pin_icon_type'] as String?,
    pinEmoji: profile['pin_emoji'] as String?,
    distanceUnit: profile['distance_unit'] as String?,
  );

  String? _processImageUrl(String? url) {
    if (url == null) return null;
    // Add timestamp to force cache refresh
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    if (url.contains('?')) {
      return '$url&t=$timestamp';
    }
    return '$url?t=$timestamp';
  }
}
