import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/auth/auth_bloc.dart';
import 'package:map_my_friends/bloc/auth/auth_event.dart';
import 'package:map_my_friends/bloc/auth/auth_state.dart';
import 'package:map_my_friends/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late AuthService authService;
  late AuthBloc authBloc;

  setUp(() {
    authService = MockAuthService();
    authBloc = AuthBloc(authService: authService);
  });

  tearDown(() {
    authBloc.close();
  });

  group('AuthBloc', () {
    test('initial state is AuthInitial', () {
      expect(authBloc.state, AuthInitial());
    });

    group('CheckAuthStatus', () {
      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, Authenticated] when tokens are stored',
        build: () {
          when(() => authService.getStoredTokens()).thenAnswer(
            (_) async => {
              'access': 'access_token',
              'refresh': 'refresh_token',
              'username': 'testuser',
            },
          );
          return authBloc;
        },
        act: (bloc) => bloc.add(CheckAuthStatus()),
        expect: () => [
          AuthLoading(),
          const Authenticated(
            accessToken: 'access_token',
            refreshToken: 'refresh_token',
            username: 'testuser',
          ),
        ],
      );

      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, Unauthenticated] when no tokens are stored',
        build: () {
          when(
            () => authService.getStoredTokens(),
          ).thenAnswer((_) async => null);
          return authBloc;
        },
        act: (bloc) => bloc.add(CheckAuthStatus()),
        expect: () => [AuthLoading(), const Unauthenticated()],
      );

      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, Unauthenticated] when an error occurs',
        build: () {
          when(
            () => authService.getStoredTokens(),
          ).thenThrow(Exception('Error'));
          return authBloc;
        },
        act: (bloc) => bloc.add(CheckAuthStatus()),
        expect: () => [AuthLoading(), const Unauthenticated()],
      );
    });

    group('LoginRequested', () {
      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, Authenticated] on successful login',
        build: () {
          when(() => authService.login('testuser', 'password')).thenAnswer(
            (_) async => {
              'access': 'access_token',
              'refresh': 'refresh_token',
              'username': 'testuser',
            },
          );
          return authBloc;
        },
        act: (bloc) => bloc.add(
          const LoginRequested(username: 'testuser', password: 'password'),
        ),
        expect: () => [
          AuthLoading(),
          const Authenticated(
            accessToken: 'access_token',
            refreshToken: 'refresh_token',
            username: 'testuser',
          ),
        ],
      );

      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, AuthError] on failed login',
        build: () {
          when(
            () => authService.login('testuser', 'password'),
          ).thenThrow(Exception('Invalid credentials'));
          return authBloc;
        },
        act: (bloc) => bloc.add(
          const LoginRequested(username: 'testuser', password: 'password'),
        ),
        expect: () => [
          AuthLoading(),
          const AuthError(message: 'Invalid credentials'),
        ],
      );
    });

    group('RegisterRequested', () {
      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, RegistrationSuccess] on successful registration',
        build: () {
          when(
            () => authService.register(
              username: 'testuser',
              email: 'test@example.com',
              password: 'password',
              passwordConfirm: 'password',
            ),
          ).thenAnswer((_) async {});
          return authBloc;
        },
        act: (bloc) => bloc.add(
          const RegisterRequested(
            username: 'testuser',
            email: 'test@example.com',
            password: 'password',
            passwordConfirm: 'password',
          ),
        ),
        expect: () => [AuthLoading(), const RegistrationSuccess()],
      );

      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, AuthError] on failed registration',
        build: () {
          when(
            () => authService.register(
              username: 'testuser',
              email: 'test@example.com',
              password: 'password',
              passwordConfirm: 'password',
            ),
          ).thenThrow(Exception('Registration failed'));
          return authBloc;
        },
        act: (bloc) => bloc.add(
          const RegisterRequested(
            username: 'testuser',
            email: 'test@example.com',
            password: 'password',
            passwordConfirm: 'password',
          ),
        ),
        expect: () => [
          AuthLoading(),
          const AuthError(message: 'Registration failed'),
        ],
      );
    });

    group('DevLoginRequested', () {
      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, Authenticated] on a successful dev sign-in',
        build: () {
          when(() => authService.loginAsDev()).thenAnswer(
            (_) async => {
              'access': 'dev_access',
              'refresh': 'dev_refresh',
              'username': 'demo',
            },
          );
          return authBloc;
        },
        act: (bloc) => bloc.add(const DevLoginRequested()),
        expect: () => [
          AuthLoading(),
          const Authenticated(
            accessToken: 'dev_access',
            refreshToken: 'dev_refresh',
            username: 'demo',
          ),
        ],
      );

      blocTest<AuthBloc, AuthState>(
        'surfaces the seed hint when the local stack is not running',
        build: () {
          when(
            () => authService.loginAsDev(),
          ).thenThrow(Exception('DEV sign-in failed: make up && make seed'));
          return authBloc;
        },
        act: (bloc) => bloc.add(const DevLoginRequested()),
        expect: () => [
          AuthLoading(),
          const AuthError(message: 'DEV sign-in failed: make up && make seed'),
        ],
      );
    });

    group('LogoutRequested', () {
      blocTest<AuthBloc, AuthState>(
        'emits [Unauthenticated] on logout',
        build: () {
          when(() => authService.logout()).thenAnswer((_) async {});
          return authBloc;
        },
        act: (bloc) => bloc.add(LogoutRequested()),
        expect: () => [
          const Unauthenticated(message: 'You have been logged out.'),
        ],
      );
    });
  });
}
