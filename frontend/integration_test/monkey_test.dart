// The device-level monkey: the monkey engine (support/monkey/monkey.dart) on
// the real web engine and plugins, in Chrome, against the real API on the
// E2E stack. Nothing is faked: requests reach Django and the Firestore
// emulator, images decode in the browser, text is laid out by the browser's
// engine.
//
// It runs nightly (.github/workflows/monkey.yml), not per PR: `make
// monkey-web` locally. MONKEY_SEED (a number, or 'random'), MONKEY_STEPS and
// MONKEY_MINUTES are dart-defines, which scripts/e2e.sh passes through. A
// failure names the seed and the last actions, and the journey harness saves
// a screenshot.
//
// Not part of all_test.dart: the per-PR journeys stay deterministic.
import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/monkey/known_gaps.dart';
import 'support/monkey/monkey.dart';

const _seedDefine = String.fromEnvironment(
  'MONKEY_SEED',
  defaultValue: '20261108',
);
const _steps = int.fromEnvironment('MONKEY_STEPS', defaultValue: 400);
const _minutes = int.fromEnvironment('MONKEY_MINUTES');

void main() {
  setUpE2E();

  final seed = _seedDefine == 'random'
      ? Random().nextInt(1 << 31)
      : int.parse(_seedDefine);
  final steps = _minutes == 0 ? _steps : 1 << 30;

  journey('the monkey on the real web engine (seed $seed)', (tester) async {
    final deadline = _minutes == 0
        ? null
        : DateTime.now().add(const Duration(minutes: _minutes));

    // An account with awkward data to wander through. The stub geocoder only
    // knows real cities, so the awkwardness is in the names.
    final user = await JourneyUser.registered('monkey');
    for (final (first, last) in const [
      ('Grace', 'Hopper'),
      ('Maximiliana-Theodora-Wilhelmina', 'von Hohenzollern-Sigmaringen'),
      ('🦄✨', '👩🏽‍💻'),
      ('نور', 'الهدى'),
      ('Zoë', "O'Brien-Ñúñez"),
    ]) {
      await user.addPerson(firstName: first, lastName: last);
    }
    await launchSignedIn(tester, user);

    var signedOutFor = 0;
    final monkey = Monkey(
      tester,
      seed: seed,
      knownGaps: knownGaps,
      // Each action, to the stub server's stdout (the stack's log, uploaded
      // on failure): a test's own prints don't reach the drive output, and a
      // hang should still say where it was.
      onRecord: (entry) => unawaited(
        Dio()
            .get<void>(
              '$stubsUrl/_stub/monkey',
              queryParameters: {'entry': '[seed $seed] $entry'},
            )
            .then((_) {}, onError: (Object _) {}),
      ),
      // Hosted sign-in leaves the app for Auth0's page, which ends the run.
      avoid: [
        find.textContaining('Auth0'),
        find.text('Google'),
        find.text('Apple'),
      ],
      // Random typing never signs back in. After a few steps signed out,
      // sign in the way a user would, so the run keeps exploring.
      recover: (_) async {
        if (loginScreen.evaluate().isEmpty) {
          signedOutFor = 0;
          return null;
        }
        if (++signedOutFor < 8) return null;
        signedOutFor = 0;
        await signInThroughUi(tester, user.username);
        return 'sign back in as ${user.username}';
      },
    );
    // The integration binding leaves the test keyboard unregistered, which
    // the monkey types and presses Done through, as in the widget tests.
    tester.testTextInput.register();
    try {
      await monkey.run(steps: steps, until: deadline);
      await monkey.settle();
    } finally {
      monkey.reset();
      tester.testTextInput.unregister();
    }
    debugPrint(
      'Monkey (web, seed $seed): ${monkey.step} actions'
      '${monkey.knownGapHits.isEmpty ? '' : ', known gaps: ${monkey.knownGapHits.entries.map((e) => '${e.key.task} ×${e.value}').join(', ')}'}',
    );
  });
}
