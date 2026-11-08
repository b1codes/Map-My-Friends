/// Targeted edge cases: the things the monkey does at random, done on
/// purpose on each main screen, with the outcome checked, not just the
/// absence of a crash.
///
/// The real app (`MyApp`, wired as `main.dart` wires it) runs over the
/// monkey's in-memory API ([AppSession]), so a double tap is checked by
/// counting the requests that reached the API, and a slow or missing
/// network is the real app's real Dio timing out or failing. Filed layout
/// problems are known gaps, as in the monkey (test/monkey/known_gaps.dart);
/// anything else the app reports fails the test.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_my_friends/components/people/person_card.dart';

import '../monkey/app_session.dart';
import '../monkey/known_gaps.dart';
import '../monkey/monkey.dart';

const _phone = Size(390, 844);
const _phoneLandscape = Size(844, 390);

/// One edge case on a fresh launch of the app. Fails on any error the app
/// reports that isn't a known gap, as well as on the body's own checks.
///
/// [skip] is the reason a case is off: 'Known bug: … (ClickUp link)'. A case
/// that finds a bug keeps asserting the right behaviour and is skipped until
/// the bug is fixed, as the E2E journeys do.
void edgeCase(
  String description,
  Future<void> Function(WidgetTester tester, AppSession app) body, {
  Size window = _phone,
  bool signedIn = true,
  Duration latency = Duration.zero,
  String? skip,
}) {
  if (skip != null) debugPrint('Skipping "$description": $skip');
  testWidgets(skip: skip != null, description, (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await AppSession.start(
      tester,
      window: window,
      signedIn: signedIn,
      latency: latency,
    );
    final errors = ErrorWatch(knownGaps)..start();
    try {
      await body(tester, app);
      await _wait(tester, const Duration(seconds: 5));
      errors.expectNone(tester);
    } finally {
      errors.stop();
      app.restore(tester);
      semantics.dispose();
    }
    await AppSession.unmount(tester);
  });
}

/// Pumps frames for [time]. The app animates forever, so it never settles.
Future<void> _wait(
  WidgetTester tester, [
  Duration time = const Duration(milliseconds: 600),
]) async {
  final end = time.inMilliseconds;
  for (var t = 0; t < end; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _tab(String name) => find.bySemanticsLabel(RegExp('^$name Tab'));

Future<void> _goTo(WidgetTester tester, String tab) async {
  await tester.tap(_tab(tab).first);
  await _wait(tester);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 50));
}

/// Two taps 60 ms apart: a double tap, or an impatient second press.
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 100));
  final at = tester.getCenter(finder.first);
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(at);
}

/// The text field labelled [label], even if it's scrolled out of view.
Finder _field(String label) => find
    .ancestor(
      of: find.text(label, skipOffstage: false),
      matching: find.byType(TextField, skipOffstage: false),
    )
    .first;

/// [text] anywhere in the tree, on screen or scrolled out of it.
Finder _text(String text) => find.text(text, skipOffstage: false);

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), text);
  await tester.pump();
}

final _addPerson = find.byTooltip('Add person');
final _savePerson = find.widgetWithText(FilledButton, 'Save Person');

Future<void> _openNewPersonForm(WidgetTester tester) async {
  await _goTo(tester, 'People');
  await _tapVisible(tester, _addPerson);
  await _wait(tester);
}

Future<void> _fillPerson(
  WidgetTester tester, {
  String first = 'Ada',
  String last = 'Lovelace',
  String city = 'London',
}) async {
  await _enter(tester, 'First Name', first);
  await _enter(tester, 'Last Name', last);
  await _enter(tester, 'City (Required)', city);
  await _enter(tester, 'State (Required)', 'England');
  await _enter(tester, 'Country (Required)', 'UK');
}

/// The system back button (Android's, the browser's), through the same
/// channel the engine uses.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      const MethodCall('popRoute'),
    ),
    (_) {},
  );
  await tester.pump();
}

