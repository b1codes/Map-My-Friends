import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:map_my_friends/bloc/map/local_map_settings_cubit.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';

void main() {
  const global = MapSettingsState(
    showControls: false,
    mapType: MapType.satellite,
    themeMode: ThemeMode.dark,
    showAirports: true,
    showStations: false,
    airportFilter: AirportFilter.international,
    stationFilter: StationFilter.major,
    distanceUnit: DistanceUnit.imperial,
  );

  LocalMapSettingsCubit build() => LocalMapSettingsCubit(initialState: global);

  test('starts from the global settings it was given', () {
    final cubit = build();
    expect(cubit.state, global);
    cubit.close();
  });

  blocTest<LocalMapSettingsCubit, MapSettingsState>(
    'toggleControls flips showControls each call',
    build: build,
    act: (c) => c
      ..toggleControls()
      ..toggleControls(),
    expect: () => [global.copyWith(showControls: true), global],
  );

  blocTest<LocalMapSettingsCubit, MapSettingsState>(
    'toggleAirports flips showAirports',
    build: build,
    act: (c) => c.toggleAirports(),
    expect: () => [global.copyWith(showAirports: false)],
  );

  blocTest<LocalMapSettingsCubit, MapSettingsState>(
    'toggleStations flips showStations',
    build: build,
    act: (c) => c.toggleStations(),
    expect: () => [global.copyWith(showStations: true)],
  );

  blocTest<LocalMapSettingsCubit, MapSettingsState>(
    'setMapType changes only the map type',
    build: build,
    act: (c) => c.setMapType(MapType.minimal),
    expect: () => [global.copyWith(mapType: MapType.minimal)],
  );

  blocTest<LocalMapSettingsCubit, MapSettingsState>(
    'setMapTheme changes only the theme',
    build: build,
    act: (c) => c.setMapTheme(ThemeMode.light),
    expect: () => [global.copyWith(themeMode: ThemeMode.light)],
  );

  blocTest<LocalMapSettingsCubit, MapSettingsState>(
    'setAirportFilter changes only the airport filter',
    build: build,
    act: (c) => c.setAirportFilter(AirportFilter.regional),
    expect: () => [global.copyWith(airportFilter: AirportFilter.regional)],
  );

  blocTest<LocalMapSettingsCubit, MapSettingsState>(
    'setStationFilter changes only the station filter',
    build: build,
    act: (c) => c.setStationFilter(StationFilter.subway),
    expect: () => [global.copyWith(stationFilter: StationFilter.subway)],
  );

  blocTest<LocalMapSettingsCubit, MapSettingsState>(
    'setDistanceUnit changes only the unit',
    build: build,
    act: (c) => c.setDistanceUnit(DistanceUnit.metric),
    expect: () => [global.copyWith(distanceUnit: DistanceUnit.metric)],
  );

  test('never writes to SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({
      'map_type': MapType.standard.index,
    });
    final prefs = await SharedPreferences.getInstance();
    final cubit = build()
      ..toggleControls()
      ..toggleAirports()
      ..toggleStations()
      ..setMapType(MapType.minimal)
      ..setMapTheme(ThemeMode.light)
      ..setAirportFilter(AirportFilter.regional)
      ..setStationFilter(StationFilter.commuter)
      ..setDistanceUnit(DistanceUnit.metric);
    await cubit.close();

    expect(prefs.getKeys(), {'map_type'});
    expect(prefs.getInt('map_type'), MapType.standard.index);
    // A fresh global cubit still reads the untouched persisted values.
    final globalCubit = MapSettingsCubit(prefs: prefs);
    expect(globalCubit.state, const MapSettingsState());
    await globalCubit.close();
  });
}
