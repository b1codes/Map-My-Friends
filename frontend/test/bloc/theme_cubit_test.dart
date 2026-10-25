import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/theme/theme_cubit.dart';

void main() {
  test('starts by following the system theme', () {
    final cubit = ThemeCubit();
    expect(cubit.state, ThemeMode.system);
    cubit.close();
  });

  blocTest<ThemeCubit, ThemeMode>(
    'setTheme emits each new mode',
    build: ThemeCubit.new,
    act: (cubit) => cubit
      ..setTheme(ThemeMode.dark)
      ..setTheme(ThemeMode.light)
      ..setTheme(ThemeMode.system),
    expect: () => [ThemeMode.dark, ThemeMode.light, ThemeMode.system],
  );

  blocTest<ThemeCubit, ThemeMode>(
    'repeating the same mode does not emit a duplicate',
    build: ThemeCubit.new,
    act: (cubit) => cubit
      ..setTheme(ThemeMode.dark)
      ..setTheme(ThemeMode.dark),
    expect: () => [ThemeMode.dark],
  );
}
