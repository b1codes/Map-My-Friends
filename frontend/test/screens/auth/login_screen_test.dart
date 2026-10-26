import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/auth/auth_bloc.dart';
import 'package:map_my_friends/bloc/auth/auth_event.dart';
import 'package:map_my_friends/bloc/auth/auth_state.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/screens/auth/forgot_password_screen.dart';
import 'package:map_my_friends/screens/auth/login_screen.dart';
import 'package:map_my_friends/screens/auth/register_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  late MockAuthBloc authBloc;

  setUpAll(() {
    registerFallbackValue(const LoginRequested(username: '', password: ''));
  });

  setUp(() {
    authBloc = MockAuthBloc();
    whenListen(
      authBloc,
      const Stream<AuthState>.empty(),
      initialState: const Unauthenticated(),
    );
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp(
          // Freezes the Ambient Field and the Chromatic Pulse so frames settle.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const LoginScreen(),
        ),
      ),
    );
    // Pre-existing and unrelated to behavior: the "Don't have an account? /
    // Sign Up" row overflows its 420px card under the test font's metrics
    // (see login_screen_dev_test.dart). Drain it.
    tester.takeException();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  final signIn = find.widgetWithText(FilledButton, 'Sign In');

  group('LoginScreen form', () {
    testWidgets('empty submit shows both validation errors and sends nothing', (
      tester,
    ) async {
      await pumpLogin(tester);

      await tapVisible(tester, signIn);

      expect(find.text('Please enter your username'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
      verifyNever(() => authBloc.add(any()));
    });

    testWidgets('a missing password alone blocks the submit', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(field('Username'), 'alice');
      await tapVisible(tester, signIn);

      expect(find.text('Please enter your username'), findsNothing);
      expect(find.text('Please enter your password'), findsOneWidget);
      verifyNever(() => authBloc.add(any()));
    });

    testWidgets('dispatches LoginRequested with a trimmed username and the '
        'password verbatim', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(field('Username'), '  alice  ');
      await tester.enterText(field('Password'), ' s3cret ');
      await tapVisible(tester, signIn);

      verify(
        () => authBloc.add(
          const LoginRequested(username: 'alice', password: ' s3cret '),
        ),
      ).called(1);
    });

    testWidgets('submitting from the password keyboard signs in', (
      tester,
    ) async {
      await pumpLogin(tester);

      await tester.enterText(field('Username'), 'alice');
      await tester.enterText(field('Password'), 'pw');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      verify(
        () => authBloc.add(
          const LoginRequested(username: 'alice', password: 'pw'),
        ),
      ).called(1);
    });

    testWidgets('the eye toggle reveals and re-hides the password', (
      tester,
    ) async {
      await pumpLogin(tester);

      EditableText passwordText() => tester.widget<EditableText>(
        find.descendant(
          of: field('Password'),
          matching: find.byType(EditableText),
        ),
      );

      expect(passwordText().obscureText, isTrue);

      await tapVisible(tester, find.byTooltip('Show password'));
      expect(passwordText().obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);

      await tapVisible(tester, find.byTooltip('Hide password'));
      expect(passwordText().obscureText, isTrue);
    });
  });

  group('LoginScreen social sign-in', () {
    testWidgets('Google dispatches the google-oauth2 Auth0 connection', (
      tester,
    ) async {
      await pumpLogin(tester);

      await tapVisible(tester, find.text('Google'));

      verify(
        () => authBloc.add(
          const Auth0LoginRequested(connection: 'google-oauth2'),
        ),
      ).called(1);
    });

    testWidgets('Apple dispatches the apple Auth0 connection', (tester) async {
      await pumpLogin(tester);

      await tapVisible(tester, find.text('Apple'));

      verify(
        () => authBloc.add(const Auth0LoginRequested(connection: 'apple')),
      ).called(1);
    });

    testWidgets('Unified Sign In dispatches Auth0 with no connection', (
      tester,
    ) async {
      await pumpLogin(tester);

      await tapVisible(tester, find.text('Unified Sign In (Auth0)'));

      verify(() => authBloc.add(const Auth0LoginRequested())).called(1);
    });
  });

  group('LoginScreen while AuthLoading', () {
    setUp(() {
      whenListen(
        authBloc,
        const Stream<AuthState>.empty(),
        initialState: AuthLoading(),
      );
    });

    testWidgets('swaps the Sign In label for the Chromatic Pulse', (
      tester,
    ) async {
      await pumpLogin(tester);

      expect(find.text('Sign In'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(ChromaticPulse),
        ),
        findsOneWidget,
      );
    });

    testWidgets('disables every action and both fields', (tester) async {
      await pumpLogin(tester);

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      for (final button in tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      )) {
        expect(button.onPressed, isNull);
      }
      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        expect(button.onPressed, isNull);
      }
      for (final f in tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      )) {
        expect(f.enabled, isFalse);
      }

      await tester.ensureVisible(find.text('Google'));
      await tester.tap(find.text('Google'), warnIfMissed: false);
      await tester.pump();
      verifyNever(() => authBloc.add(any()));
    });
  });

  group('LoginScreen errors', () {
    testWidgets('an AuthError emitted while on screen is shown as a toast', (
      tester,
    ) async {
      final controller = StreamController<AuthState>();
      addTearDown(controller.close);
      whenListen(
        authBloc,
        controller.stream,
        initialState: const Unauthenticated(),
      );
      await pumpLogin(tester);

      controller.add(const AuthError(message: 'Invalid credentials'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Invalid credentials'), findsOneWidget);
    });

    testWidgets('an AuthError that settled before the screen was built is '
        'shown on the first frame', (tester) async {
      whenListen(
        authBloc,
        const Stream<AuthState>.empty(),
        initialState: const AuthError(message: 'Dev login failed'),
      );
      await pumpLogin(tester);
      await tester.pump();

      expect(find.text('Dev login failed'), findsOneWidget);
    });

    testWidgets('a non-error state shows no toast', (tester) async {
      await pumpLogin(tester);
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('LoginScreen navigation', () {
    testWidgets('Forgot Password? opens the reset screen, and Back to Login '
        'returns', (tester) async {
      await pumpLogin(tester);

      await tapVisible(tester, find.text('Forgot Password?'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);

      await tapVisible(tester, find.text('Back to Login'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('Sign Up opens registration, and Sign In returns', (
      tester,
    ) async {
      await pumpLogin(tester);

      await tapVisible(tester, find.widgetWithText(TextButton, 'Sign Up'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);

      await tapVisible(tester, find.widgetWithText(TextButton, 'Sign In'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
