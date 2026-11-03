# Testing and CI

What runs on every pull request, what each check enforces, and how to run the same checks locally. Each suite has its own README for details: the [contract tests](../contracts/README.md), the [E2E journeys](../frontend/integration_test/README.md), and the [manual QA checklist](manual-qa.md) for the few things automation can't reach.

## On every pull request

`.github/workflows/ci.yml` runs these jobs in parallel. **CI Passed** succeeds only when all the others did, so it's the one check to require in branch protection.

| Job | What it checks | Fails when | Locally |
| --- | --- | --- | --- |
| Lint & Format Backend | Ruff format and lint on `backend/` | anything isn't formatted, or a rule fires | `make lint-backend` |
| Test Backend | the Django suite on the Firestore emulator, in random order, under coverage | a test fails, or branch coverage is below the gate | `make test-cov` |
| Lint, Format, & Test Frontend | dart format, `flutter analyze` (the app and the golden harness), the Flutter suite in random order under coverage, goldens included | a test fails, a golden differs, the analyzer reports anything (infos too), or line coverage is below the gate | `make lint-frontend`, `make test-frontend-cov`, `make goldens` |
| Lint, Format, & Test Widgetbook | the component catalog is regenerated, formatted and analyzed, every entry opens, and every entry matches its light and dark golden | the committed catalog is stale, an entry throws, or a golden differs | `make goldens` for the goldens; see the job for the rest |
| E2E Journeys | the real app in headless Chrome against a throwaway full stack | a journey fails | `make e2e` |
| Lint Workflows | actionlint and shellcheck on every workflow | a workflow has an error | `make lint-workflows` |
| Validate Terraform Configuration | `terraform fmt` | anything isn't formatted | `terraform fmt -check -recursive infra` |

`make check` runs the linters and both coverage gates, which is everything above except the catalog, the goldens (off Linux x64) and the journeys. The backend half needs the dev stack (`make up`). Frontend targets use `fvm`; override with `make check FLUTTER=flutter DART=dart`.

The contract tests have no job of their own. They're part of the backend and frontend suites.

## Coverage gates

| Suite | Measures | Gate | Measured (2026-11-03) | Where the gate lives |
| --- | --- | --- | --- | --- |
| Backend | branch coverage of `apps/` and `config/` | 98% | 99.23% | `fail_under` in `backend/pyproject.toml` |
| Frontend | line coverage of `lib/` | 97% | 98.62% | `minimumLineCoverage` in `frontend/tool/check_coverage.dart` |

The gates sit a little under the measured totals. One uncovered line doesn't fail a PR, but an untested module, screen or endpoint does. Raise a gate when coverage rises, and don't lower one to get a PR through.

What's left out of the totals:

- **Backend:** tests, migrations and the WSGI/ASGI entry points (`[tool.coverage.run] omit`).
- **Frontend:** the generated l10n files (`excluded` in the checker).

Flutter's coverage only includes files a test loaded, so an untested new file would leave the total unchanged instead of counting as 0%. The frontend checker therefore also fails when a file in `lib/` has code that no test loads. Files that only declare constants never appear in a report, so those are allowed.

Each run puts a coverage summary on the job page and uploads the full report as an artifact: `backend-coverage` (HTML) and `frontend-coverage` (`lcov.info`).

## Visual regression (goldens)

A golden test renders a screen or component and compares it, pixel for pixel, with an image committed next to the test. There are two sets:

- **The catalog:** `frontend/widgetbook/test/catalog_golden_test.dart` opens every Widgetbook entry through the real catalog app, in light and dark, and keeps the images in `frontend/widgetbook/test/goldens/`, one directory per catalog folder. A new entry gets goldens without any extra code. A test fails if an image no longer belongs to any entry.
- **The app:** the design-system specimen, the shell at each device class, the Pulse screen and the Map screen, in `goldens/` directories under `frontend/test/`.

What makes them trustworthy:

