import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/profile/profile_bloc.dart';
import 'package:map_my_friends/bloc/profile/profile_event.dart';
import 'package:map_my_friends/bloc/profile/profile_state.dart';
import 'package:map_my_friends/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

/// A full server profile payload, keyed exactly as the API returns it.
Map<String, dynamic> _profileJson({String? image = 'https://cdn/p.png'}) => {
  'username': 'brandon',
  'email': 'b@example.com',
  'first_name': 'Brandon',
  'last_name': 'L',
  'profile_image': image,
  'city': 'Chicago',
  'state': 'IL',
  'country': 'USA',
  'street': '1 Main St',
  'birth_date': '1990-01-02',
  'phone_number': '+15555550100',
  'pin_color': '#123456',
  'pin_style': 'circle',
  'pin_icon_type': 'emoji',
  'pin_emoji': '🙂',
  'distance_unit': 'imperial',
};

/// Matches a ProfileLoaded carrying every field of [_profileJson], with the
/// image URL checked by [image].
Matcher _loadedFromJson({required Matcher image}) => isA<ProfileLoaded>()
    .having((s) => s.username, 'username', 'brandon')
    .having((s) => s.email, 'email', 'b@example.com')
    .having((s) => s.firstName, 'firstName', 'Brandon')
    .having((s) => s.lastName, 'lastName', 'L')
    .having((s) => s.profileImageUrl, 'profileImageUrl', image)
    .having((s) => s.city, 'city', 'Chicago')
    .having((s) => s.state, 'state', 'IL')
    .having((s) => s.country, 'country', 'USA')
    .having((s) => s.street, 'street', '1 Main St')
    .having((s) => s.birthDate, 'birthDate', '1990-01-02')
    .having((s) => s.phoneNumber, 'phoneNumber', '+15555550100')
    .having((s) => s.pinColor, 'pinColor', '#123456')
    .having((s) => s.pinStyle, 'pinStyle', 'circle')
    .having((s) => s.pinIconType, 'pinIconType', 'emoji')
    .having((s) => s.pinEmoji, 'pinEmoji', '🙂')
    .having((s) => s.distanceUnit, 'distanceUnit', 'imperial');

