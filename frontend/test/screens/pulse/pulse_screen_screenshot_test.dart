@Tags(['golden'])
library;

// Golden images only match the platform that generated them: text
// antialiasing differs between macOS and Linux, which shows up here as a
// sub-4% pixel diff with identical layout. These are tagged so CI skips them
// (`flutter test --exclude-tags golden`) and they stay useful locally, where
// they are the check on what the UI actually looks like.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/bloc/pulse/pulse_bloc.dart';
import 'package:map_my_friends/models/contact_log.dart';
import 'package:map_my_friends/models/person.dart';
import 'package:map_my_friends/screens/pulse/pulse_screen.dart';
import 'package:map_my_friends/components/shared/ambient_field.dart';
import 'package:map_my_friends/utils/app_theme.dart';

class MockPulseBloc extends MockBloc<PulseEvent, PulseState>
    implements PulseBloc {}

Person _p(
  String id,
  String first,
  String last,
  String tag,
  DateTime? lastContacted,
  String? channel,
) {
  return Person(
    id: id,
    firstName: first,
    lastName: last,
    relationshipTag: tag,
    city: 'Denver',
    state: 'CO',
    country: 'USA',
    lastContactedAt: lastContacted,
    lastContactChannel: channel,
  );
}

void main() {
  setUpAll(() {
    // Render offline: the real theme, a local typeface. See
    // AppTheme.textThemeBuilder for why this seam exists.
    AppTheme.textThemeBuilder = (color) => Typography.material2021().black
        .apply(bodyColor: color, displayColor: color);
    AppTheme.resetThemeCache();
  });

  tearDownAll(() {
    AppTheme.textThemeBuilder = AppTheme.buildBrandTextTheme;
    AppTheme.resetThemeCache();
  });

  final now = DateTime(2026, 7, 22);

  PulseLoaded sampleState() {
    final people = [
      _p(
        '1',
        'Marco',
        'Rossi',
        'FRIEND',
        now.subtract(const Duration(days: 3)),
        'MESSAGE',
      ),
      _p(
        '2',
        'Sara',
        'Lin',
        'FRIEND',
        now.subtract(const Duration(days: 12)),
        'CALL',
      ),
      _p(
        '3',
        'Dev',
        'Patel',
        'FAMILY',
        now.subtract(const Duration(days: 31)),
        'VIDEO',
      ),
      _p(
        '4',
        'Mom',
        '',
        'FAMILY',
        now.subtract(const Duration(days: 48)),
        'CALL',
      ),
      _p('5', 'Noah', 'Kim', 'FRIEND', null, null),
    ];
    final logs = [
      ContactLog(
        id: 'a',
        personId: '1',
        channel: ContactChannel.message,
        contactedAt: now.subtract(const Duration(days: 3)),
      ),
      ContactLog(
        id: 'b',
        personId: '2',
        channel: ContactChannel.call,
        contactedAt: now.subtract(const Duration(days: 12)),
      ),
      ContactLog(
        id: 'c',
        personId: '3',
        channel: ContactChannel.video,
        contactedAt: now.subtract(const Duration(days: 12)),
      ),
    ];
    return PulseLoaded(people: people, logs: logs);
  }

  // The real theme, with GoogleFonts fetching disabled so the golden renders
  // offline in the fallback face. Everything these goldens exist to check --
  // the glass material, the Ambient Field behind it, spacing, and the thermal
  // recency colours -- comes from AppTheme itself; only the typeface differs
  // from production.
  ThemeData testTheme(Brightness brightness) {
    return brightness == Brightness.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme;
  }

  Widget harness(PulseBloc bloc, {required Brightness brightness}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: testTheme(Brightness.light),
      darkTheme: testTheme(Brightness.dark),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      // Freeze the field. A drifting composition never settles, and a golden
      // of a moving surface is a golden of whichever frame the runner reached
      // first; MapField.stillPhase is the composition the reduced-motion path
      // shows anyway.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      // The shell owns the field in production; the golden has to stand it up
      // itself, or every glass surface on this screen renders against nothing
      // and the shot shows a material the app never displays.
      home: BackdropGroup(
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: AmbientField()),
            Positioned.fill(
              child: BlocProvider<PulseBloc>.value(
                value: bloc,
                child: PulseScreen(now: now),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('Pulse screen — mobile light', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = MockPulseBloc();
    whenListen(
      bloc,
      const Stream<PulseState>.empty(),
      initialState: sampleState(),
    );

    await tester.pumpWidget(harness(bloc, brightness: Brightness.light));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PulseScreen),
      matchesGoldenFile('goldens/pulse_mobile_light.png'),
    );
  });

  testWidgets('Pulse screen — mobile dark', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = MockPulseBloc();
    whenListen(
      bloc,
      const Stream<PulseState>.empty(),
      initialState: sampleState(),
    );

    await tester.pumpWidget(harness(bloc, brightness: Brightness.dark));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PulseScreen),
      matchesGoldenFile('goldens/pulse_mobile_dark.png'),
    );
  });
}
