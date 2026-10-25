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

  group('RegisterScreen payload, toggles and navigation', () {
    Finder field(String label) => find.widgetWithText(TextFormField, label);
    final createButton = find.widgetWithText(FilledButton, 'Create Account');

    Future<void> submit(WidgetTester tester) async {
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pump();
    }

    Future<void> fillRequired(WidgetTester tester) async {
      await tester.enterText(field('Username *'), '  ada  ');
      await tester.enterText(field('Email *'), 'ada@example.com');
      await tester.enterText(field('Password *'), 'password123');
      await tester.enterText(field('Confirm Password *'), 'password123');
    }

    // The honeypot reuses the "First Name" label on purpose, so the real
    // field is the first match and the trap is the last.
    Finder realFirstName() => field('First Name').first;
    Finder honeypot() => field('First Name').last;

    /// Pushes the screen over a host page, as the login screen does, so the
    /// pops it performs have somewhere to land.
    Future<StreamController<AuthState>> pumpPushed(WidgetTester tester) async {
      final controller = StreamController<AuthState>.broadcast();
      addTearDown(controller.close);
      when(() => authBloc.stream).thenAnswer((_) => controller.stream);
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
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
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
      expect(find.byType(RegisterScreen), findsOneWidget);
      return controller;
    }

    testWidgets('rejects a username shorter than three characters', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.enterText(field('Username *'), 'ab');
      await submit(tester);

      expect(
        find.text('Username must be at least 3 characters'),
        findsOneWidget,
      );
      verifyNever(() => authBloc.add(any()));
    });

    testWidgets('rejects a password shorter than eight characters', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.enterText(field('Password *'), 'short');
      await tester.enterText(field('Confirm Password *'), 'short');
      await submit(tester);

      expect(
        find.text('Password must be at least 8 characters'),
        findsOneWidget,
      );
      verifyNever(() => authBloc.add(any()));
    });

    testWidgets('sends a trimmed username and null for blank names', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await fillRequired(tester);
      await tester.enterText(realFirstName(), '   ');
      await submit(tester);

      verify(
        () => authBloc.add(
          const RegisterRequested(
            username: 'ada',
            email: 'ada@example.com',
            password: 'password123',
            passwordConfirm: 'password123',
            firstName: null,
            lastName: null,
            firstNameHp: '',
          ),
        ),
      ).called(1);
    });

    testWidgets('sends trimmed first and last names when given', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await fillRequired(tester);
      await tester.enterText(realFirstName(), ' Ada ');
      await tester.enterText(field('Last Name'), ' Lovelace ');
      await submit(tester);

      final event =
          verify(
                () => authBloc.add(captureAny(that: isA<RegisterRequested>())),
              ).captured.single
              as RegisterRequested;
      expect(event.firstName, 'Ada');
      expect(event.lastName, 'Lovelace');
    });

    testWidgets('forwards whatever a bot typed into the honeypot', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await fillRequired(tester);
      // A bot fills fields programmatically; a person can never focus it.
      tester.widget<TextFormField>(honeypot()).controller!.text = 'botty';
      await submit(tester);

      final event =
          verify(
                () => authBloc.add(captureAny(that: isA<RegisterRequested>())),
              ).captured.single
              as RegisterRequested;
      expect(event.firstNameHp, 'botty');
      expect(event.firstName, isNull);
    });

    testWidgets('the done action on Confirm Password submits', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await fillRequired(tester);
      await tester.showKeyboard(field('Confirm Password *'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      verify(() => authBloc.add(any(that: isA<RegisterRequested>()))).called(1);
    });

    testWidgets('each eye toggle reveals only its own field', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      bool obscured(String label) => tester
          .widget<EditableText>(
            find.descendant(
              of: field(label),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText;

      expect(obscured('Password *'), isTrue);
      expect(obscured('Confirm Password *'), isTrue);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(obscured('Password *'), isFalse);
      expect(obscured('Confirm Password *'), isTrue);
      expect(find.byTooltip('Hide password'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Show confirm password'));
      await tester.tap(find.byTooltip('Show confirm password'));
      await tester.pump();
      expect(obscured('Confirm Password *'), isFalse);
      expect(find.byTooltip('Hide confirm password'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide password'));
      await tester.tap(find.byTooltip('Hide confirm password'));
      await tester.pump();
      expect(obscured('Password *'), isTrue);
      expect(obscured('Confirm Password *'), isTrue);
    });

    testWidgets('while AuthLoading the submit is disabled', (tester) async {
      when(() => authBloc.state).thenReturn(AuthLoading());
      await tester.pumpWidget(createWidgetUnderTest());

      // The header still reads "Create Account"; the button no longer does.
      expect(createButton, findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      verifyNever(() => authBloc.add(any()));
    });

    testWidgets('RegistrationSuccess shows its message and returns to login', (
      tester,
    ) async {
      final states = await pumpPushed(tester);

      states.add(const RegistrationSuccess());
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.text('host'), findsOneWidget);
      expect(
        find.text('Registration successful! Please login.'),
        findsOneWidget,
      );
    });

    testWidgets('AuthError keeps the user on the form', (tester) async {
      final states = await pumpPushed(tester);

      states.add(const AuthError(message: 'Username taken'));
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.text('Username taken'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('Sign In returns to the previous screen', (tester) async {
      await pumpPushed(tester);

      final signIn = find.widgetWithText(TextButton, 'Sign In');
      await tester.ensureVisible(signIn);
      await tester.tap(signIn);
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsNothing);
      verifyNever(() => authBloc.add(any()));
    });
  });
}
