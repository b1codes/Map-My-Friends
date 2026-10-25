import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  late SharedPreferences prefs;
  late MapSettingsCubit mapSettingsCubit;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    mapSettingsCubit = MapSettingsCubit(prefs: prefs);
  });

  tearDown(() {
    mapSettingsCubit.close();
  });

  group('MapSettingsCubit', () {
    test('initial state has default values when prefs are empty', () {
      expect(mapSettingsCubit.state, const MapSettingsState());
    });

    test('initial state loads values from prefs', () async {
      SharedPreferences.setMockInitialValues({
        'map_show_controls': false,
        'map_type': MapType.satellite.index,
        'map_theme_mode': ThemeMode.dark.index,
        'map_show_airports': true,
        'map_show_stations': true,
        'map_airport_filter': AirportFilter.international.index,
        'map_station_filter': StationFilter.major.index,
        'map_distance_unit': DistanceUnit.imperial.index,
      });
      prefs = await SharedPreferences.getInstance();
      final cubit = MapSettingsCubit(prefs: prefs);

      expect(cubit.state.showControls, false);
      expect(cubit.state.mapType, MapType.satellite);
      expect(cubit.state.themeMode, ThemeMode.dark);
      expect(cubit.state.showAirports, true);
      expect(cubit.state.showStations, true);
      expect(cubit.state.airportFilter, AirportFilter.international);
      expect(cubit.state.stationFilter, StationFilter.major);
      expect(cubit.state.distanceUnit, DistanceUnit.imperial);

      cubit.close();
    });

    blocTest<MapSettingsCubit, MapSettingsState>(
      'toggleControls updates state and saves to prefs',
      build: () => mapSettingsCubit,
      act: (cubit) => cubit.toggleControls(),
      expect: () => [const MapSettingsState().copyWith(showControls: false)],
      verify: (_) {
        expect(prefs.getBool('map_show_controls'), false);
      },
    );

    blocTest<MapSettingsCubit, MapSettingsState>(
      'toggleAirports updates state and saves to prefs',
      build: () => mapSettingsCubit,
      act: (cubit) => cubit.toggleAirports(),
      expect: () => [const MapSettingsState().copyWith(showAirports: true)],
      verify: (_) {
        expect(prefs.getBool('map_show_airports'), true);
      },
    );

    blocTest<MapSettingsCubit, MapSettingsState>(
      'toggleStations updates state and saves to prefs',
      build: () => mapSettingsCubit,
      act: (cubit) => cubit.toggleStations(),
      expect: () => [const MapSettingsState().copyWith(showStations: true)],
      verify: (_) {
        expect(prefs.getBool('map_show_stations'), true);
      },
    );

    blocTest<MapSettingsCubit, MapSettingsState>(
      'setMapType updates state and saves to prefs',
      build: () => mapSettingsCubit,
      act: (cubit) => cubit.setMapType(MapType.minimal),
      expect: () => [
        const MapSettingsState().copyWith(mapType: MapType.minimal),
      ],
      verify: (_) {
        expect(prefs.getInt('map_type'), MapType.minimal.index);
      },
    );

    blocTest<MapSettingsCubit, MapSettingsState>(
      'setMapTheme updates state and saves to prefs',
      build: () => mapSettingsCubit,
      act: (cubit) => cubit.setMapTheme(ThemeMode.light),
      expect: () => [
        const MapSettingsState().copyWith(themeMode: ThemeMode.light),
      ],
      verify: (_) {
        expect(prefs.getInt('map_theme_mode'), ThemeMode.light.index);
      },
    );

    blocTest<MapSettingsCubit, MapSettingsState>(
      'setAirportFilter updates state and saves to prefs',
      build: () => mapSettingsCubit,
      act: (cubit) => cubit.setAirportFilter(AirportFilter.regional),
      expect: () => [
        const MapSettingsState().copyWith(
          airportFilter: AirportFilter.regional,
        ),
      ],
      verify: (_) {
        expect(
          prefs.getInt('map_airport_filter'),
          AirportFilter.regional.index,
        );
      },
    );

    blocTest<MapSettingsCubit, MapSettingsState>(
      'setStationFilter updates state and saves to prefs',
      build: () => mapSettingsCubit,
      act: (cubit) => cubit.setStationFilter(StationFilter.subway),
      expect: () => [
        const MapSettingsState().copyWith(stationFilter: StationFilter.subway),
      ],
      verify: (_) {
        expect(prefs.getInt('map_station_filter'), StationFilter.subway.index);
      },
    );

    blocTest<MapSettingsCubit, MapSettingsState>(
      'setDistanceUnit updates state and saves to prefs',
      build: () => mapSettingsCubit,
      act: (cubit) => cubit.setDistanceUnit(DistanceUnit.imperial),
      expect: () => [
        const MapSettingsState().copyWith(distanceUnit: DistanceUnit.imperial),
      ],
      verify: (_) {
        expect(prefs.getInt('map_distance_unit'), DistanceUnit.imperial.index);
      },
    );

    blocTest<MapSettingsCubit, MapSettingsState>(
      'toggling twice returns to the original value and persists it',
      build: () => mapSettingsCubit,
      act: (cubit) => cubit
        ..toggleAirports()
        ..toggleAirports(),
      expect: () => [
        const MapSettingsState(showAirports: true),
        const MapSettingsState(),
      ],
      verify: (_) => expect(prefs.getBool('map_show_airports'), false),
    );

    test('settings changed in one session are restored in the next', () async {
      mapSettingsCubit
        ..toggleControls()
        ..toggleStations()
        ..setMapType(MapType.minimal)
        ..setMapTheme(ThemeMode.dark)
        ..setAirportFilter(AirportFilter.regional)
        ..setStationFilter(StationFilter.commuter)
        ..setDistanceUnit(DistanceUnit.imperial);
      final changed = mapSettingsCubit.state;

      final next = MapSettingsCubit(prefs: prefs);
      expect(next.state, changed);
      expect(
        next.state,
        const MapSettingsState(
          showControls: false,
          showStations: true,
          mapType: MapType.minimal,
          themeMode: ThemeMode.dark,
          airportFilter: AirportFilter.regional,
          stationFilter: StationFilter.commuter,
          distanceUnit: DistanceUnit.imperial,
        ),
      );
      await next.close();
    });

    test('copyWith with no arguments is an identical value', () {
      const state = MapSettingsState(mapType: MapType.satellite);
      expect(state.copyWith(), state);
      expect(state.copyWith(mapType: MapType.minimal), isNot(state));
    });
  });
}
