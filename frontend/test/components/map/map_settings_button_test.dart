import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/map/local_map_settings_cubit.dart';
import 'package:map_my_friends/bloc/map/map_settings_cubit.dart';
import 'package:map_my_friends/components/map/map_settings_button.dart';
import 'package:map_my_friends/components/map/map_settings_modal.dart';

void main() {
  late LocalMapSettingsCubit cubit;

  setUp(() {
    cubit = LocalMapSettingsCubit(initialState: const MapSettingsState());
  });

  tearDown(() => cubit.close());

  Future<void> pumpButton(WidgetTester tester, {double topPadding = 0}) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<LocalMapSettingsCubit>.value(
        value: cubit,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(600, 1400),
              padding: EdgeInsets.only(top: topPadding),
            ),
            child: BackdropGroup(
              child: const Scaffold(
                body: Stack(children: [MapSettingsButton()]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('floats below the top safe area at the right edge', (
    tester,
  ) async {
    await pumpButton(tester, topPadding: 30);

    final positioned = tester.widget<Positioned>(find.byType(Positioned));
    expect(positioned.top, 46);
    expect(positioned.right, 16);
  });

  testWidgets('opens the settings modal on tap', (tester) async {
    await pumpButton(tester);
    expect(find.byType(MapSettingsModal), findsNothing);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.byType(MapSettingsModal), findsOneWidget);
    expect(find.text('Map Settings'), findsOneWidget);
  });

  testWidgets('the modal edits the map session cubit the button sits under', (
    tester,
  ) async {
    await pumpButton(tester);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Map Controls'));
    await tester.pump();

    expect(cubit.state.showControls, isFalse);
  });
}
