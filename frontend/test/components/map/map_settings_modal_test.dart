import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/map/local_map_settings_cubit.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/components/map/map_settings_modal.dart';
import 'package:mocktail/mocktail.dart';

class MockLocalMapSettingsCubit extends MockCubit<MapSettingsState>
    implements LocalMapSettingsCubit {}

void main() {
  late MockLocalMapSettingsCubit cubit;

  setUp(() {
    cubit = MockLocalMapSettingsCubit();
    when(() => cubit.state).thenReturn(const MapSettingsState());
  });

  Future<void> pumpModal(WidgetTester tester, LocalMapSettingsCubit c) async {
    // Tall enough that every control is on screen without scrolling.
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<LocalMapSettingsCubit>.value(
            value: c,
            child: const MapSettingsModal(),
          ),
        ),
      ),
    );
  }

  SwitchListTile switchTile(WidgetTester tester, String title) =>
      tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SwitchListTile),
        ),
      );

  testWidgets('reflects the current settings', (tester) async {
    when(() => cubit.state).thenReturn(
      const MapSettingsState(
        showControls: false,
        showAirports: true,
        showStations: false,
        mapType: MapType.satellite,
      ),
    );
    await pumpModal(tester, cubit);

    expect(find.text('Map Settings'), findsOneWidget);
    expect(switchTile(tester, 'Show Map Controls').value, isFalse);
    expect(switchTile(tester, 'Show Airports').value, isTrue);
    expect(switchTile(tester, 'Show Train Stations').value, isFalse);
    expect(find.text('SATELLITE'), findsOneWidget);
  });

  testWidgets('hides the filters for layers that are off', (tester) async {
    await pumpModal(tester, cubit);

    expect(find.byType(SegmentedButton<AirportFilter>), findsNothing);
    expect(find.byType(SegmentedButton<StationFilter>), findsNothing);
    // Unit and theme are always available.
    expect(find.byType(SegmentedButton<DistanceUnit>), findsOneWidget);
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
  });

  group('each control calls the matching cubit method', () {
    testWidgets('the three layer switches', (tester) async {
      await pumpModal(tester, cubit);

      await tester.tap(find.text('Show Map Controls'));
      verify(() => cubit.toggleControls()).called(1);

      await tester.tap(find.text('Show Airports'));
      verify(() => cubit.toggleAirports()).called(1);

      await tester.tap(find.text('Show Train Stations'));
      verify(() => cubit.toggleStations()).called(1);
    });

    testWidgets('the airport filter', (tester) async {
      when(
        () => cubit.state,
      ).thenReturn(const MapSettingsState(showAirports: true));
      await pumpModal(tester, cubit);

      await tester.tap(find.text('International'));
      verify(
        () => cubit.setAirportFilter(AirportFilter.international),
      ).called(1);

      await tester.tap(find.text('Regional'));
      verify(() => cubit.setAirportFilter(AirportFilter.regional)).called(1);
    });

    testWidgets('the station filter', (tester) async {
      when(
        () => cubit.state,
      ).thenReturn(const MapSettingsState(showStations: true));
      await pumpModal(tester, cubit);

      for (final (label, filter) in [
        ('Amtrak', StationFilter.major),
        ('Rail', StationFilter.commuter),
        ('Subway', StationFilter.subway),
        ('Other', StationFilter.regional),
      ]) {
        await tester.tap(find.text(label));
        verify(() => cubit.setStationFilter(filter)).called(1);
      }
    });

    testWidgets('the distance unit', (tester) async {
      await pumpModal(tester, cubit);

      await tester.tap(find.text('Imperial (mi)'));
      verify(() => cubit.setDistanceUnit(DistanceUnit.imperial)).called(1);
    });

    testWidgets('the map type dropdown', (tester) async {
      await pumpModal(tester, cubit);

      await tester.tap(find.byType(DropdownButton<MapType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MINIMAL').last);
      await tester.pumpAndSettle();

      verify(() => cubit.setMapType(MapType.minimal)).called(1);
    });

    testWidgets('the map theme', (tester) async {
      await pumpModal(tester, cubit);

      await tester.tap(find.text('Dark'));
      verify(() => cubit.setMapTheme(ThemeMode.dark)).called(1);

      await tester.tap(find.text('Light'));
      verify(() => cubit.setMapTheme(ThemeMode.light)).called(1);
    });
  });

  testWidgets('turning a layer on reveals its filter and applies a choice', (
    tester,
  ) async {
    final real = LocalMapSettingsCubit(initialState: const MapSettingsState());
    addTearDown(real.close);
    await pumpModal(tester, real);

    await tester.tap(find.text('Show Airports'));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<AirportFilter>), findsOneWidget);

    await tester.tap(find.text('Regional'));
    await tester.pumpAndSettle();
    expect(real.state.airportFilter, AirportFilter.regional);
    expect(
      tester
          .widget<SegmentedButton<AirportFilter>>(
            find.byType(SegmentedButton<AirportFilter>),
          )
          .selected,
      {AirportFilter.regional},
    );

    await tester.tap(find.text('Show Train Stations'));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<StationFilter>), findsOneWidget);

    await tester.tap(find.text('Show Airports'));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<AirportFilter>), findsNothing);
    expect(real.state.showAirports, isFalse);
    expect(real.state.showStations, isTrue);
  });
}
