# E2E journeys

These tests run the real app against the real backend and walk through what a user actually does: sign up, add a friend, log a contact, plan a trip. Each journey drives `lib/main.dart` in headless Chrome. It types into the real forms, and the API and Firestore emulator answer for real. Nothing in the app is mocked.

```sh
make e2e                                                    # every journey
make e2e JOURNEY=integration_test/journeys/auth_test.dart   # one file
```

You need Docker, Chrome and the pinned Flutter SDK (`fvm`). A full run takes a few minutes, and most of that is compiling the app once.

## What runs where

| Piece | Where | Notes |
| --- | --- | --- |
| App | `flutter drive -d web-server`, headless Chrome | Built with `API_BASE_URL`, `OSRM_BASE_URL`, `TILE_URL_TEMPLATE` and `E2E_STUBS_URL` pointing at the stack below, and `DEV_LOGIN=false` so the login screen looks like production. |
| API | `docker-compose.e2e.yml`, `localhost:8100` | The real Django app on the Firestore emulator. It's a separate compose project from `make up`, so it never touches your dev data. |
| Third parties | `docker/e2e-stubs`, `localhost:8190` | Deterministic Nominatim, OSRM and map tiles. See below. |
| chromedriver | `frontend/build/e2e/chromedriver/` | `scripts/e2e.sh` downloads one that matches your Chrome the first time. Set `CHROMEDRIVER` to use your own. |

[`scripts/e2e.sh`](../../scripts/e2e.sh) does everything: it recreates the stack, waits for it, starts chromedriver, and drives the app. Every run gets an empty emulator, a throwaway SQLite file for Django's users, and fresh throttle counters. The script's header lists the environment variables it reads. Use `E2E_HEADED=1` to watch the browser, `E2E_KEEP_STACK=1` to inspect the stack afterwards, and the port and project variables to run several stacks side by side.

### Why the third parties are stubbed

Nominatim, OSRM and the OpenStreetMap tile servers are volunteer-run. They rate-limit and change their data, and their usage policies discourage automated traffic. The contract tests in [`contracts/`](../../contracts/README.md) pin the response shapes the app relies on and check the real services every night, so the journeys only need something that answers in those shapes. The stubs answer like this:

- **Geocoding:** the cities in `CITIES` in [`server.py`](../../docker/e2e-stubs/server.py) resolve to their real coordinates. Any other city isn't found, so a journey can test that path on purpose.
- **Routing:** a route goes through a midpoint nudged off the straight line, so a road route can be told apart from the app's straight-line fallback.
- **Tiles:** one plain tile for every request.
- **Call log:** every call is logged. Read it with `E2EApi.stubLog()` and reset it with `E2EApi.clearStubLog()`.

## Writing a journey

Journeys live in `journeys/`, one file per area, and every file is imported by `all_test.dart`. `flutter drive` compiles once per target, so CI runs that single entry point.

```dart
void main() {
  setUpE2E();

  journey('a user adds a friend', (tester) async {
    final user = await JourneyUser.registered('friend'); // seeded via the API
    await launchSignedIn(tester, user);                  // real login form
    await goToTab(tester, 'People');
    ...
  });
}
```

The helpers are in [`support/e2e.dart`](support/e2e.dart):

- **`journey`** is `testWidgets` plus a screenshot of the screen on failure. Screenshots are saved to `frontend/build/e2e/screenshots/`, and CI uploads them as the `e2e-screenshots` artifact.
- **`pumpUntil` / `pumpUntilGone`** replace `pumpAndSettle`. The app animates forever (the ambient background and the pulse indicators), so it never settles. On a timeout the failure lists the text on screen.
- **`launchApp`** clears device storage first, so it behaves like a first visit. `launchApp(keepDeviceState: true)` is a returning user, and it's how journeys check that something survives a restart.
- **`enterField('Label', text)`, `tapText`, `tapOn`, `toast(...)` and `tab('People')`** find things the way a user does: by visible label, or by the navigation's semantics label.
- **`JourneyUser`** gives every journey its own user. It can also register one and get a signed-in `Dio` (`user.api()`) to arrange state the journey isn't about.

Conventions:

- Use the UI for the thing under test, and the API for everything else.
- Make each journey independent. Use a fresh `JourneyUser` and don't rely on order, because CI runs every file in one app session.
- Assert what a user would see, plus where it ends up on the server when that's the point. "Survives a relaunch" proves the data came from the API and not from widget state.
- If a journey finds a bug, keep it asserting the right behaviour and pass `skip: 'Known bug: … (ClickUp …)'` until the bug is fixed.

## What this doesn't cover

Some things can't run in headless Chrome. Auth0 sign-in goes through a hosted login page. Geolocation and image-picker permission prompts are native, and native mobile builds behave differently from the web build. These are on the [manual QA checklist](../../docs/manual-qa.md).