Future<void> _backgroundAndResume(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump(const Duration(milliseconds: 200));
  }
}

String _fieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

/// The text fields of a multipart request, by name.
Map<String, String> _formFields(String body) => {
  for (final m in RegExp(
    r'name="([^"]+)"\r\n\r\n([\s\S]*?)\r\n--',
  ).allMatches(body))
    m.group(1)!: m.group(2)!,
};

const _tabs = ['Map', 'People', 'Pulse', 'Trips', 'Me'];

/// The profile's required address. The seeded account (the contract's
/// fixture) has none yet, so Save Profile would only show the errors.
Future<void> _fillProfileAddress(WidgetTester tester) async {
  await _enter(tester, 'City (Required)', 'Leeds');
  await _enter(tester, 'State (Required)', 'Yorkshire');
  await _enter(tester, 'Country (Required)', 'UK');
}

void main() {
  setUpAll(setUpAppSessions);

  group('a double tap submits once', () {
    edgeCase('saving a new person', (tester, app) async {
      await _openNewPersonForm(tester);
      await _fillPerson(tester);
      await _doubleTap(tester, _savePerson);
      await _wait(tester, const Duration(seconds: 2));

      expect(app.requestsTo('POST', 'people/'), hasLength(1));
      // The form closes on the first tap, so the second lands on whatever
      // was under it (here the Me tab). Back to the list to count.
      await _goTo(tester, 'People');
      expect(find.text('7 people'), findsOneWidget);
    });

    edgeCase('logging a call', (tester, app) async {
      await _goTo(tester, 'Pulse');
      await _tapVisible(tester, _text('Grace Hopper'));
      await _wait(tester);
      // Grace has a phone number, so the sheet offers "Call & log" (which
      // opens the dialler) and "Just log it".
      await _doubleTap(tester, _text('Just log it'));
      await _wait(tester, const Duration(seconds: 2));

      expect(app.requestsTo('POST', 'contact-logs/'), hasLength(1));
    });

    edgeCase(
      'saving the profile',
      skip:
          'Known bug: a double tap sends the profile twice '
          '(https://app.clickup.com/t/86bd08v6n)',
      (tester, app) async {
        await _goTo(tester, 'Me');
        await _fillProfileAddress(tester);
        await _doubleTap(tester, _text('Save Profile'));
        await _wait(tester, const Duration(seconds: 2));

        expect(app.requestsTo('PATCH', 'user/profile/'), hasLength(1));
      },
    );

    edgeCase('signing in', signedIn: false, (tester, app) async {
      await _wait(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'ada');
      await tester.enterText(fields.at(1), 'Analytical-Engine-1843');
      await _doubleTap(tester, find.widgetWithText(FilledButton, 'Sign In'));
      await _wait(tester, const Duration(seconds: 2));

      expect(app.requestsTo('POST', 'user/auth/token/'), hasLength(1));
      expect(_tab('Map'), findsWidgets);
    });

    edgeCase('saving a planned trip', (tester, app) async {
      await _goTo(tester, 'People');
      await _tapVisible(tester, _text('Grace Hopper'));
      await _wait(tester);
      await _tapVisible(tester, _text('Add to Trip Planner'));
      await _systemBack(tester);
      // "Added Grace to trip" covers the tab bar until it times out
      // (https://app.clickup.com/t/86bd08v6r).
      await _wait(tester, const Duration(seconds: 5));
      await _goTo(tester, 'Map');
      await _doubleTap(tester, find.bySemanticsLabel('Save Trip'));
      await _wait(tester, const Duration(seconds: 2));

      expect(app.requestsTo('POST', 'trips/'), hasLength(1));
    });
  });

  group('taps while a screen is loading', () {
    edgeCase(
      'every tab, as fast as they come, then the data arrives',
      latency: const Duration(seconds: 2),
      (tester, app) async {
        for (var round = 0; round < 3; round++) {
          for (final tab in _tabs) {
            await tester.tap(_tab(tab).first);
            await tester.pump(const Duration(milliseconds: 50));
          }
        }
        await _goTo(tester, 'People');
        await _wait(tester, const Duration(seconds: 5));

        expect(find.text('6 people'), findsOneWidget);
      },
    );

    edgeCase(
      'saving a person, then saving again before the answer',
      latency: const Duration(seconds: 2),
      (tester, app) async {
        await _wait(tester, const Duration(seconds: 3));
        await _openNewPersonForm(tester);
        await _fillPerson(tester);
        await _tapVisible(tester, _savePerson);
        await tester.pump(const Duration(milliseconds: 500));
        if (_savePerson.evaluate().isNotEmpty) {
          await tester.tap(_savePerson.first, warnIfMissed: false);
        }
        await _wait(tester, const Duration(seconds: 5));

        expect(app.requestsTo('POST', 'people/'), hasLength(1));
      },
    );
  });

  group('back in the middle of a request', () {
    edgeCase(
      'leaving the form while the save is on its way',
      latency: const Duration(seconds: 2),
      (tester, app) async {
        await _wait(tester, const Duration(seconds: 3));
        await _openNewPersonForm(tester);
        await _fillPerson(tester);
        await _tapVisible(tester, _savePerson);
        await tester.pump(const Duration(milliseconds: 300));
        await _systemBack(tester);
        await _wait(tester, const Duration(seconds: 5));

        expect(app.requestsTo('POST', 'people/'), hasLength(1));
        await _goTo(tester, 'People');
        expect(find.text('7 people'), findsOneWidget);
      },
    );

    edgeCase(
      'leaving a person while their details load',
      latency: const Duration(seconds: 2),
      (tester, app) async {
        await _wait(tester, const Duration(seconds: 3));
        await _goTo(tester, 'People');
        await _tapVisible(tester, _text('Grace Hopper'));
        await tester.pump(const Duration(milliseconds: 300));
        await _systemBack(tester);
        await _wait(tester, const Duration(seconds: 5));

        expect(find.text('6 people'), findsOneWidget);
      },
    );
  });

  group('background and back', () {
    for (final tab in _tabs) {
      edgeCase('on $tab', (tester, app) async {
        await _goTo(tester, tab);
        await _backgroundAndResume(tester);
        await _wait(tester);

        expect(
          tester.widget<Semantics>(_tabSemantics(tab)).properties.selected,
          isTrue,
          reason: 'the app should come back on the same tab',
        );
      });
    }

    edgeCase('with a half-filled form, which keeps its text', (
      tester,
      app,
    ) async {
      await _openNewPersonForm(tester);
      await _enter(tester, 'First Name', 'Ada');
      await _backgroundAndResume(tester);
      await _wait(tester);

      expect(_fieldText(tester, 'First Name'), 'Ada');
    });
  });

  group('rotation', () {
    for (final tab in _tabs) {
      edgeCase('on $tab', (tester, app) async {
        await _goTo(tester, tab);
        tester.view.physicalSize = _phoneLandscape;
        await _wait(tester);
        tester.view.physicalSize = _phone;
        await _wait(tester);

        expect(_tab(tab), findsWidgets);
      });
    }

    edgeCase('with a half-filled form, which keeps its text', (
      tester,
      app,
    ) async {
      await _openNewPersonForm(tester);
      await _enter(tester, 'First Name', 'Ada');
      tester.view.physicalSize = _phoneLandscape;
      await _wait(tester);
      tester.view.physicalSize = _phone;
      await _wait(tester);

      expect(_fieldText(tester, 'First Name'), 'Ada');
    });
  });

  group('offline and slow', () {
    edgeCase('offline at launch, then back online', (tester, app) async {
      app.http.offline = true;
      await _goTo(tester, 'Pulse');
      await _wait(tester, const Duration(seconds: 10));
      expect(find.text("Couldn't load your circle"), findsOneWidget);

      app.http.offline = false;
      await _tapVisible(tester, find.text('Try again'));
      await _wait(tester, const Duration(seconds: 2));
      expect(find.text("Couldn't load your circle"), findsNothing);
      expect(_text('Grace Hopper'), findsWidgets);
    });

    edgeCase('saving a person offline keeps the form', (tester, app) async {
      await _openNewPersonForm(tester);
      await _fillPerson(tester);
      app.http.offline = true;
      await _tapVisible(tester, _savePerson);
      await _wait(tester, const Duration(seconds: 10));

      expect(_savePerson, findsOneWidget, reason: 'the form should stay open');
      expect(_fieldText(tester, 'First Name'), 'Ada');
    });

    edgeCase(
      'a slow network shows the wait, then the data',
      latency: const Duration(seconds: 3),
      (tester, app) async {
        await _goTo(tester, 'Pulse');
        expect(_text('Grace Hopper'), findsNothing);
        await _wait(tester, const Duration(seconds: 8));
        expect(_text('Grace Hopper'), findsWidgets);
      },
    );
  });

  group('large text', () {
    for (final scale in [1.3, 2.0]) {
      for (final tab in _tabs) {
        edgeCase('×$scale on $tab', (tester, app) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await _goTo(tester, tab);
          await _wait(tester);

          expect(_tab(tab), findsWidgets);
        });
      }
    }
  });

  group('long names, special characters and emoji', () {
    final long = List.filled(100, 'Wolfeschlegel').join();
    const awkward = <String, String>{
      'emoji': '🦄👩🏽‍💻🇮🇪',
      'right-to-left': 'نور الهدى',
      'combining marks': 'Zoë é́',
      'markup': '<script>alert(1)</script>',
      'SQL': "Robert'); DROP TABLE people;--",
      'format string': '%s%n{0}',
    };

    edgeCase('a 1,300-character name is saved and shown', (tester, app) async {
      await _openNewPersonForm(tester);
      await _fillPerson(tester, first: long);
      await _tapVisible(tester, _savePerson);
      await _wait(tester, const Duration(seconds: 2));

      final sent = app.requestsTo('POST', 'people/').single;
      expect(_formFields(sent.bodyText)['first_name'], long);
      expect(
        find.textContaining('Wolfeschlegel', skipOffstage: false),
        findsWidgets,
      );
    });

    for (final MapEntry(key: kind, value: text) in awkward.entries) {
      edgeCase('a name with $kind is saved and shown as typed', (
        tester,
        app,
      ) async {
        await _openNewPersonForm(tester);
        await _fillPerson(tester, first: text, last: text, city: text);
        await _tapVisible(tester, _savePerson);
        await _wait(tester, const Duration(seconds: 2));

        final fields = _formFields(
          app.requestsTo('POST', 'people/').single.bodyText,
        );
        expect(fields['first_name'], text);
        expect(fields['city'], text);
        expect(
          find.descendant(
            of: find.byType(PersonCard, skipOffstage: false),
            matching: _text('$text $text'),
          ),
          findsOneWidget,
        );
      });
    }

    edgeCase('the profile keeps an emoji name', (tester, app) async {
      await _goTo(tester, 'Me');
      await _enter(tester, 'First Name', '🦄✨');
      await _fillProfileAddress(tester);
      await _tapVisible(tester, _text('Save Profile'));
      await _wait(tester, const Duration(seconds: 2));

      final sent = app.requestsTo('PATCH', 'user/profile/').single;
      expect(
        (jsonDecode(sent.bodyText) as Map<String, dynamic>)['first_name'],
        '🦄✨',
      );
    });
  });
}

/// The navigation item's Semantics, which says whether it's selected.
Finder _tabSemantics(String name) => find
    .byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == '$name Tab',
    )
    .first;
