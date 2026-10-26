# Manual QA checklist

Automation covers almost everything: the backend and frontend unit suites, the [contract tests](../contracts/README.md), and the [E2E journeys](../frontend/integration_test/README.md). This list covers only what those can't reach, which is native OS prompts, hosted third-party pages, and how the app behaves on a real device. Go through it before a release, on at least one iOS device, one Android device and desktop Chrome, signed in against the production API.

If an item here becomes automatable, move it into a suite and delete it from this list.

## Sign-in with Auth0

The E2E journeys cover username and password accounts. Auth0 redirects to a hosted login page, which can't run headless.

- [ ] **Unified Sign In (Auth0):** sign in, land on the map, and stay signed in after the app is killed and reopened.
- [ ] **Google:** sign in with an account that has used the app before, and with one that hasn't.
- [ ] **Apple:** sign in on iOS and on the web.
- [ ] **Cancelling:** close the hosted page partway through. The app returns to a usable login screen and doesn't hang.
- [ ] **Logout after Auth0:** the next launch shows the login screen.

## Location

Headless Chrome has no location, so the E2E journeys run with it unavailable.

- [ ] **First launch:** the OS permission prompt appears. After you allow it, the map centres on you.
- [ ] **Deny:** the map still works without your position. Asking again from Settings shows "Location permission denied".
- [ ] **"Don't ask again" (Android) or denied in Settings (iOS):** Settings shows "Location permission denied forever", and nothing crashes.
- [ ] **Location services off for the whole device:** the map still works without your position.

## Photos

The image picker is a native plugin.

- [ ] **Me → profile picture:** choosing from the gallery and taking a photo both work, and the photo shows after a relaunch.
- [ ] **Person form → photo:** the same, for a friend's photo.
- [ ] **First use:** the camera and photo-library permission prompts appear, and denying them doesn't crash the app.

## Links out of the app

- [ ] **Friend details → phone number:** opens the dialler (`tel:`).
- [ ] **Log contact → call / message with "open app":** opens the dialler or the messages app (`sms:`) with the number filled in.
- [ ] **Map attribution links:** open OpenStreetMap and CARTO in the browser.

## Real map tiles

The E2E stack serves a plain stub tile. Check that the real tile servers render:

- [ ] **Map styles:** standard, minimal and satellite all load in light and dark mode.
- [ ] **Localised standard map:** in German and French the map uses its localised tile server.
- [ ] **Offline tiles (iOS/Android only; the web build doesn't cache):** tiles you've already viewed still show in airplane mode.

## Feel on a real device

- [ ] **Gestures:** panning, pinch-zooming and rotating the map are smooth on a mid-range Android phone, with no stutter when clusters split.
- [ ] **Layout:** the bottom bar in portrait and the rail in landscape and on tablets don't overlap the notch, the home indicator or the keyboard.
- [ ] **Text size:** the largest system text size still leaves every screen usable.
