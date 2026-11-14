import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/location/location_bloc.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/bloc/theme/theme_cubit.dart';
import 'package:map_my_friends/components/shared/chromatic_pulse.dart';
import 'package:map_my_friends/screens/settings/settings_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockThemeCubit extends MockCubit<ThemeMode> implements ThemeCubit {}

class MockMapSettingsCubit extends MockCubit<MapSettingsState>
    implements MapSettingsCubit {}

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

void main() {
  late MockThemeCubit themeCubit;
  late MockMapSettingsCubit mapSettings;
  late MockLocationBloc locationBloc;

  setUpAll(() {
    registerFallbackValue(LoadLocation());
    registerFallbackValue(ThemeMode.system);
    registerFallbackValue(MapType.standard);
    registerFallbackValue(DistanceUnit.metric);
  });

  setUp(() {
    themeCubit = MockThemeCubit();
    mapSettings = MockMapSettingsCubit();
    locationBloc = MockLocationBloc();
    whenListen(
      themeCubit,
      const Stream<ThemeMode>.empty(),
      initialState: ThemeMode.system,
    );
    whenListen(
      mapSettings,
      const Stream<MapSettingsState>.empty(),
      initialState: const MapSettingsState(),
    );
    whenListen(
      locationBloc,
      const Stream<LocationState>.empty(),
      initialState: LocationInitial(),
    );
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>.value(value: themeCubit),
          BlocProvider<MapSettingsCubit>.value(value: mapSettings),
          BlocProvider<LocationBloc>.value(value: locationBloc),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  /// The app-theme selector is the first of the two Light/System/Dark rows;
  /// the minimal-map theme selector is the second.
  Finder appTheme(String label) => find
      .descendant(
        of: find.byType(SegmentedButton<ThemeMode>).first,
        matching: find.text(label),
      )
      .first;
  Finder mapTheme(String label) => find
      .descendant(
        of: find.byType(SegmentedButton<ThemeMode>).last,
        matching: find.text(label),
      )
      .first;

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  group('SettingsScreen appearance', () {
    testWidgets('reflects the current theme mode', (tester) async {
      whenListen(
        themeCubit,
        const Stream<ThemeMode>.empty(),
        initialState: ThemeMode.dark,
      );
      await pumpSettings(tester);

      final selector = tester.widget<SegmentedButton<ThemeMode>>(
        find.byType(SegmentedButton<ThemeMode>).first,
      );
      expect(selector.selected, {ThemeMode.dark});
    });

    for (final entry in {
      'Light': ThemeMode.light,
      'Dark': ThemeMode.dark,
    }.entries) {
      testWidgets('${entry.key} sets the app theme to ${entry.value}', (
        tester,
      ) async {
        await pumpSettings(tester);

        await tapVisible(tester, appTheme(entry.key));

        verify(() => themeCubit.setTheme(entry.value)).called(1);
        verifyNever(() => mapSettings.setMapTheme(any()));
      });
    }

    testWidgets('System sets the app theme back to system', (tester) async {
      whenListen(
        themeCubit,
        const Stream<ThemeMode>.empty(),
        initialState: ThemeMode.light,
      );
      await pumpSettings(tester);

      await tapVisible(tester, appTheme('System'));

      verify(() => themeCubit.setTheme(ThemeMode.system)).called(1);
    });

    testWidgets('the selector follows ThemeCubit emissions', (tester) async {
      final controller = StreamController<ThemeMode>();
      addTearDown(controller.close);
      whenListen(themeCubit, controller.stream, initialState: ThemeMode.system);
      await pumpSettings(tester);

      controller.add(ThemeMode.light);
      await tester.pump();
      await tester.pump();

      final selector = tester.widget<SegmentedButton<ThemeMode>>(
        find.byType(SegmentedButton<ThemeMode>).first,
      );
      expect(selector.selected, {ThemeMode.light});
    });
  });

  group('SettingsScreen default map settings', () {
    testWidgets('reflects every current map setting', (tester) async {
      whenListen(
        mapSettings,
        const Stream<MapSettingsState>.empty(),
        initialState: const MapSettingsState(
          mapType: MapType.satellite,
          themeMode: ThemeMode.dark,
          showControls: false,
          distanceUnit: DistanceUnit.imperial,
        ),
      );
      await pumpSettings(tester);

      expect(
        tester
            .widget<SegmentedButton<MapType>>(
              find.byType(SegmentedButton<MapType>),
            )
            .selected,
        {MapType.satellite},
      );
      expect(
        tester
            .widget<SegmentedButton<ThemeMode>>(
              find.byType(SegmentedButton<ThemeMode>).last,
            )
            .selected,
        {ThemeMode.dark},
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(
        tester
            .widget<SegmentedButton<DistanceUnit>>(
              find.byType(SegmentedButton<DistanceUnit>),
            )
            .selected,
        {DistanceUnit.imperial},
      );
    });

    for (final entry in {
      'Satellite': MapType.satellite,
      'Minimal': MapType.minimal,
    }.entries) {
      testWidgets('${entry.key} sets the map type', (tester) async {
        await pumpSettings(tester);

        await tapVisible(tester, find.text(entry.key));

        verify(() => mapSettings.setMapType(entry.value)).called(1);
      });
    }

    testWidgets('Standard sets the map type back to standard', (tester) async {
      whenListen(
        mapSettings,
        const Stream<MapSettingsState>.empty(),
        initialState: const MapSettingsState(mapType: MapType.minimal),
      );
      await pumpSettings(tester);

      await tapVisible(tester, find.text('Standard'));

      verify(() => mapSettings.setMapType(MapType.standard)).called(1);
    });

    testWidgets('the minimal map theme row sets the map theme, not the app '
        'theme', (tester) async {
      await pumpSettings(tester);

      await tapVisible(tester, mapTheme('Dark'));

      verify(() => mapSettings.setMapTheme(ThemeMode.dark)).called(1);
      verifyNever(() => themeCubit.setTheme(any()));
    });

    testWidgets('Show Map Controls toggles the controls once', (tester) async {
      await pumpSettings(tester);

      await tapVisible(tester, find.byType(Switch));

      verify(() => mapSettings.toggleControls()).called(1);
    });

    testWidgets('Imperial sets the distance unit', (tester) async {
      await pumpSettings(tester);

      await tapVisible(tester, find.text('Imperial (mi)'));

      verify(
        () => mapSettings.setDistanceUnit(DistanceUnit.imperial),
      ).called(1);
    });

    testWidgets('Metric sets the distance unit back', (tester) async {
      whenListen(
        mapSettings,
        const Stream<MapSettingsState>.empty(),
        initialState: const MapSettingsState(
          distanceUnit: DistanceUnit.imperial,
        ),
      );
      await pumpSettings(tester);

      await tapVisible(tester, find.text('Metric (km)'));

      verify(() => mapSettings.setDistanceUnit(DistanceUnit.metric)).called(1);
    });
  });

  group('SettingsScreen location', () {
    testWidgets('Use Current Location requests permission', (tester) async {
      await pumpSettings(tester);

      await tapVisible(tester, find.text('Use Current Location'));

      verify(
        () => locationBloc.add(any(that: isA<RequestPermission>())),
      ).called(1);
    });

    testWidgets('while locating, the button gives way to the pulse', (
      tester,
    ) async {
      whenListen(
        locationBloc,
        const Stream<LocationState>.empty(),
        initialState: LocationLoading(),
      );
      await pumpSettings(tester);

      expect(find.text('Use Current Location'), findsNothing);
      expect(find.byType(PulseIndicator), findsOneWidget);
    });

    for (final entry in <String, LocationState>{
      'Location permission denied': LocationPermissionDenied(),
      'Location permission denied forever': LocationPermissionDeniedForever(),
      'Location loaded': const LocationLoaded(),
    }.entries) {
      testWidgets('toasts "${entry.key}"', (tester) async {
        final controller = StreamController<LocationState>();
        addTearDown(controller.close);
        whenListen(
          locationBloc,
          controller.stream,
          initialState: LocationLoading(),
        );
        await pumpSettings(tester);

        controller.add(entry.value);
        await tester.pump();
        await tester.pump();

        expect(find.text(entry.key), findsOneWidget);
      });
    }

    testWidgets('a location error raises no toast', (tester) async {
      final controller = StreamController<LocationState>();
      addTearDown(controller.close);
      whenListen(
        locationBloc,
        controller.stream,
        initialState: LocationLoading(),
      );
      await pumpSettings(tester);

      controller.add(const LocationError('boom'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
