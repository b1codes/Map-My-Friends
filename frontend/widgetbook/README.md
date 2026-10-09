# Map My Friends — Widgetbook

A catalog of every component in `lib/components` and every screen in `lib/screens`. Each entry renders the widget the app actually ships, on the app's real theme, with knobs for its states.

## Run it

```sh
cd frontend/widgetbook
flutter pub get
flutter run -d chrome   # or -d macos
```

Deep links work: `/#/?path=screens/people/peoplescreen/states` opens one entry directly.

## Add an entry

1. Write a top-level function annotated with `@widgetbook.UseCase` in `lib/use_cases/`, next to its neighbours. Use the source tree for the path: `[Components]/shared`, `[Screens]/people`, and so on.
2. Regenerate the navigation tree:
   ```sh
   dart run build_runner build
   ```
3. Commit the regenerated `lib/main.directories.g.dart`. CI fails if it is out of date.

`test/use_cases_smoke_test.dart` opens every entry and fails on anything it throws, so a broken entry shows up in CI, not in review.

## How entries are built

| Piece | Why |
| --- | --- |
| `Stage` | Stands up what the shell provides in production: the Ambient Field and one `BackdropGroup`. Glass over a flat canvas is not the material the app ships, and `GlassContainer` asserts without a group. `Stage.screen` is for tab screens, `Stage.route` for anything that brings its own room, and `Stage.pushed` for screens the app only pushes. |
| `StoryScope` | Provides every bloc the app reads, each pinned to a state. Fakes keep the real types (`StoryPeopleBloc implements PeopleBloc`), so screens resolve them unchanged; events are swallowed, so nothing touches Auth0, the API, or location services. A knob change moves the existing bloc to the new state, so listeners fire as they do in the app. |
| `Fixtures` | One sample world shared by every entry. All dates hang off a fixed `Fixtures.now`, so contact recency (and its thermal colours) reads the same on every run. `maximiliane` is the long-name stress case. |
| `AppAssetBundle` | The app loads `assets/…`; as a dependency its files are bundled under `packages/map_my_friends/…`. The shim maps one to the other. |
| `MediaPreferencesAddon` | Toggles reduced motion and high contrast. Both change what the design system draws: a still field, and opaque glass. |

## Network

Almost everything is offline. The exceptions:

- Map tiles and the Trip details route line load from their public servers.
- The nearby airports and stations sections *inside* Person details and Me call the API at `ApiConfig.baseUrl`; without the backend they show their error state. Their own entries take an injected bloc and cover every state offline.

Generator telemetry is disabled in `build.yaml`.

## Versions

`widgetbook` is held at 3.23, the newest release that supports Flutter 3.41, which CI pins. 3.24 onward needs Flutter 3.44, so bump the two together.
