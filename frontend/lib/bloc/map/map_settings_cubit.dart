import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MapType { standard, satellite, minimal }

class MapSettingsState extends Equatable {
  final bool showControls;
  final MapType mapType;
  final ThemeMode themeMode;

  const MapSettingsState({
    this.showControls = true,
    this.mapType = MapType.standard,
    this.themeMode = ThemeMode.system,
  });

  MapSettingsState copyWith({
    bool? showControls,
    MapType? mapType,
    ThemeMode? themeMode,
  }) {
    return MapSettingsState(
      showControls: showControls ?? this.showControls,
      mapType: mapType ?? this.mapType,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  @override
  List<Object> get props => [showControls, mapType, themeMode];
}

class MapSettingsCubit extends Cubit<MapSettingsState> {
  final SharedPreferences prefs;

  MapSettingsCubit({required this.prefs}) : super(const MapSettingsState()) {
    _loadSettings();
  }

  void _loadSettings() {
    final showControls = prefs.getBool('map_show_controls') ?? true;
    final mapTypeIndex = prefs.getInt('map_type') ?? MapType.standard.index;
    final themeModeIndex =
        prefs.getInt('map_theme_mode') ?? ThemeMode.system.index;

    emit(
      state.copyWith(
        showControls: showControls,
        mapType: MapType.values[mapTypeIndex],
        themeMode: ThemeMode.values[themeModeIndex],
      ),
    );
  }

  void toggleControls() {
    final newValue = !state.showControls;
    prefs.setBool('map_show_controls', newValue);
    emit(state.copyWith(showControls: newValue));
  }

  void setMapType(MapType type) {
    prefs.setInt('map_type', type.index);
    emit(state.copyWith(mapType: type));
  }

  void setMapTheme(ThemeMode mode) {
    prefs.setInt('map_theme_mode', mode.index);
    emit(state.copyWith(themeMode: mode));
  }
}
