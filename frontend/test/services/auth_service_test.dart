import 'dart:typed_data';

import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/services/auth_service.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fake_http_adapter.dart';
import 'service_test_support.dart';

class MockAuth0 extends Mock implements Auth0 {}

class MockWebAuthentication extends Mock implements WebAuthentication {}

/// Throws a transport-level failure (no HTTP response at all).
FakeResponse connectionError(RequestOptions request) =>
    throw DioException.connectionError(
      requestOptions: request,
      reason: 'host unreachable',
    );

void main() {
  late FakeHttpAdapter adapter;
  late AuthService auth;

  setUp(() {
    seedTokens();
    adapter = FakeHttpAdapter();
    auth = authServiceOn(adapter);
  });

  test('the app-wide instance is a singleton', () {
    expect(AuthService(), same(AuthService()));
  });

  group('login', () {
    test(
      'posts the credentials and stores both tokens and the username',
      () async {
        adapter.reply('POST', 'user/auth/token/', 200, {
          'access': 'acc-1',
          'refresh': 'ref-1',
        });

        final result = await auth.login('alice', 's3cret');

        expect(result, {
          'access': 'acc-1',
          'refresh': 'ref-1',
          'username': 'alice',
        });
        final request = adapter.requestsTo('POST', 'user/auth/token/').single;
        expect(request.data, {'username': 'alice', 'password': 's3cret'});
        expect(request.baseUrl, testBaseUrl);
        expect(await storedValues(), {
          accessKey: 'acc-1',
          refreshKey: 'ref-1',
          usernameKey: 'alice',
        });
      },
    );

    test('maps a 401 to "Invalid username or password"', () async {
      adapter.reply('POST', 'user/auth/token/', 401, {'detail': 'nope'});

      await expectLater(
        auth.login('alice', 'wrong'),
        throwsA(exceptionWith('Invalid username or password')),
      );
      expect(await storedValues(), isEmpty);
    });

    test('reports other HTTP failures as "Login failed"', () async {
      adapter.reply('POST', 'user/auth/token/', 500, {'detail': 'boom'});

      await expectLater(
        auth.login('alice', 's3cret'),
        throwsA(exceptionStartingWith('Login failed: ')),
      );
    });

    test(
      'reports a network failure as "Login failed" with its reason',
      () async {
        adapter.on('POST', 'user/auth/token/', connectionError);

        await expectLater(
          auth.login('alice', 's3cret'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(
                startsWith('Exception: Login failed: '),
                contains('host unreachable'),
              ),
            ),
          ),
        );
      },
    );

    test('rejects a non-200 success status as invalid credentials', () async {
      adapter.reply('POST', 'user/auth/token/', 202, {'queued': true});

      await expectLater(
        auth.login('alice', 's3cret'),
        throwsA(exceptionWith('Invalid credentials')),
      );
      expect(await storedValues(), isEmpty);
    });
  });

  group('loginAsDev', () {
    // The `!ApiConfig.devLoginEnabled` guard is folded at compile time; with
    // the default dart-defines in a test build it is always enabled, so the
    // "not available in this build" branch is unreachable here.
    test('logs in with the seeded dev credentials', () async {
      adapter.reply('POST', 'user/auth/token/', 200, {
        'access': 'dev-acc',
        'refresh': 'dev-ref',
      });

      final result = await auth.loginAsDev();

      expect(result['username'], 'demo');
      expect(adapter.requestsTo('POST', 'user/auth/token/').single.data, {
        'username': 'demo',
        'password': 'demo12345!',
      });
      expect((await storedValues())[accessKey], 'dev-acc');
    });

    test(
      'explains how to start the local stack when the login fails',
      () async {
        adapter.reply('POST', 'user/auth/token/', 401);

        await expectLater(
          auth.loginAsDev(),
          throwsA(
            exceptionWith(
              'DEV sign-in failed for "demo" at $testBaseUrl\n'
              'Start and seed the local stack: make up && make seed\n'
              '(Invalid username or password)',
            ),
          ),
        );
      },
    );
  });

  group('loginWithAuth0', () {
    // `ApiConfig.auth0ClientId == 'YOUR_AUTH0_CLIENT_ID'` (the mock-login
    // branch) is a compile-time constant comparison. The default dart-define
    // supplies a real client id, so that branch cannot run in this suite.
    late MockAuth0 auth0;
    late MockWebAuthentication webAuth;

    Credentials credentials({
      String accessToken = 'auth0-acc',
      String? refreshToken = 'auth0-ref',
      String? nickname,
      String? name,
      String? email,
    }) => Credentials(
      idToken: 'id-token',
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.utc(2030),
      user: UserProfile(
        sub: 'auth0|123',
        nickname: nickname,
        name: name,
        email: email,
      ),
      tokenType: 'Bearer',
    );

    void stubLogin(Future<Credentials> Function() answer) {
      when(
        () => webAuth.login(
          audience: any(named: 'audience'),
          scopes: any(named: 'scopes'),
          parameters: any(named: 'parameters'),
        ),
      ).thenAnswer((_) => answer());
    }

    setUp(() {
      auth0 = MockAuth0();
      webAuth = MockWebAuthentication();
      when(
        () => auth0.webAuthentication(scheme: any(named: 'scheme')),
      ).thenReturn(webAuth);
      auth = AuthService.forTesting(
        dioFactory: (o) => Dio(o)..httpClientAdapter = adapter,
        auth0: auth0,
      );
    });

    test('stores the Auth0 tokens and the nickname as username', () async {
      stubLogin(
        () async => credentials(nickname: 'nick', name: 'Name', email: 'e@x'),
      );

      final result = await auth.loginWithAuth0();

      expect(result, {
        'access': 'auth0-acc',
        'refresh': 'auth0-ref',
        'username': 'nick',
      });
      expect(await storedValues(), {
        accessKey: 'auth0-acc',
        refreshKey: 'auth0-ref',
        usernameKey: 'nick',
      });
      verify(() => auth0.webAuthentication(scheme: 'demo')).called(1);
      final captured = verify(
        () => webAuth.login(
          audience: captureAny(named: 'audience'),
          scopes: captureAny(named: 'scopes'),
          parameters: captureAny(named: 'parameters'),
        ),
      ).captured;
      // Named captures come back in name order, so pick them out by type.
      expect(
        captured.whereType<String>().single,
        'https://api.mapmyfriends.com/',
      );
      expect(captured.whereType<Set<String>>().single, {
        'openid',
        'profile',
        'email',
        'offline_access',
      });
      expect(captured.whereType<Map<String, String>>().single, isEmpty);
    });

    test('passes the connection through as a login parameter', () async {
      stubLogin(() async => credentials(nickname: 'g'));

      await auth.loginWithAuth0(connection: 'google-oauth2');

      final captured = verify(
        () => webAuth.login(
          audience: any(named: 'audience'),
          scopes: any(named: 'scopes'),
          parameters: captureAny(named: 'parameters'),
        ),
      ).captured;
      expect(captured.single, {'connection': 'google-oauth2'});
    });

    test('falls back from nickname to name', () async {
      stubLogin(() async => credentials(name: 'Full Name', email: 'e@x'));
      expect((await auth.loginWithAuth0())['username'], 'Full Name');
    });

    test('falls back from name to email', () async {
      stubLogin(() async => credentials(email: 'e@x.com'));
      expect((await auth.loginWithAuth0())['username'], 'e@x.com');
    });

    test('falls back to an empty username and refresh token', () async {
      stubLogin(() async => credentials(refreshToken: null));

      final result = await auth.loginWithAuth0();

      expect(result, {'access': 'auth0-acc', 'refresh': '', 'username': ''});
      expect((await storedValues())[refreshKey], '');
    });

    test('wraps an Auth0 failure and stores nothing', () async {
      stubLogin(() async => throw Exception('User cancelled'));

      await expectLater(
        auth.loginWithAuth0(),
        throwsA(exceptionStartingWith('Auth0 Login failed: ')),
      );
      expect(await storedValues(), isEmpty);
    });
  });

  group('register', () {
    test('posts the form, omitting fields that were not given', () async {
      adapter.reply('POST', 'user/auth/register/', 201, {'id': 1});

      await auth.register(
        username: 'bob',
        email: 'bob@example.com',
        password: 'pw1',
        passwordConfirm: 'pw1',
        firstName: 'Bob',
      );

      expect(adapter.requestsTo('POST', 'user/auth/register/').single.data, {
        'username': 'bob',
        'email': 'bob@example.com',
        'password': 'pw1',
        'password_confirm': 'pw1',
        'first_name': 'Bob',
      });
    });

    test('sends last name and the honeypot field when given', () async {
      adapter.reply('POST', 'user/auth/register/', 201);

      await auth.register(
        username: 'bob',
        email: 'bob@example.com',
        password: 'pw1',
        passwordConfirm: 'pw1',
        lastName: 'Builder',
        firstNameHp: 'bot-filled',
      );

      final data =
          adapter.requestsTo('POST', 'user/auth/register/').single.data as Map;
      expect(data['last_name'], 'Builder');
      expect(data['first_name_hp'], 'bot-filled');
      expect(data.containsKey('first_name'), isFalse);
    });

    test('treats a non-201 success as a failure', () async {
      adapter.reply('POST', 'user/auth/register/', 200, {'id': 1});

      await expectLater(
        auth.register(
          username: 'bob',
          email: 'b@x',
          password: 'p',
          passwordConfirm: 'p',
        ),
        throwsA(exceptionWith('Registration failed')),
      );
    });

    test('formats field errors one per line', () async {
      adapter.reply('POST', 'user/auth/register/', 400, {
        'username': ['A user with that username already exists.'],
        'password': ['Too short.', 'Too common.'],
      });

      await expectLater(
        auth.register(
          username: 'bob',
          email: 'b@x',
          password: 'p',
          passwordConfirm: 'p',
        ),
        throwsA(
          exceptionWith(
            'username: A user with that username already exists.\n'
            'password: Too short., Too common.',
          ),
        ),
      );
    });

    test('reports a network failure as "Registration failed"', () async {
      adapter.on('POST', 'user/auth/register/', connectionError);

      await expectLater(
        auth.register(
          username: 'bob',
          email: 'b@x',
          password: 'p',
          passwordConfirm: 'p',
        ),
        throwsA(exceptionStartingWith('Registration failed: ')),
      );
    });
  });

  group('requestPasswordReset', () {
    test('posts the email', () async {
      adapter.reply('POST', 'user/auth/password-reset/', 200, {'ok': true});

      await auth.requestPasswordReset('a@example.com');

      expect(
        adapter.requestsTo('POST', 'user/auth/password-reset/').single.data,
        {'email': 'a@example.com'},
      );
    });

    test('wraps a failure', () async {
      adapter.reply('POST', 'user/auth/password-reset/', 500);

      await expectLater(
        auth.requestPasswordReset('a@example.com'),
        throwsA(exceptionStartingWith('Password reset request failed: ')),
      );
    });
  });

  group('stored session', () {
    test('logout clears every stored key', () async {
      seedTokens(access: 'a', refresh: 'r', username: 'u');

      await auth.logout();

      expect(await storedValues(), isEmpty);
      expect(await auth.getAccessToken(), isNull);
    });

    test('getStoredTokens returns the stored session', () async {
      seedTokens(access: 'a', refresh: 'r', username: 'u');

      expect(await auth.getStoredTokens(), {
        'access': 'a',
        'refresh': 'r',
        'username': 'u',
      });
      expect(await auth.getAccessToken(), 'a');
    });

    test('getStoredTokens defaults a missing username to empty', () async {
      seedTokens(access: 'a', refresh: 'r');

      expect(await auth.getStoredTokens(), {
        'access': 'a',
        'refresh': 'r',
        'username': '',
      });
    });

    test('getStoredTokens is null without both tokens', () async {
      seedTokens(access: 'a', username: 'u');
      expect(await auth.getStoredTokens(), isNull);

      seedTokens(refresh: 'r', username: 'u');
      expect(await auth.getStoredTokens(), isNull);
    });
  });

  group('refreshAccessToken', () {
    test('posts the refresh token and stores the new access token', () async {
      seedTokens(access: 'old', refresh: 'ref', username: 'u');
      adapter.reply('POST', 'user/auth/token/refresh/', 200, {'access': 'new'});

      expect(await auth.refreshAccessToken(), 'new');

      expect(
        adapter.requestsTo('POST', 'user/auth/token/refresh/').single.data,
        {'refresh': 'ref'},
      );
      expect(await storedValues(), {
        accessKey: 'new',
        refreshKey: 'ref',
        usernameKey: 'u',
      });
    });

    test(
      'stores the rotated refresh token when the server sends one',
      () async {
        seedTokens(access: 'old', refresh: 'spent', username: 'u');
        adapter.reply('POST', 'user/auth/token/refresh/', 200, {
          'access': 'new',
          'refresh': 'rotated',
        });

        expect(await auth.refreshAccessToken(), 'new');

        expect(await storedValues(), {
          accessKey: 'new',
          refreshKey: 'rotated',
          usernameKey: 'u',
        });
      },
    );

    test('logs out and returns null when the refresh is rejected', () async {
      seedTokens(access: 'old', refresh: 'expired', username: 'u');
      adapter.reply('POST', 'user/auth/token/refresh/', 401);

      expect(await auth.refreshAccessToken(), isNull);
      expect(await storedValues(), isEmpty);
    });

    test(
      'returns null without a request when no refresh token is stored',
      () async {
        seedTokens(access: 'old');

        expect(await auth.refreshAccessToken(), isNull);
        expect(adapter.requests, isEmpty);
        expect(await auth.getAccessToken(), 'old');
      },
    );
  });

  group('profile', () {
    group('getProfile', () {
      test(
        'fails with "Not authenticated" and no request without a token',
        () async {
          await expectLater(
            auth.getProfile(),
            throwsA(exceptionWith('Not authenticated')),
          );
          expect(adapter.requests, isEmpty);
        },
      );

      test(
        'returns the profile, authenticated with the stored token',
        () async {
          seedTokens(access: 'tok', refresh: 'r');
          adapter.reply('GET', 'user/profile/', 200, {'username': 'alice'});

          expect(await auth.getProfile(), {'username': 'alice'});
          final request = adapter.requestsTo('GET', 'user/profile/').single;
          expect(authHeaderOf(request), 'Bearer tok');
          expect(request.baseUrl, testBaseUrl);
        },
      );

      test('maps a 401 to "Authentication required"', () async {
        seedTokens(access: 'tok', refresh: 'r');
        adapter.reply('GET', 'user/profile/', 401);

        await expectLater(
          auth.getProfile(),
          throwsA(exceptionWith('Authentication required')),
        );
      });

      test('wraps other HTTP failures', () async {
        seedTokens(access: 'tok', refresh: 'r');
        adapter.reply('GET', 'user/profile/', 500);

        await expectLater(
          auth.getProfile(),
          throwsA(exceptionStartingWith('Failed to load profile: ')),
        );
      });

      test('rejects a non-200 success status', () async {
        seedTokens(access: 'tok', refresh: 'r');
        adapter.reply('GET', 'user/profile/', 204);

        await expectLater(
          auth.getProfile(),
          throwsA(exceptionWith('Failed to load profile')),
        );
      });
    });

    group('updateProfile', () {
      setUp(() => seedTokens(access: 'tok', refresh: 'r'));

      test('sends every given field under its snake_case key', () async {
        adapter.reply('PATCH', 'user/profile/', 200, {'ok': true});

        final result = await auth.updateProfile(
          firstName: 'Ada',
          lastName: 'Lovelace',
          city: 'London',
          state: 'England',
          country: 'UK',
          street: '1 St James',
          birthDate: '1815-12-10',
          phoneNumber: '+44 20',
          pinColor: '#00FF00',
          pinStyle: 'circle',
          pinIconType: 'emoji',
          pinEmoji: '🧮',
          distanceUnit: 'km',
        );

        expect(result, {'ok': true});
        final request = adapter.requestsTo('PATCH', 'user/profile/').single;
        expect(authHeaderOf(request), 'Bearer tok');
        expect(request.data, {
          'first_name': 'Ada',
          'last_name': 'Lovelace',
          'city': 'London',
          'state': 'England',
          'country': 'UK',
          'street': '1 St James',
          'birth_date': '1815-12-10',
          'phone_number': '+44 20',
          'pin_color': '#00FF00',
          'pin_style': 'circle',
          'pin_icon_type': 'emoji',
          'pin_emoji': '🧮',
          'distance_unit': 'km',
        });
      });

      test('sends only the fields that were given', () async {
        adapter.reply('PATCH', 'user/profile/', 200, {'ok': true});

        await auth.updateProfile(city: 'Paris', distanceUnit: 'mi');

        expect(adapter.requestsTo('PATCH', 'user/profile/').single.data, {
          'city': 'Paris',
          'distance_unit': 'mi',
        });
      });

      test('fails with "Not authenticated" without a token', () async {
        seedTokens();
        await expectLater(
          auth.updateProfile(city: 'Paris'),
          throwsA(exceptionWith('Not authenticated')),
        );
        expect(adapter.requests, isEmpty);
      });

      test('maps a 401 to "Authentication required"', () async {
        adapter.reply('PATCH', 'user/profile/', 401);
        await expectLater(
          auth.updateProfile(city: 'Paris'),
          throwsA(exceptionWith('Authentication required')),
        );
      });

      test('wraps other HTTP failures', () async {
        adapter.reply('PATCH', 'user/profile/', 400, {
          'city': ['bad'],
        });
        await expectLater(
          auth.updateProfile(city: 'Paris'),
          throwsA(exceptionStartingWith('Failed to update profile: ')),
        );
      });

      test('rejects a non-200 success status', () async {
        adapter.reply('PATCH', 'user/profile/', 202, {'ok': true});
        await expectLater(
          auth.updateProfile(city: 'Paris'),
          throwsA(exceptionWith('Failed to update profile')),
        );
      });
    });

    group('uploadProfileImage', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      setUp(() => seedTokens(access: 'tok', refresh: 'r'));

      test('patches a multipart profile_image part', () async {
        adapter.reply('PATCH', 'user/profile/', 200, {'profile_image': 'u'});

        final result = await auth.uploadProfileImage(bytes, 'me.png');

        expect(result, {'profile_image': 'u'});
        final request = adapter.requestsTo('PATCH', 'user/profile/').single;
        expect(authHeaderOf(request), 'Bearer tok');
        expect(request.contentType, startsWith('multipart/form-data'));
        final form = request.data as FormData;
        expect(form.fields, isEmpty);
        final part = form.files.single;
        expect(part.key, 'profile_image');
        expect(part.value.filename, 'me.png');
        expect(part.value.contentType.toString(), 'image/png');
        expect(part.value.length, bytes.length);
      });

      test('fails with "Not authenticated" without a token', () async {
        seedTokens();
        await expectLater(
          auth.uploadProfileImage(bytes, 'me.png'),
          throwsA(exceptionWith('Not authenticated')),
        );
      });

      test('maps a 401 to "Authentication required"', () async {
        adapter.reply('PATCH', 'user/profile/', 401);
        await expectLater(
          auth.uploadProfileImage(bytes, 'me.png'),
          throwsA(exceptionWith('Authentication required')),
        );
      });

      test('wraps other HTTP failures', () async {
        adapter.reply('PATCH', 'user/profile/', 413);
        await expectLater(
          auth.uploadProfileImage(bytes, 'me.png'),
          throwsA(exceptionStartingWith('Failed to upload profile image: ')),
        );
      });

      test('rejects a non-200 success status', () async {
        adapter.reply('PATCH', 'user/profile/', 201, {'ok': true});
        await expectLater(
          auth.uploadProfileImage(bytes, 'me.png'),
          throwsA(exceptionWith('Failed to upload profile image')),
        );
      });
    });
  });
}
