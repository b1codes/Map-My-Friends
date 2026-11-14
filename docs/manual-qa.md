# Manual QA checklist

Automation covers almost everything: the backend and frontend unit suites, the [contract tests](../contracts/README.md), the [E2E journeys](../frontend/integration_test/README.md), and the [accessibility checks](testing.md#accessibility). This list covers only what those can't reach, which is native OS prompts, hosted third-party pages, and how the app behaves on a real device. Go through it before a release, on at least one iOS device, one Android device and desktop Chrome, signed in against the production API.

If an item here becomes automatable, move it into a suite and delete it from this list.

The checks that need a real Google Cloud project, done once on the first deploy and again after infrastructure changes, are in [docs/deploy.md](deploy.md#the-first-deploy).

## Sign-in with Auth0

The E2E journeys cover username and password accounts. Auth0 redirects to a hosted login page, which can't run headless.

- [ ] **Unified Sign In (Auth0):** sign in, land on the map, and stay signed in after the app is killed and reopened.
- [ ] **Google:** sign in with an account that has used the app before, and with one that hasn't.
- [ ] **Apple:** sign in on iOS and on the web.
- [ ] **Cancelling:** close the hosted page partway through. The app returns to a usable login screen and doesn't hang.
- [ ] **Logout after Auth0:** the next launch shows the login screen.

## Location

The E2E journeys always run as a user who declined the location prompt.

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

## Screen readers and keyboard

The catalog checks that every control has a name, every tap target is big enough, and text has enough contrast (see [Accessibility](testing.md#accessibility)). Whether the app makes sense when you can't see it takes a person.

- [ ] **VoiceOver (iOS) and TalkBack (Android):** sign in, find a friend's pin on the map and open their sheet, add a person with a photo, log a contact, and plan, save and open a trip. Each control says what it does, and reading order follows the screen.
- [ ] **Sheets and dialogs:** while a sheet or dialog is open, the screen reader stays inside it, and closing it returns you to where you were.
- [ ] **Keyboard (web):** Tab through sign-in, register and the person form. Focus follows the layout, is always visible, and Enter submits.

## Feel on a real device

- [ ] **Gestures:** panning, pinch-zooming and rotating the map are smooth on a mid-range Android phone, with no stutter when clusters split.
- [ ] **Layout:** the bottom bar in portrait and the rail in landscape and on tablets don't overlap the notch, the home indicator or the keyboard.
- [ ] **Text size:** the largest system text size still leaves every screen usable. The catalog checks 200%. iOS's largest accessibility size is about 310%, so check that one by hand.
- [ ] **Stress:** on a native Android and iOS build, mash the controls for a minute: rapid taps on Save, two-finger taps, swipes while sheets open and close, back mid-save, background and back, rotating. The monkey covers this on the web engine only (see [Monkey and fuzz tests](testing.md#monkey-and-fuzz-tests)). On Android, `adb shell monkey -p <package> -s <seed> --throttle 100 2000` does it for you.
