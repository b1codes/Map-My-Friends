import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_harness/golden_harness.dart';
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
  setUpGoldens();

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

  Widget harness(PulseBloc bloc, {required Brightness brightness}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
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

  goldenTest('Pulse screen — mobile light', now: now, (tester) async {
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

    await expectGolden(
      tester,
      find.byType(PulseScreen),
      'goldens/pulse_mobile_light.png',
    );
  });

  goldenTest('Pulse screen — mobile dark', now: now, (tester) async {
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

    await expectGolden(
      tester,
      find.byType(PulseScreen),
      'goldens/pulse_mobile_dark.png',
    );
  });
}
