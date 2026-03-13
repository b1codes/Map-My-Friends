import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MapType { standard, satellite, minimal }

enum AirportFilter { all, international, regional }

class MapSettingsState extends Equatable {
  final bool showControls;
  final MapType mapType;
  final ThemeMode themeMode;
  final bool showAirports;
  final bool showStations;
  final AirportFilter airportFilter;

  const MapSettingsState({
    this.showControls = true,
    this.mapType = MapType.standard,
    this.themeMode = ThemeMode.system,
    this.showAirports = false,
    this.showStations = false,
    this.airportFilter = AirportFilter.all,
  });

  MapSettingsState copyWith({
    bool? showControls,
    MapType? mapType,
    ThemeMode? themeMode,
    bool? showAirports,
    bool? showStations,
    AirportFilter? airportFilter,
  }) {
    return MapSettingsState(
      showControls: showControls ?? this.showControls,
      mapType: mapType ?? this.mapType,
      themeMode: themeMode ?? this.themeMode,
      showAirports: showAirports ?? this.showAirports,
      showStations: showStations ?? this.showStations,
      airportFilter: airportFilter ?? this.airportFilter,
    );
  }

  @override
  List<Object> get props => [
        showControls,
        mapType,
        themeMode,
        showAirports,
        showStations,
        airportFilter,
      ];
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
    final showAirports = prefs.getBool('map_show_airports') ?? false;
    final showStations = prefs.getBool('map_show_stations') ?? false;
    final airportFilterIndex =
        prefs.getInt('map_airport_filter') ?? AirportFilter.all.index;

    emit(
      state.copyWith(
        showControls: showControls,
        mapType: MapType.values[mapTypeIndex],
        themeMode: ThemeMode.values[themeModeIndex],
        showAirports: showAirports,
        showStations: showStations,
        airportFilter: AirportFilter.values[airportFilterIndex],
      ),
    );
  }

  void toggleControls() {
    final newValue = !state.showControls;
    prefs.setBool('map_show_controls', newValue);
    emit(state.copyWith(showControls: newValue));
  }

  void toggleAirports() {
    final newValue = !state.showAirports;
    prefs.setBool('map_show_airports', newValue);
    emit(state.copyWith(showAirports: newValue));
  }

  void toggleStations() {
    final newValue = !state.showStations;
    prefs.setBool('map_show_stations', newValue);
    emit(state.copyWith(showStations: newValue));
  }

  void setMapType(MapType type) {
    prefs.setInt('map_type', type.index);
    emit(state.copyWith(mapType: type));
  }

  void setMapTheme(ThemeMode mode) {
    prefs.setInt('map_theme_mode', mode.index);
    emit(state.copyWith(themeMode: mode));
  }

  void setAirportFilter(AirportFilter filter) {
    prefs.setInt('map_airport_filter', filter.index);
    emit(state.copyWith(airportFilter: filter));
  }
}
