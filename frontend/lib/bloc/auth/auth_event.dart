import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class CheckAuthStatus extends AuthEvent {}

class LoginRequested extends AuthEvent {
  final String username;
  final String password;

  const LoginRequested({required this.username, required this.password});

  @override
  List<Object?> get props => [username, password];
}

class RegisterRequested extends AuthEvent {
  final String username;
  final String email;
  final String password;
  final String passwordConfirm;
  final String? firstName;
  final String? lastName;
  final String? firstNameHp;

  const RegisterRequested({
    required this.username,
    required this.email,
    required this.password,
    required this.passwordConfirm,
    this.firstName,
    this.lastName,
    this.firstNameHp,
  });

  @override
  List<Object?> get props => [
    username,
    email,
    password,
    passwordConfirm,
    firstName,
    lastName,
    firstNameHp,
  ];
}

class PasswordResetRequested extends AuthEvent {
  final String email;

  const PasswordResetRequested({required this.email});

  @override
  List<Object?> get props => [email];
}

class LogoutRequested extends AuthEvent {}
