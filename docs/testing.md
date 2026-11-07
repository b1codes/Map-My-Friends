# Testing and CI

What runs on every pull request, what each check enforces, and how to run the same checks locally. Each suite has its own README for details: the [contract tests](../contracts/README.md), the [E2E journeys](../frontend/integration_test/README.md), and the [manual QA checklist](manual-qa.md) for the few things automation can't reach.

## On every pull request

`.github/workflows/ci.yml` runs these jobs in parallel. **CI Passed** succeeds only when all the others did, so it's the one check to require in branch protection.

| Job | What it checks | Fails when | Locally |
| --- | --- | --- | --- |
| Lint & Format Backend | Ruff format and lint on `backend/` | anything isn't formatted, or a rule fires | `make lint-backend` |
| Test Backend | the Django suite on the Firestore emulator, in random order, under coverage | a test fails, or branch coverage is below the gate | `make test-cov` |
| Lint, Format, & Test Frontend | dart format, `flutter analyze` (the app and the golden harness), the Flutter suite in random order under coverage, goldens included, then a release web build's download size | a test fails, a golden differs, the analyzer reports anything (infos too), line coverage is below the gate, or the web download is over [its budget](#web-download-size) | `make lint-frontend`, `make test-frontend-cov`, `make goldens`, `make web-size` |
| Lint, Format, & Test Widgetbook | the component catalog is regenerated, formatted and analyzed, every entry opens, every entry matches its light and dark golden, and every entry passes the [accessibility checks](#accessibility) | the committed catalog is stale, an entry throws, a golden differs, or an accessibility check finds a different number of problems than its known gaps record | `make goldens` for the goldens; see the job for the rest |
| E2E Journeys | the real app in headless Chrome against a throwaway full stack | a journey fails | `make e2e` |
| Lint Workflows | actionlint and shellcheck on every workflow | a workflow has an error | `make lint-workflows` |
| Validate Terraform Configuration | `terraform fmt` | anything isn't formatted | `terraform fmt -check -recursive infra` |

`make check` runs the linters and both coverage gates, which is everything above except the catalog, the goldens (off Linux x64) and the journeys. The backend half needs the dev stack (`make up`). Frontend targets use `fvm`; override with `make check FLUTTER=flutter DART=dart`.

The contract tests have no job of their own. They're part of the backend and frontend suites.

## Coverage gates

| Suite | Measures | Gate | Measured | Where the gate lives |
| --- | --- | --- | --- | --- |
| Backend | branch coverage of `apps/` and `config/` | 99% | 99.91% (2026-11-07) | `fail_under` in `backend/pyproject.toml` |
| Frontend | line coverage of `lib/` | 97% | 98.76% (2026-11-03) | `minimumLineCoverage` in `frontend/tool/check_coverage.dart` |

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

`.github/workflows/security.yml` runs the [security scans](#security-scans), and `.github/workflows/performance.yml` runs the [load test](#the-load-test). The load test also runs on a PR that changes it or its stack.

## Security scans

Three scanners look for what the test suites can't: vulnerable dependencies, leaked secrets, and holes a live attacker could find in the running API. The authorization and rate-limit rules themselves are tested in the backend suite.

| Scan | What it checks | Fails when | Where it runs | Locally |
| --- | --- | --- | --- | --- |
| Dependency Scan | every lockfile (`backend/poetry.lock` and each `pubspec.lock`) against the [OSV](https://osv.dev) database, with OSV-Scanner | any known vulnerability that `.osv-scanner.toml` doesn't ignore | every PR (ci.yml), and nightly (security.yml), since new advisories appear without code changes | `make scan-deps` |
| Secret Scan | gitleaks' rules plus a Django `SECRET_KEY` rule (`.gitleaks.toml`) over git commits | anything that looks like a credential, unless it is an allowlisted fixture | every PR, over the PR's commits; nightly over the whole history | `make scan-secrets` (whole history), or `make scan-secrets GITLEAKS_LOG_OPTS=origin/main..HEAD` |
| ZAP API Scan | OWASP ZAP's API scan (passive and active rules: injection, error disclosure, headers, and so on) against a throwaway stack running as production does | a medium or high alert that `.zap/rules.tsv` doesn't triage, or any 5xx from the API | nightly and on demand (security.yml, workflow_dispatch); too slow for every PR (see below) | `make dast` |
| DAST route check | the scan's API definition against the routes Django serves | a route is served that the scan doesn't know, or the other way round | every PR, in Test Backend | `make check-dast-routes` (needs `make up`) |

Every scanner image is pinned by digest: OSV-Scanner in `scripts/scan-deps.sh`, gitleaks in the `Makefile`, ZAP in `scripts/dast.sh`.

### Security tests in the suites

These run with the backend and frontend suites on every PR:

- `backend/tests/test_authz_matrix.py` runs every API route and method as an anonymous caller, the owner, and another user. Non-owners must not see the owner's data, and a refused write must leave Firestore unchanged. It fails when a route is added without a row in the matrix.
- `backend/tests/test_throttling.py` checks every rate limit at its exact boundary with a fake clock: per IP for anonymous callers, per user for signed-in ones, and whoever is calling on sign-up, password reset and login.
- `backend/tests/test_deploy_settings.py` loads `config/settings.py` under a production environment and runs `manage.py check --deploy` with it. The dev, test and E2E stacks all run with DEBUG on, so without it the production settings would never run under test.
- `backend/apps/common/tests/test_image_uploads.py` checks that only real PNG, JPEG and WebP images are stored. Each is re-encoded, which drops appended content and metadata, and saved under its real format.
- `frontend/test/security/third_party_token_test.dart` checks that no request to a host other than the API carries the app's tokens. It fails when a new network call site appears in `lib/`.

The E2E and DAST stacks raise the throttle rates (`docker/test-stack-settings/unthrottled_settings.py`), because their journeys and scans send far more requests from one address than a person would.

What a production deployment must set: `DJANGO_SECRET_KEY` (with DEBUG off, which is the default, the app refuses to start on the committed development key), `DJANGO_NUM_PROXIES=1` behind nginx (otherwise every client shares nginx's address for rate limiting), `ALLOWED_HOSTS`, `CORS_ALLOWED_ORIGINS`, `CSRF_TRUSTED_ORIGINS`, and `SECURE_SSL_REDIRECT=True` once nginx serves HTTPS. `backend/.env.example` lists them.

### The dependency scan

The lockfiles come from the manifests git tracks, so a new package is scanned without any change here, and a missing lockfile fails rather than being skipped. Every lockfile is committed, so the scan checks exactly the versions CI and the release build install.

### The ZAP scan

`scripts/dast.sh` documents each step. In short:

- **The stack.** `docker-compose.e2e.yml` (API, Firestore emulator, third-party stubs) with `docker-compose.dast.yml` on top, which runs the API under gunicorn with DEBUG off, a random `DJANGO_SECRET_KEY`, collected static files and the code baked into the image. Scanning a DEBUG server would report DEBUG's behaviour instead of production's. The one difference from production is that `docker/test-stack-settings/unthrottled_settings.py` (shared with the E2E stack) raises the throttle rates: the scan sends thousands of requests as one user, and at the real rates most would get 429. It runs as project `map-my-friends-dast` on port 8200, beside the dev and E2E stacks.
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

## Performance

Production is one or more Cloud Run instances (one vCPU, 512 MiB each, scaling to zero) in front of Firestore in the same region. A request's cost is mostly its Firestore round trips, which run one after another and each bill at least one document read, plus the CPU it holds on the instance. The checks follow from that:

| Check | What it checks | Fails when | Where it runs | Locally |
| --- | --- | --- | --- | --- |
| Round-trip budgets | every API route the owner can call, sent with a small account and a large one, counting every Firestore RPC | a route's count differs from its budget at either size | every PR, in Test Backend | `make test-cov` |
| Production indexes | every query those requests send, against `firestore.indexes.json` | a query would need an index that isn't declared | every PR, in Test Backend | `make test-cov` |
| Large accounts | the people list and grid, Pulse, My Trips and the map with 500 people (and 2,000 logs, or 300 trips) | a list builds more than a screenful, or the map stops clustering | every PR, in the frontend suite | `make test-frontend-cov` |
| App requests | what the real app asks the API for when it opens and on each tab | a request is repeated or new | every PR, in E2E Journeys | `make e2e` |
| Web download size | a release web build's gzipped app and assets | over its budget | every PR, in the frontend job | `make web-size` |
| Load test | one Cloud Run-sized instance under a steady mix of what the app sends, plus its cold start and memory | any failed request, a dropped iteration, a p95 over budget, a 5xx, a slow cold start, or too much memory | nightly, and on PRs that change it | `make load` |

### Round-trip budgets

`backend/tests/test_round_trip_budgets.py` counts the RPCs the Firestore client sends (`count_firestore_rpcs` in `apps/common/testing.py`) for one request per case. Each case runs twice: once with one of everything, and once with 8 people (3 logs each), 6 trips (4 stops each) and a request body carrying as many stops. The count must equal the case's budget both times. Budgets are exact, like `assertNumQueries`, so a saving fails too and the budget gets lowered to keep it. The completeness test fails when the authorization matrix lets the owner call a route and method that has no budget.

Every route is flat today: 1 round trip for the people, contact-log and leg lists, 4 for the trip list, 2 to save a trip. A route that has to grow can be recorded as a known gap (`known_gap=(small, large)` plus the task tracking it), which fails if it gets worse and if it's fixed.

What keeps them flat (see the docstrings in `apps/people/repositories.py` and `apps/trips/repositories.py`):

- Each person stores their last contact, kept in step by every contact-log write, in a transaction. The people list doesn't query the logs.
- Contact logs, stops and legs store their owner (logs and legs their own id too), so one collection-group query finds all of an owner's, or one of them.
- A trip's writes go in one commit, and the result is built in memory instead of read back.
- Contended transactions retry in rounds with a random wait between them (`fs.run_transaction`).

### Production indexes

The emulator answers any query, indexed or not. Production refuses one that needs an index nobody declared (FAILED_PRECONDITION, a 500). `backend/tests/test_firestore_indexes.py` records the query of every request in the budget table and checks it: one collection with equality filters or one order needs nothing; a collection-group query needs a `fieldOverrides` entry per field; equality plus an order, or two orders, need a composite index.

**Deploying.** Indexes deploy separately from the code: `firebase deploy --only firestore:indexes`. Deploy them first, and wait until the console shows them built, before the code that queries them serves traffic. An override that adds `COLLECTION_GROUP` also has to keep the field's `COLLECTION` indexes, because an override replaces the defaults. The checker tests for that too.

Data written before 2026-11-07 lacks the copied owner fields and stored last contact, and the new queries don't see it. Production had no real data then. Locally, `docker compose restart firestore` empties the dev emulator (it keeps data in memory only), and `make seed` refills it.

### App requests

The E2E stack's API logs every request it answers, by user (`docker/test-stack-settings/request_log.py`, loaded only there). `frontend/integration_test/journeys/requests_test.dart` opens the real app and checks that it asks for the profile, people and trips once each. A second journey, moving between tabs, is skipped as a known gap: every Pulse visit refetches people and every Me visit the profile ([ClickUp](https://app.clickup.com/t/86bd054ar)).

### Web download size

`frontend/tool/check_web_size.dart` reads a release web build and checks gzipped sizes against the budgets at its top: `main.dart.js` (1,745 KiB on 2026-11-07, budget 1,900), each bundled asset (largest 149 KiB, budget 200), and both together (2,351 KiB, budget 2,600). Assets load when first used, so the total is the most a visit downloads. CanvasKit comes from Google's CDN and isn't counted. A failing run names the file. Shrink it, or load it on demand, before raising a budget. This check is how the 2.5 MB logo was found.

### The load test

`scripts/load.sh` documents each step. In short:

- **The stack.** `docker-compose.e2e.yml` with `docker-compose.perf.yml` on top: the API as one Cloud Run instance (DEBUG off, gunicorn with 1 worker and 8 threads, 1 vCPU, 512 MiB), with Toxiproxy adding 3 ms each way to every Firestore round trip (`PERF_FIRESTORE_LATENCY_MS`). It runs as project `map-my-friends-perf` on port 8300.
- **The load.** `perf/load.js` (k6, pinned by digest) seeds 20 accounts through the API (25 people, 50 logs and 4 trips each), then runs five scenarios side by side for 3 minutes at fixed rates, about 26 requests/s: opening the app, browsing, logging contact, planning a trip, and signing in. `PERF_RATE_SCALE` multiplies the rates.
- **Pass or fail.** Any failed request or check, any dropped iteration (the instance couldn't keep up), a scenario's p95 over its budget (in `perf/load.js`), any 5xx in the API's log, more than 20 s from restart to the first answer, a first hub lookup over 1.5 s, or peak memory over 400 MiB.
- **Measured on 2026-11-07.** p95 was 40 to 60 ms locally and 46 to 83 ms on CI for everything but sign-in, against budgets of 150 to 250 ms. Sign-in was about 300 ms locally and 480 ms on CI, against 1,000: the password hash holds the one vCPU, and every request on the instance waits behind it. Peak memory was about 200 MiB, and the API answered about 5 s after a restart. At 4× the rate (about 100 requests/s) the instance still met every budget. At 10× (about 260/s offered) requests queued for 5 to 8 s, so one instance tops out between the two.
- **When it fails.** Read the scenario table in `build/perf/summary.md` (on CI, the run's page and the `load-test` artifact) and `api.log`. A slower scenario usually has a route whose round trips grew, which the budgets should have caught first, or new CPU work in a request. The TimezoneFinder that was built on every person save (about 300 ms) showed up this way. Raise a budget only with a measured reason.

`PERF_DURATION=1m make load` gives a quick run, and `PERF_KEEP_STACK=1` leaves the stack up.

## Releases

`.github/workflows/release.yml` deploys only after CI passes on `main`:

- It runs when the CI Pipeline finishes on `main`. Its gate job continues only if that run succeeded and was a push.
- It deploys the commit CI tested, not whatever `main` points at by then. The web build checks out that commit, and the server fast-forwards to it.
- A manual run (`workflow_dispatch`) on `main` deploys `main` as it is, for when CI itself is broken. Use it sparingly.

Branch protection on `main` requires **CI Passed** (from GitHub Actions) as well as a code-owner review, so a PR can't merge with a failing job. That's a repository setting, not a file. A new CI job only blocks merges once it's listed in CI Passed's `needs`.
