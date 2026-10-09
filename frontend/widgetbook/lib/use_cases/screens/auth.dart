import 'package:flutter/material.dart';
import 'package:map_my_friends/bloc/auth/auth_state.dart';
import 'package:map_my_friends/screens/auth/forgot_password_screen.dart';
import 'package:map_my_friends/screens/auth/login_screen.dart';
import 'package:map_my_friends/screens/auth/register_screen.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/stage.dart';
import '../../support/story_scope.dart';

/// The auth states a form screen reacts to. A screen only reacts to a
/// *change*, so switching this knob is what plays its toast or navigation.
enum _Auth { idle, loading, error, success }

_Auth _authKnob(BuildContext context, {required String successLabel}) =>
    context.knobs.object.dropdown(
      label: 'Auth state',
      description:
          'Screens react to changes, not to the state they open in: switch '
          'to "error" or "$successLabel" to see the toast and navigation.',
      options: _Auth.values,
      labelBuilder: (s) => s == _Auth.success ? successLabel : s.name,
    );

@widgetbook.UseCase(name: 'Default', type: LoginScreen, path: '[Screens]/auth')
Widget loginScreenDefault(BuildContext context) {
  final AuthState auth = switch (context.knobs.object.dropdown(
    label: 'Auth state',
    description:
        'An error the screen opens with (a failed DEV auto-login) is shown '
        'on the first frame; one that arrives later shows as it arrives.',
    options: const [_Auth.idle, _Auth.loading, _Auth.error],
    labelBuilder: (s) => s.name,
  )) {
    _Auth.loading => AuthLoading(),
    _Auth.error => const AuthError(message: 'Incorrect username or password'),
    _ => const Unauthenticated(),
  };

  return StoryScope(
    auth: auth,
    child: const Stage.route(child: LoginScreen()),
  );
}

@widgetbook.UseCase(
  name: 'Default',
  type: RegisterScreen,
  path: '[Screens]/auth',
)
Widget registerScreenDefault(BuildContext context) {
  final AuthState auth = switch (_authKnob(
    context,
    successLabel: 'registered',
  )) {
    _Auth.idle => const Unauthenticated(),
    _Auth.loading => AuthLoading(),
    _Auth.error => const AuthError(message: 'That username is taken'),
    _Auth.success => const RegistrationSuccess(),
  };

  return StoryScope(
    auth: auth,
    child: const Stage.pushed(pushedFrom: 'Login', child: RegisterScreen()),
  );
}

@widgetbook.UseCase(
  name: 'Default',
  type: ForgotPasswordScreen,
  path: '[Screens]/auth',
)
Widget forgotPasswordScreenDefault(BuildContext context) {
  final AuthState auth = switch (_authKnob(context, successLabel: 'sent')) {
    _Auth.idle => const Unauthenticated(),
    _Auth.loading => AuthLoading(),
    _Auth.error => const AuthError(message: 'No account uses that email'),
    _Auth.success => const PasswordResetSent(
      message: 'Check your inbox for a reset link.',
    ),
  };

  return StoryScope(
    auth: auth,
    child: const Stage.pushed(
      pushedFrom: 'Login',
      child: ForgotPasswordScreen(),
    ),
  );
}
