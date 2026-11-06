# Testing and CI

What runs on every pull request, what each check enforces, and how to run the same checks locally. Each suite has its own README for details: the [contract tests](../contracts/README.md), the [E2E journeys](../frontend/integration_test/README.md), and the [manual QA checklist](manual-qa.md) for the few things automation can't reach.

## On every pull request

`.github/workflows/ci.yml` runs these jobs in parallel. **CI Passed** succeeds only when all the others did, so it's the one check to require in branch protection.

| Job | What it checks | Fails when | Locally |
| --- | --- | --- | --- |
| Lint & Format Backend | Ruff format and lint on `backend/` | anything isn't formatted, or a rule fires | `make lint-backend` |
| Test Backend | the Django suite on the Firestore emulator, in random order, under coverage | a test fails, or branch coverage is below the gate | `make test-cov` |
| Lint, Format, & Test Frontend | dart format, `flutter analyze` (the app and the golden harness), the Flutter suite in random order under coverage, goldens included | a test fails, a golden differs, the analyzer reports anything (infos too), or line coverage is below the gate | `make lint-frontend`, `make test-frontend-cov`, `make goldens` |
| Lint, Format, & Test Widgetbook | the component catalog is regenerated, formatted and analyzed, every entry opens, every entry matches its light and dark golden, and every entry passes the [accessibility checks](#accessibility) | the committed catalog is stale, an entry throws, a golden differs, or an accessibility check finds a different number of problems than its known gaps record | `make goldens` for the goldens; see the job for the rest |
| E2E Journeys | the real app in headless Chrome against a throwaway full stack | a journey fails | `make e2e` |
| Lint Workflows | actionlint and shellcheck on every workflow | a workflow has an error | `make lint-workflows` |
| Validate Terraform Configuration | `terraform fmt` | anything isn't formatted | `terraform fmt -check -recursive infra` |

`make check` runs the linters and both coverage gates, which is everything above except the catalog, the goldens (off Linux x64) and the journeys. The backend half needs the dev stack (`make up`). Frontend targets use `fvm`; override with `make check FLUTTER=flutter DART=dart`.

The contract tests have no job of their own. They're part of the backend and frontend suites.

## Coverage gates

| Suite | Measures | Gate | Measured (2026-11-03) | Where the gate lives |
| --- | --- | --- | --- | --- |
| Backend | branch coverage of `apps/` and `config/` | 98% | 99.23% | `fail_under` in `backend/pyproject.toml` |
| Frontend | line coverage of `lib/` | 97% | 98.76% | `minimumLineCoverage` in `frontend/tool/check_coverage.dart` |

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

## Accessibility

Every Widgetbook entry, and the entries cover every screen, is checked against the bar `lib/utils/a11y_constants.dart` sets, in the Widgetbook job on every PR:

| Check | Fails when | Variants | File |
| --- | --- | --- | --- |
| Tap targets | a tappable node is smaller than 48x48 | light | `catalog_accessibility_test.dart` |
| Labels | a tappable node has no label or tooltip, so a screen reader can only say "button" | light | `catalog_accessibility_test.dart` |
| Large text | anything overflows with the system text size at 200% | light | `catalog_accessibility_test.dart` |
| Text contrast | text is below WCAG AA: 4.5:1, or 3:1 for large text | light and dark, each with and without high contrast | `catalog_contrast_test.dart` |

Two smaller checks sit in the app's own suite. `test/utils/app_theme_tokens_test.dart` checks every `MapSignal` ink (the colours that carry meaning as text) against both grounds. The screens and components that had unnamed controls check in their own tests that each control has a name, most with Flutter's `labeledTapTargetGuideline`.

**Known gaps.** Problems the checks already know about are listed in `frontend/widgetbook/test/support/accessibility_gaps.dart`, as a count per entry with the task that fixes them. One entry is marked as a test-font artifact instead, with the reason it isn't a real problem. A check fails on any other count. So a new problem fails CI even on an entry that already has one, and a fix has to lower the count, which keeps the list honest. A new entry starts with no gaps.

**How the checks see the app**:

- Entries open the way the catalog shows them: the first frame, knobs at their defaults, motion reduced. A dialog behind "tap to open" isn't checked, and neither is a state only a knob reaches.
- Layout checks run with the app's real fonts (`loadRealFonts()` from golden_harness), because the test font is much wider. Glyph sizes come from the font files, so the results are the same on macOS and on Linux x64.
- Contrast runs with the test font. Its glyphs are solid boxes, so the check reads the exact text colour instead of antialiased edges blended with the glass behind. Text over glass is judged against whatever the glass is over, which is what a person sees.
- flutter_test's contrast check finds a node's text by its label. A node labelled with words that also appear as visible text elsewhere can be measured against that other text. Name controls with words that aren't already on screen.
- Icons aren't measured. WCAG asks 3:1 of them.

Run them with `fvm flutter test test/catalog_accessibility_test.dart test/catalog_contrast_test.dart` in `frontend/widgetbook`, in about 20 seconds. Unlike goldens, they don't need Docker. What only a person can judge, like how a screen reader flows or where keyboard focus goes, is in the [manual QA checklist](manual-qa.md#screen-readers-and-keyboard).

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

## Security scans

Three scanners look for what the test suites can't: vulnerable dependencies, leaked secrets, and holes a live attacker could find in the running API. The authorization and rate-limit rules themselves are tested in the backend suite.

| Scan | What it checks | Fails when | Where it runs | Locally |
| --- | --- | --- | --- | --- |
| Dependency Scan | every lockfile (`backend/poetry.lock` and each `pubspec.lock`) against the [OSV](https://osv.dev) database, with OSV-Scanner | any known vulnerability that `.osv-scanner.toml` doesn't ignore | every PR (ci.yml), and nightly (security.yml), since new advisories appear without code changes | `make scan-deps` |
| Secret Scan | gitleaks' rules plus a Django `SECRET_KEY` rule (`.gitleaks.toml`) over git commits | anything that looks like a credential, unless it is an allowlisted fixture | every PR, over the PR's commits; nightly over the whole history | `make scan-secrets` (whole history), or `make scan-secrets GITLEAKS_LOG_OPTS=origin/main..HEAD` |
| ZAP API Scan | OWASP ZAP's API scan (passive and active rules: injection, error disclosure, headers, and so on) against a throwaway stack running as production does | a medium or high alert that `.zap/rules.tsv` doesn't triage, or any 5xx from the API | nightly and on demand (security.yml, workflow_dispatch); too slow for every PR (see below) | `make dast` |
| DAST route check | the scan's API definition against the routes Django serves | a route is served that the scan doesn't know, or the other way round | every PR, in Test Backend | `make check-dast-routes` (needs `make up`) |

Every scanner image is pinned by digest: OSV-Scanner in `scripts/scan-deps.sh`, gitleaks in the `Makefile`, ZAP in `scripts/dast.sh`.

### The dependency scan

The lockfiles come from the manifests git tracks, so a new package is scanned without any change here, and a missing lockfile fails rather than being skipped. `frontend/pubspec.lock` and `frontend/golden_harness/pubspec.lock` are not committed, so run `fvm flutter pub get` in both before `make scan-deps`; CI resolves them the same way the other jobs do.

### The ZAP scan

`scripts/dast.sh` documents each step. In short:

- **The stack.** `docker-compose.e2e.yml` (API, Firestore emulator, third-party stubs) with `docker-compose.dast.yml` on top, which runs the API under gunicorn with DEBUG off, a random `DJANGO_SECRET_KEY`, collected static files and the code baked into the image. Scanning a DEBUG server would report DEBUG's behaviour instead of production's. The one difference from production is that `docker/dast/dast_settings.py` raises the throttle rates: the scan sends thousands of requests as one user, and at the real rates most would get 429. It runs as project `map-my-friends-dast` on port 8200, beside the dev and E2E stacks.
- **What it attacks.** There is no hand-written OpenAPI spec. `scripts/dast_openapi.py` builds one from `contracts/api/interactions` (every request the app makes, with real bodies) plus `.zap/extra-operations.json` (endpoints the app doesn't call, which are still reachable). The route check fails when Django serves a route that neither file describes, when a listed route no longer exists, or when an extra operation gains a contract. `admin/` and `media/` are excluded there, each with its reason.
- **As whom.** `scripts/dast_seed.py` registers a user, signs in for a SimpleJWT access token, and creates a person, a contact log and a trip through the API, so ZAP's requests reach real records instead of 404s. DELETEs get a second set of records, so the first one doesn't leave the rest of the scan with nothing to attack. ZAP sends the token on every request.
- **Pass or fail.** `scripts/zap_gate.py` reads ZAP's JSON report: high and medium alerts fail, low ones warn, informational ones are listed. It prints each alert with up to five URLs and their evidence, and CI adds the same summary to the job page. Any 5xx the API answered also fails the run, listed by endpoint: it is an unhandled exception on input the API should have rejected, which ZAP itself only rates Low. The overlay settings log the tracebacks, which production doesn't (no `LOGGING` is configured, so with DEBUG off they go nowhere).
- **Why nightly.** Measured on 2026-11-05 on an 8-core Mac: the stack is ready in 20 to 45 seconds with a cached image. ZAP took 10 minutes when the seeded records were deleted early on, 14 minutes before it crashed in a browser-based rule (now ignored), and over 16 minutes (more than 21,000 requests) once DELETEs got their own records, at which point it was stopped. That is well past the 10 minutes a PR check should take. `scripts/dast.sh` caps the active scan at 20 minutes, any one rule at 4, and ZAP's start-up and passive scan at 10, so a run ends with a report rather than hanging.
- **Reports.** `build/dast/` gets `zap-report.html` (the one to read), `.json` and `.md`, the generated `openapi.json`, and the stack's logs. The nightly job uploads them as the `zap-report` artifact. The run also prints the API's responses by status: many 429s would mean a throttle got in the way, and any 5xx is worth reading in `stack.log`.

`DAST_KEEP_STACK=1 make dast` leaves the stack up afterwards; `DAST_ZAP_OPTIONS=-S make dast` runs only the passive rules, in about a minute.

### Triaging a finding

Fix it if you can. That means upgrading the dependency, rotating and removing the secret, or changing the code. If it really can't be exploited here, or is a false positive, record that next to the scan, with a reason specific enough that a reviewer can check it:

- **Dependency:** add an `[[IgnoredVulns]]` entry to `.osv-scanner.toml` with the id, a `reason`, and an `ignoreUntil` date no more than three months out. After that date it fails again and gets re-triaged. Delete the entry once the package is upgraded.
- **Secret:** if it's real, it's already public once pushed. Rotate it first, then add its fingerprint (gitleaks prints it) to `.gitleaksignore` with a comment saying when it was rotated. For a test fixture, add a narrow allowlist to `.gitleaks.toml` that matches only the fixture's path and exact value, so a real secret in the same file still fails.
- **ZAP alert:** add a line to `.zap/rules.tsv`: the plugin id, `IGNORE`, `INFO` or `WARN`, the rule name in brackets, and the reason, separated by tabs. To drop only some URLs, use `<id>`, `OUTOFSCOPE` and a URL regex. `FAIL` makes a low alert block too. Plugin ids are listed at [zaproxy.org/docs/alerts](https://www.zaproxy.org/docs/alerts/).

## Releases

`.github/workflows/release.yml` deploys only after CI passes on `main`:

- It runs when the CI Pipeline finishes on `main`. Its gate job continues only if that run succeeded and was a push.
- It deploys the commit CI tested, not whatever `main` points at by then. The web build checks out that commit, and the server fast-forwards to it.
- A manual run (`workflow_dispatch`) on `main` deploys `main` as it is, for when CI itself is broken. Use it sparingly.

Branch protection on `main` requires **CI Passed** (from GitHub Actions) as well as a code-owner review, so a PR can't merge with a failing job. That's a repository setting, not a file. A new CI job only blocks merges once it's listed in CI Passed's `needs`.
