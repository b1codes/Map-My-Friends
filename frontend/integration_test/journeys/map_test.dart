// The map: a user's people appear as pins (and nobody else's), a pin opens
// the person, and the base map comes from the configured tile server.
//
// Headless Chrome has no location, so the map stays on its fallback centre
// (San Francisco, zoom 13). People are seeded there so their pins are on
// screen without panning. The location prompt itself is on the manual QA
// checklist.
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/e2e.dart';

void main() {
  setUpE2E();

  group('Map', () {
    journey('a returning user sees their own people as pins, and only theirs', (
      tester,
    ) async {
      final ada = await JourneyUser.registered('mapowner');
      await ada.addPerson(firstName: 'Ada', lastName: 'Lovelace');
      final other = await JourneyUser.registered('mapother');
      await other.addPerson(firstName: 'Bob', lastName: 'Builder');

      // Signed in on a previous visit: the app opens straight onto the map.
      await launchSignedIn(tester, ada);
      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, mainShell);

      await pumpUntil(tester, pinOf('Ada Lovelace'), reason: "Ada's pin");
      expect(pinOf('Bob Builder'), findsNothing);
    });

    journey('people appear on the map straight after signing in', (
      tester,
    ) async {
      final user = await JourneyUser.registered('mapsignin');
      await user.addPerson(firstName: 'Grace', lastName: 'Hopper');

      await launchSignedIn(tester, user);

      await pumpUntil(tester, pinOf('Grace Hopper'), reason: "Grace's pin");
    });

    journey('tapping a pin opens the person, with nearby airports', (
      tester,
    ) async {
      final user = await JourneyUser.registered('mappin');
      await user.addPerson(firstName: 'Alan', lastName: 'Turing');

      await launchSignedIn(tester, user);
      await launchApp(tester, keepDeviceState: true);
      await pumpUntil(tester, pinOf('Alan Turing'), reason: "Alan's pin");

      await tapOn(tester, pinOf('Alan Turing'));
      // The pin's sheet lists the person; choosing them opens their details.
      await pumpUntil(tester, find.text('Alan Turing'));
      await tapText(tester, 'Alan Turing');

      // Nearest airports come from the API, for the person's geocoded city.
      await pumpUntil(tester, find.text('SFO'), reason: 'SFO near the person');
      expect(find.textContaining(' km'), findsWidgets);
    });

    journey('the base map is drawn from the configured tile server', (
      tester,
    ) async {
      final user = await JourneyUser.registered('maptiles');
      await E2EApi.clearStubLog();

      await launchSignedIn(tester, user);
      await settle(tester, const Duration(seconds: 2));

      final layer = tester.widget<TileLayer>(find.byType(TileLayer).first);
      expect(layer.urlTemplate, startsWith(stubsUrl));

      final tiles = (await E2EApi.stubLog()).where(
        (r) => (r['path'] as String).startsWith('/tiles/'),
      );
      expect(tiles, isNotEmpty, reason: 'the map should have loaded tiles');
    });
  });
}
