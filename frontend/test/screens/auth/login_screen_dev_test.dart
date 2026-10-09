import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:map_my_friends/bloc/auth/auth_bloc.dart';
import 'package:map_my_friends/bloc/auth/auth_event.dart';
import 'package:map_my_friends/bloc/auth/auth_state.dart';
import 'package:map_my_friends/screens/auth/login_screen.dart';
import 'package:map_my_friends/services/api_config.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  late AuthBloc authBloc;

  setUpAll(() {
    registerFallbackValue(const DevLoginRequested());
  });

  setUp(() {
    authBloc = MockAuthBloc();
    when(() => authBloc.state).thenReturn(const Unauthenticated());
    when(
      () => authBloc.stream,
    ).thenAnswer((_) => const Stream<AuthState>.empty());
    when(() => authBloc.close()).thenAnswer((_) => Future.value());
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: const LoginScreen(),
      ),
    );
  }

  group('LoginScreen DEV sign-in', () {
    // Tests run on the Dart VM in debug mode, so devLoginEnabled is true here
    // for the same reason it is true on an emulator or in Chrome.
    test('is enabled outside release builds', () {
      expect(ApiConfig.devLoginEnabled, isTrue);
      expect(ApiConfig.devAutoLogin, isFalse, reason: 'opt-in only');
    });

    testWidgets('dispatches DevLoginRequested when tapped', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      // Pre-existing, unrelated to the DEV button: the "Don't have an account?
      // / Sign Up" Row overflows its 420px card under the test environment's
      // fallback font metrics (it reproduces with --dart-define=DEV_LOGIN=false
      // too). Drain it so this test fails only for reasons it is testing.
      tester.takeException();

      final button = find.widgetWithText(
        OutlinedButton,
        'DEV Sign In (${ApiConfig.devUsername})',
      );
      expect(button, findsOneWidget);

      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      verify(() => authBloc.add(const DevLoginRequested())).called(1);
    });
  });
}
