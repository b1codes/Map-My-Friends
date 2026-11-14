# golden_harness

What every golden test shares, in the app (`frontend/test`) and in the Widgetbook catalog (`frontend/widgetbook/test`): real fonts, the reference platform, a pinned clock, and a comparator that says what to do when an image changes. It's a dev dependency of both, by path, and nothing in it ships in the app.

How the goldens work, and how to run and update them, is in [docs/testing.md](../../docs/testing.md#visual-regression-goldens).

## Use it

```dart
void main() {
  setUpGoldens();

  goldenTest('Pulse screen, light', now: DateTime(2026, 7, 22), (tester) async {
    await tester.pumpWidget(...);
    await expectGolden(tester, find.byType(PulseScreen), 'goldens/pulse_light.png');
  });
}
```

- `setUpGoldens()` loads the fonts and installs the comparator, once per file.
- `goldenTest` tags the test `golden`, skips it anywhere but Linux x64, and with `now:` runs it with `clock.now()` pinned.
- `expectGolden` decodes every image on screen first (so a golden never depends on whether an earlier test cached it), then compares.
- `loadRealFonts()` loads just the fonts, on any platform, for a test that checks layout rather than pixels. The catalog's accessibility test uses it to check text at 200% (`setUpAll(loadRealFonts)`). Like `setUpGoldens`, it changes the font for every test in the file.

## Fonts

`fonts/` holds the Montserrat and Open Sans weights the app's theme and screens use. They are byte-for-byte the files google_fonts downloads at runtime (each checked against the SHA-256 it pins), renamed the way google_fonts looks for bundled fonts, e.g. `Montserrat-SemiBold.ttf`. This package's assets are bundled into the tests of the packages that depend on it, so google_fonts finds them there and never goes to the network. Both families are under the SIL Open Font License; the licences are next to the files.

Roboto and the Material icons come from the Flutter SDK, and Cupertino icons from the app's own bundle.

If the app starts using another weight, a golden fails and names the missing face and its URL. Save that URL in `fonts/` under the name the error gives.
