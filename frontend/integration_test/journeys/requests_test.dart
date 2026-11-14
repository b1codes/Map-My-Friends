// Request budgets: what the app asks the API for when it opens and as the
// user moves between tabs. Each request costs the user a round trip, and
// the API an instance's time and Firestore reads. A screen that asks again
// for what the app already has, or asks twice at once, is a regression the
// other journeys wouldn't notice. The E2E stack's API logs every request
// (docker/test-stack-settings/request_log.py), from whichever of the app's
// HTTP clients sent it.
import 'package:flutter_test/flutter_test.dart';

import '../support/e2e.dart';

/// Counts by `METHOD path`, so an assertion failure shows what was sent.
Map<String, int> counted(List<String> requests) {
  final counts = <String, int>{};
  for (final request in requests) {
    counts[request] = (counts[request] ?? 0) + 1;
  }
  return counts;
}

Future<JourneyUser> userWithPeople(String prefix) async {
  final user = await JourneyUser.registered(prefix);
  await user.addPerson(firstName: 'Ada', lastName: 'Lovelace');
  await user.addPerson(firstName: 'Alan', lastName: 'Turing');
  return user;
}

void main() {
  setUpE2E();

  group('Requests', () {
    journey('opening the app asks for the profile, people and trips once', (
      tester,
    ) async {
      final user = await userWithPeople('reqopen');
      await E2EApi.clearRequestLog();

      await launchSignedIn(tester, user);
      // Long enough for any late or repeated load to land.
      await settle(tester, const Duration(seconds: 3));

      expect(counted(await E2EApi.requestLog(user)), {
        'GET /api/user/profile/': 1,
        'GET /api/people/': 1,
        'GET /api/trips/': 1,
      });
    });

    journey(
      'moving between tabs asks only for what a tab hasn\'t got',
      (tester) async {
        final user = await userWithPeople('reqtabs');
        await launchSignedIn(tester, user);
        await settle(tester, const Duration(seconds: 3));

        // Pulse needs the contact logs; it has the people already. Every
        // other tab shows what the app loaded when it opened.
        const expected = {
          'People': <String, int>{},
          'Trips': <String, int>{},
          'Pulse': {'GET /api/contact-logs/': 1},
          'Me': <String, int>{},
          'Map': <String, int>{},
        };
        for (final MapEntry(key: name, value: requests) in expected.entries) {
          await E2EApi.clearRequestLog();
          await goToTab(tester, name);
          await settle(tester, const Duration(seconds: 2));
          expect(
            counted(await E2EApi.requestLog(user)),
            requests,
            reason: 'opening the $name tab',
          );
        }
      },
      skip:
          'Known gap: every Pulse visit refetches people and every Me visit '
          'the profile (https://app.clickup.com/t/86bd054ar)',
    );
  });
}
