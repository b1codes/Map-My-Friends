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
import 'package:mocktail/mocktail.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  late MockAuthBloc authBloc;
  late StreamController<AuthState> states;

  setUpAll(() {
    registerFallbackValue(const PasswordResetRequested(email: ''));
  });

  setUp(() {
    authBloc = MockAuthBloc();
    states = StreamController<AuthState>();
    whenListen(authBloc, states.stream, initialState: const Unauthenticated());
  });

  // Not awaited: a test that re-stubs the bloc never listens to [states],
  // and closing an unlistened controller never completes.
  tearDown(() => unawaited(states.close()));

  /// Mounts the screen as a route pushed over a host page, as the login
  /// screen does, so the pops it performs have somewhere to land.
  Future<void> pumpPushed(WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen(),
                    ),
                  ),
                  child: const Text('host'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('host'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  }

  final emailField = find.widgetWithText(TextFormField, 'Email');
  final sendButton = find.widgetWithText(FilledButton, 'Send Reset Link');

  Future<void> tapSend(WidgetTester tester) async {
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pump();
  }

  group('ForgotPasswordScreen validation', () {
    testWidgets('an empty email is rejected without dispatching', (
      tester,
    ) async {
      await pumpPushed(tester);

      await tapSend(tester);

      expect(find.text('Please enter your email'), findsOneWidget);
      verifyNever(() => authBloc.add(any()));
    });

    testWidgets('a malformed email is rejected without dispatching', (
      tester,
    ) async {
      await pumpPushed(tester);

      await tester.enterText(emailField, 'not-an-email');
      await tapSend(tester);

      expect(find.text('Please enter a valid email'), findsOneWidget);
      verifyNever(() => authBloc.add(any()));
    });
  });

  group('ForgotPasswordScreen submit', () {
    testWidgets('the button dispatches PasswordResetRequested for the email', (
      tester,
    ) async {
      await pumpPushed(tester);

      await tester.enterText(emailField, 'ada@example.com');
      await tapSend(tester);

      verify(
        () => authBloc.add(
          const PasswordResetRequested(email: 'ada@example.com'),
        ),
      ).called(1);
    });

    testWidgets('the keyboard done action submits too', (tester) async {
      await pumpPushed(tester);

      await tester.enterText(emailField, 'ada@example.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      verify(
        () => authBloc.add(
          const PasswordResetRequested(email: 'ada@example.com'),
        ),
      ).called(1);
    });

    testWidgets('PasswordResetSent shows the message and returns to login', (
      tester,
    ) async {
      await pumpPushed(tester);

      states.add(const PasswordResetSent(message: 'Check your inbox'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.text('host'), findsOneWidget);
      // The toast outlives the route: it is on the app's ScaffoldMessenger.
      expect(find.text('Check your inbox'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('AuthError shows a failure toast and stays on the screen', (
      tester,
    ) async {
      await pumpPushed(tester);

      states.add(const AuthError(message: 'Too many requests'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(find.text('Too many requests'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('while AuthLoading the button shows the pulse and the form '
        'ignores input', (tester) async {
      whenListen(
        authBloc,
        const Stream<AuthState>.empty(),
        initialState: AuthLoading(),
      );
      await pumpPushed(tester);

      expect(find.text('Send Reset Link'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(ChromaticPulse),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      verifyNever(() => authBloc.add(any()));
    });

    testWidgets('Back to Login pops without dispatching', (tester) async {
      await pumpPushed(tester);

      await tester.tap(find.text('Back to Login'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsNothing);
      verifyNever(() => authBloc.add(any()));
    });

    testWidgets('the header back button pops too', (tester) async {
      await pumpPushed(tester);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsNothing);
    });
  });
}