- **One platform.** Text antialiasing and blur differ a little between macOS and Linux, and even between arm64 and x64 Linux, so goldens are recorded and compared on Linux x64, which is what CI runs. Anywhere else the golden tests report as skipped instead of failing.
- **Real fonts.** flutter_test normally draws every glyph and icon as a box. `frontend/golden_harness` loads Montserrat and Open Sans (the files google_fonts would download, committed under `golden_harness/fonts/`), Roboto and the icon fonts, so a typeface, weight or icon change shows up. Nothing is fetched over the network, and none of it ships in the app.
- **A fixed clock.** `lib/` reads the time through `package:clock` (a test enforces it), and goldens pin it, so dates, the Pulse calendar and recency colours don't change from day to day.
- **No motion.** Catalog goldens run with reduced motion, the still composition the app shows when the platform asks for it. The animated field would otherwise be caught mid-drift.

Running them:

- `make goldens` compares, and `make update-goldens` re-records. On Linux x64 they run directly. Anywhere else they run in the Flutter image pinned in `scripts/goldens.sh`, as linux/amd64, which on Apple Silicon is emulated and takes a few minutes. The image's Flutter must match `.fvmrc`, and the script refuses to run if it doesn't.
- When a golden fails, the expected, actual and diff images are written to `failures/` next to it. On CI they're uploaded as the `golden-failures-frontend` and `golden-failures-widgetbook` artifacts.
- After an intended UI change, run `make update-goldens`, look at the changed images in the diff, and commit them with the change.
- To give a new test goldens, call `setUpGoldens()` first in `main()`, write it with `goldenTest(...)` (pass `now:` if anything on screen shows a date), and compare with `expectGolden(...)`. Keep goldens in their own file: the harness loads real fonts for the whole file, which would change layout-based assertions in other tests.

## Random order

Both suites run in a random order on every CI run, so a test that only passes after another test has run fails CI. The log prints the seed. To reproduce a failure:

- Backend: `docker compose exec api python manage.py test --shuffle <seed>`
- Frontend: `fvm flutter test --test-randomize-ordering-seed <seed>`

## Static analysis

- **Python:** Ruff, configured in `backend/pyproject.toml`. On top of the defaults it turns on the rule families that find bugs or dead code: bugbear, blind `except`, Django, return and simplify checks, perf, logging, stray `print`, unused `noqa`, and others. `required-version` pins Ruff. CI installs exactly that version, and a different local Ruff refuses to run, so `make lint-backend` (which runs `uvx ruff@<that version>`) always matches CI.
- **Dart:** `frontend/analysis_options.yaml` starts from `flutter_lints` and adds `strict-casts`, `strict-inference` and `strict-raw-types`, plus lints for dynamic calls, unawaited futures, unclosed sinks and subscriptions, and non-Error throws. Style-only lints stay off, because `dart format` owns layout. The Widgetbook package has its own `analysis_options.yaml`, and the golden harness reuses the app's.
- **Workflows:** actionlint, pinned by digest in the `Makefile`, which CI calls too.

## Nightly

`.github/workflows/contracts-live.yml` checks the real Auth0, OSRM and Overpass against the third-party contracts. It runs nightly instead of per PR because those are public services with outages, and an outage shouldn't block unrelated work.

## Releases

`.github/workflows/release.yml` deploys only after CI passes on `main`:

- It runs when the CI Pipeline finishes on `main`. Its gate job continues only if that run succeeded and was a push.
- It deploys the commit CI tested, not whatever `main` points at by then. The web build checks out that commit, and the server fast-forwards to it.
- A manual run (`workflow_dispatch`) on `main` deploys `main` as it is, for when CI itself is broken. Use it sparingly.

Branch protection on `main` requires **CI Passed** (from GitHub Actions) as well as a code-owner review, so a PR can't merge with a failing job. That's a repository setting, not a file. A new CI job only blocks merges once it's listed in CI Passed's `needs`.
