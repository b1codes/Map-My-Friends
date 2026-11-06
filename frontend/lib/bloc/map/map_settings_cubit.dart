import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MapType { standard, satellite, minimal }

enum AirportFilter { all, international, regional }

enum StationFilter { all, major, commuter, subway, regional }

enum DistanceUnit { metric, imperial }

class MapSettingsState extends Equatable {
  final bool showControls;
  final MapType mapType;
  final ThemeMode themeMode;
  final bool showAirports;
  final bool showStations;
  final AirportFilter airportFilter;
  final StationFilter stationFilter;
  final DistanceUnit distanceUnit;

  const MapSettingsState({
    this.showControls = true,
    this.mapType = MapType.standard,
    this.themeMode = ThemeMode.system,
    this.showAirports = false,
    this.showStations = false,
    this.airportFilter = AirportFilter.all,
    this.stationFilter = StationFilter.all,
    this.distanceUnit = DistanceUnit.metric,
  });

  MapSettingsState copyWith({
    bool? showControls,
    MapType? mapType,
    ThemeMode? themeMode,
    bool? showAirports,
    bool? showStations,
    AirportFilter? airportFilter,
    StationFilter? stationFilter,
    DistanceUnit? distanceUnit,
  }) {
    return MapSettingsState(
      showControls: showControls ?? this.showControls,
      mapType: mapType ?? this.mapType,
      themeMode: themeMode ?? this.themeMode,
      showAirports: showAirports ?? this.showAirports,
      showStations: showStations ?? this.showStations,
      airportFilter: airportFilter ?? this.airportFilter,
      stationFilter: stationFilter ?? this.stationFilter,
      distanceUnit: distanceUnit ?? this.distanceUnit,
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
    stationFilter,
    distanceUnit,
  ];
}

class MapSettingsCubit extends Cubit<MapSettingsState> {
  final SharedPreferences prefs;

  MapSettingsCubit({required this.prefs}) : super(const MapSettingsState()) {
    _loadSettings();
  }

  void _loadSettings() {
    final showControls = prefs.getBool('map_show_controls') ?? true;
    final showAirports = prefs.getBool('map_show_airports') ?? false;
    final showStations = prefs.getBool('map_show_stations') ?? false;

    emit(
      state.copyWith(
        showControls: showControls,
        mapType: _savedEnum('map_type', MapType.values, MapType.standard),
        themeMode: _savedEnum(
          'map_theme_mode',
          ThemeMode.values,
          ThemeMode.system,
        ),
        showAirports: showAirports,
        showStations: showStations,
        airportFilter: _savedEnum(
          'map_airport_filter',
          AirportFilter.values,
          AirportFilter.all,
        ),
        stationFilter: _savedEnum(
          'map_station_filter',
          StationFilter.values,
          StationFilter.all,
        ),
        distanceUnit: _savedEnum(
          'map_distance_unit',
          DistanceUnit.values,
          DistanceUnit.metric,
        ),
      ),
    );
  }

  /// The enum value saved under [key] by index, or [fallback] when nothing
  /// is saved or the index doesn't exist in this build (e.g. it was written
  /// by a version whose enum had more cases).
  T _savedEnum<T extends Enum>(String key, List<T> values, T fallback) {
    final index = prefs.getInt(key);
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
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

  void setStationFilter(StationFilter filter) {
    prefs.setInt('map_station_filter', filter.index);
    emit(state.copyWith(stationFilter: filter));
  }

  void setDistanceUnit(DistanceUnit unit) {
    prefs.setInt('map_distance_unit', unit.index);
    emit(state.copyWith(distanceUnit: unit));
  }
}
