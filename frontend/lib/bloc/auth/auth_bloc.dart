import 'package:flutter_bloc/flutter_bloc.dart';
import 'auth_event.dart';
import 'auth_state.dart';
import '../../services/auth_service.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthService _authService;

  AuthBloc({AuthService? authService})
    : _authService = authService ?? AuthService(),
      super(AuthInitial()) {
    on<CheckAuthStatus>(_onCheckAuthStatus);
    on<LoginRequested>(_onLoginRequested);
    on<RegisterRequested>(_onRegisterRequested);
    on<PasswordResetRequested>(_onPasswordResetRequested);
    on<LogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onCheckAuthStatus(
    CheckAuthStatus event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      final tokens = await _authService.getStoredTokens();
      if (tokens != null) {
        emit(
          Authenticated(
            accessToken: tokens['access']!,
            refreshToken: tokens['refresh']!,
            username: tokens['username'],
          ),
        );
      } else {
        emit(const Unauthenticated());
      }
    } catch (e) {
      emit(const Unauthenticated());
    }
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      final tokens = await _authService.login(event.username, event.password);
      emit(
        Authenticated(
          accessToken: tokens['access']!,
          refreshToken: tokens['refresh']!,
          username: tokens['username'],
        ),
      );
    } catch (e) {
      emit(AuthError(message: e.toString().replaceFirst('Exception: ', '')));
    }
  }

  Future<void> _onRegisterRequested(
    RegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      await _authService.register(
        username: event.username,
        email: event.email,
        password: event.password,
        passwordConfirm: event.passwordConfirm,
        firstName: event.firstName,
        lastName: event.lastName,
        firstNameHp: event.firstNameHp,
      );
      emit(const RegistrationSuccess());
    } catch (e) {
      emit(AuthError(message: e.toString().replaceFirst('Exception: ', '')));
    }
  }

  Future<void> _onPasswordResetRequested(
    PasswordResetRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      await _authService.requestPasswordReset(event.email);
      emit(
        const PasswordResetSent(
          message:
              'If an account exists with this email, a password reset link has been sent.',
        ),
      );
    } catch (e) {
      emit(AuthError(message: e.toString().replaceFirst('Exception: ', '')));
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authService.logout();
    emit(const Unauthenticated(message: 'You have been logged out.'));
  }
}
