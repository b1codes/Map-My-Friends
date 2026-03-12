import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'map_settings_cubit.dart';

/// Cubit for managing temporary map settings during an active map session.
/// It initializes from the global [MapSettingsCubit] state but does not
/// persist changes to SharedPreferences.
class LocalMapSettingsCubit extends Cubit<MapSettingsState> {
  LocalMapSettingsCubit({required MapSettingsState initialState})
    : super(initialState);

  void toggleControls() {
    emit(state.copyWith(showControls: !state.showControls));
  }

  void setMapType(MapType type) {
    emit(state.copyWith(mapType: type));
  }

  void setMapTheme(ThemeMode mode) {
    emit(state.copyWith(themeMode: mode));
  }

  void toggleAirports() {
    emit(state.copyWith(showAirports: !state.showAirports));
  }

  void setAirportFilter(AirportFilter filter) {
    emit(state.copyWith(airportFilter: filter));
  }
}
