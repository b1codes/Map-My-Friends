import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/auth/auth_bloc.dart';
import 'package:map_my_friends/bloc/auth/auth_event.dart';
import 'package:map_my_friends/bloc/auth/auth_state.dart';
import 'package:map_my_friends/screens/auth/register_screen.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  late AuthBloc authBloc;

  setUpAll(() {
    registerFallbackValue(const LoginRequested(username: '', password: ''));
  });

  setUp(() {
    authBloc = MockAuthBloc();
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => Stream<AuthState>.empty());
    when(() => authBloc.close()).thenAnswer((_) => Future.value());
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: BlocProvider.value(value: authBloc, child: const RegisterScreen()),
    );
  }

  group('RegisterScreen', () {
    testWidgets('shows validation errors for empty fields', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      // Use widgetWithText to avoid ambiguous match with AppBar title
      final button = find.widgetWithText(FilledButton, 'Create Account');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      expect(find.text('Username is required'), findsOneWidget);
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
      expect(find.text('Please confirm your password'), findsOneWidget);
    });

    testWidgets('shows error for invalid email', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'),
        'invalid-email',
      );
      final button = find.widgetWithText(FilledButton, 'Create Account');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      expect(find.text('Please enter a valid email'), findsOneWidget);
    });

    testWidgets('shows error for password mismatch', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password *'),
        'password123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password *'),
        'password456',
      );
      final button = find.widgetWithText(FilledButton, 'Create Account');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('dispatches RegisterRequested on valid form submission', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username *'),
        'testuser',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'),
        'test@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password *'),
        'password123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password *'),
        'password123',
      );

      final button = find.widgetWithText(FilledButton, 'Create Account');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      verify(() => authBloc.add(any(that: isA<RegisterRequested>()))).called(1);
    });

    testWidgets('shows loading indicator when state is AuthLoading', (
      tester,
    ) async {
      when(() => authBloc.state).thenReturn(AuthLoading());

      await tester.pumpWidget(createWidgetUnderTest());

      // The app's loading state is the Chromatic Pulse, not Material's
      // spinner — `llc-standards/context/chromatic-pulse.md`.
      expect(find.byType(ChromaticPulse), findsOneWidget);
    });

    testWidgets('shows snackbar on AuthError', (tester) async {
      // Use broadcast controller to avoid "Stream already listened to"
      final controller = StreamController<AuthState>.broadcast();
      when(() => authBloc.stream).thenAnswer((_) => controller.stream);

      await tester.pumpWidget(createWidgetUnderTest());

      controller.add(const AuthError(message: 'Registration failed'));
      // Need to pump enough to show snackbar
      await tester.pump();

      expect(find.text('Registration failed'), findsOneWidget);
      await controller.close();
    });
  });
}