void main() {
  late MockAuthService auth;

  const previous = ProfileLoaded(username: 'brandon', city: 'Old City');

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    auth = MockAuthService();
  });

  test('initial state is ProfileInitial', () {
    final bloc = ProfileBloc(authService: auth);
    expect(bloc.state, ProfileInitial());
    bloc.close();
  });

  group('LoadProfile', () {
    blocTest<ProfileBloc, ProfileState>(
      'maps every profile field and cache-busts the image with ?t=',
      build: () {
        when(() => auth.getProfile()).thenAnswer((_) async => _profileJson());
        return ProfileBloc(authService: auth);
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        ProfileLoading(),
        _loadedFromJson(image: matches(r'^https://cdn/p\.png\?t=\d+$')),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'appends &t= when the image URL already has a query string',
      build: () {
        when(() => auth.getProfile()).thenAnswer(
          (_) async => _profileJson(image: 'https://cdn/p.png?sig=abc'),
        );
        return ProfileBloc(authService: auth);
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        ProfileLoading(),
        _loadedFromJson(image: matches(r'^https://cdn/p\.png\?sig=abc&t=\d+$')),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'keeps a missing image as null instead of inventing a URL',
      build: () {
        when(
          () => auth.getProfile(),
        ).thenAnswer((_) async => _profileJson(image: null));
        return ProfileBloc(authService: auth);
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [ProfileLoading(), _loadedFromJson(image: isNull)],
    );

    blocTest<ProfileBloc, ProfileState>(
      'strips the "Exception: " prefix from the error message',
      build: () {
        when(
          () => auth.getProfile(),
        ).thenThrow(Exception('Failed to load profile'));
        return ProfileBloc(authService: auth);
      },
      act: (bloc) => bloc.add(LoadProfile()),
      expect: () => [
        ProfileLoading(),
        const ProfileError(message: 'Failed to load profile'),
      ],
    );
  });

  group('UpdateProfile', () {
    blocTest<ProfileBloc, ProfileState>(
      'sends every field to the service and emits the saved profile',
      build: () {
        when(
          () => auth.updateProfile(
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            city: any(named: 'city'),
            state: any(named: 'state'),
            country: any(named: 'country'),
            street: any(named: 'street'),
            birthDate: any(named: 'birthDate'),
            phoneNumber: any(named: 'phoneNumber'),
            pinColor: any(named: 'pinColor'),
            pinStyle: any(named: 'pinStyle'),
            pinIconType: any(named: 'pinIconType'),
            pinEmoji: any(named: 'pinEmoji'),
            distanceUnit: any(named: 'distanceUnit'),
          ),
        ).thenAnswer((_) async => _profileJson());
        return ProfileBloc(authService: auth);
      },
      seed: () => previous,
      act: (bloc) => bloc.add(
        const UpdateProfile(
          firstName: 'Brandon',
          lastName: 'L',
          city: 'Chicago',
          state: 'IL',
          country: 'USA',
          street: '1 Main St',
          birthDate: '1990-01-02',
          phoneNumber: '+15555550100',
          pinColor: '#123456',
          pinStyle: 'circle',
          pinIconType: 'emoji',
          pinEmoji: '🙂',
          distanceUnit: 'imperial',
        ),
      ),
      expect: () => [
        ProfileUpdating(),
        _loadedFromJson(image: matches(r'^https://cdn/p\.png\?t=\d+$')),
      ],
      verify: (_) {
        verify(
          () => auth.updateProfile(
            firstName: 'Brandon',
            lastName: 'L',
            city: 'Chicago',
            state: 'IL',
            country: 'USA',
            street: '1 Main St',
            birthDate: '1990-01-02',
            phoneNumber: '+15555550100',
            pinColor: '#123456',
            pinStyle: 'circle',
            pinIconType: 'emoji',
            pinEmoji: '🙂',
            distanceUnit: 'imperial',
          ),
        ).called(1);
      },
    );

    blocTest<ProfileBloc, ProfileState>(
      'restores the previous profile, then reports the error',
      build: () {
        when(
          () => auth.updateProfile(city: any(named: 'city')),
        ).thenThrow(Exception('Address could not be geocoded'));
        return ProfileBloc(authService: auth);
      },
      seed: () => previous,
      act: (bloc) => bloc.add(const UpdateProfile(city: 'Nowhere')),
      expect: () => [
        ProfileUpdating(),
        previous,
        const ProfileError(message: 'Address could not be geocoded'),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'only reports the error when there was no loaded profile to restore',
      build: () {
        when(
          () => auth.updateProfile(city: any(named: 'city')),
        ).thenThrow(Exception('boom'));
        return ProfileBloc(authService: auth);
      },
      act: (bloc) => bloc.add(const UpdateProfile(city: 'Nowhere')),
      expect: () => [ProfileUpdating(), const ProfileError(message: 'boom')],
    );
  });

  group('UploadProfileImage', () {
    final bytes = Uint8List.fromList([1, 2, 3]);

    blocTest<ProfileBloc, ProfileState>(
      'uploads with the default name and cache-busts the new image',
      build: () {
        when(
          () => auth.uploadProfileImage(any(), any()),
        ).thenAnswer((_) async => _profileJson(image: 'https://cdn/new.png'));
        return ProfileBloc(authService: auth);
      },
      seed: () => previous,
      act: (bloc) => bloc.add(UploadProfileImage(imageBytes: bytes)),
      expect: () => [
        ProfileUpdating(),
        _loadedFromJson(image: matches(r'^https://cdn/new\.png\?t=\d+$')),
      ],
      verify: (_) {
        verify(
          () => auth.uploadProfileImage(bytes, 'profile_image.png'),
        ).called(1);
      },
    );

    blocTest<ProfileBloc, ProfileState>(
      'passes a custom image name through',
      build: () {
        when(
          () => auth.uploadProfileImage(any(), any()),
        ).thenAnswer((_) async => _profileJson());
        return ProfileBloc(authService: auth);
      },
      act: (bloc) =>
          bloc.add(UploadProfileImage(imageBytes: bytes, imageName: 'me.jpg')),
      skip: 1,
      expect: () => [isA<ProfileLoaded>()],
      verify: (_) {
        verify(() => auth.uploadProfileImage(bytes, 'me.jpg')).called(1);
      },
    );

    blocTest<ProfileBloc, ProfileState>(
      'restores the previous profile, then reports the upload error',
      build: () {
        when(
          () => auth.uploadProfileImage(any(), any()),
        ).thenThrow(Exception('Image too large'));
        return ProfileBloc(authService: auth);
      },
      seed: () => previous,
      act: (bloc) => bloc.add(UploadProfileImage(imageBytes: bytes)),
      expect: () => [
        ProfileUpdating(),
        previous,
        const ProfileError(message: 'Image too large'),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'only reports the upload error when nothing was loaded',
      build: () {
        when(
          () => auth.uploadProfileImage(any(), any()),
        ).thenThrow(Exception('Image too large'));
        return ProfileBloc(authService: auth);
      },
      act: (bloc) => bloc.add(UploadProfileImage(imageBytes: bytes)),
      expect: () => [
        ProfileUpdating(),
        const ProfileError(message: 'Image too large'),
      ],
    );
  });

  group('ProfileLoaded.copyWith', () {
    test('replaces only the given fields', () {
      const full = ProfileLoaded(
        username: 'u',
        email: 'e',
        firstName: 'f',
        lastName: 'l',
        profileImageUrl: 'i',
        city: 'c',
        state: 's',
        country: 'co',
        street: 'st',
        birthDate: 'b',
        phoneNumber: 'p',
        pinColor: 'pc',
        pinStyle: 'ps',
        pinIconType: 'pi',
        pinEmoji: 'pe',
        distanceUnit: 'd',
      );
      expect(full.copyWith(), full);
      final changed = full.copyWith(city: 'Paris', pinEmoji: '🗼');
      expect(changed.city, 'Paris');
      expect(changed.pinEmoji, '🗼');
      expect(changed, full.copyWith(city: 'Paris', pinEmoji: '🗼'));
      expect(changed.username, 'u');
      expect(changed.distanceUnit, 'd');
      expect(changed, isNot(full));

      final all = full.copyWith(
        username: 'U',
        email: 'E',
        firstName: 'F',
        lastName: 'L',
        profileImageUrl: 'I',
        city: 'C',
        state: 'S',
        country: 'CO',
        street: 'ST',
        birthDate: 'B',
        phoneNumber: 'P',
        pinColor: 'PC',
        pinStyle: 'PS',
        pinIconType: 'PI',
        pinEmoji: 'PE',
        distanceUnit: 'D',
      );
      expect(all.props, [
        'U',
        'E',
        'F',
        'L',
        'I',
        'C',
        'S',
        'CO',
        'ST',
        'B',
        'P',
        'PC',
        'PS',
        'PI',
        'PE',
        'D',
      ]);
    });
  });

  test('profile events have value equality', () {
    expect(const UpdateProfile(city: 'A'), const UpdateProfile(city: 'A'));
    expect(const UpdateProfile(city: 'A'), isNot(const UpdateProfile()));
    final bytes = Uint8List.fromList([1]);
    expect(
      UploadProfileImage(imageBytes: bytes),
      UploadProfileImage(imageBytes: bytes, imageName: 'profile_image.png'),
    );
    expect(LoadProfile(), LoadProfile());
  });
}
