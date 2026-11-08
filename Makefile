# Makefile
up:
	docker compose up

# Debug mode: starts the stack with debugpy on port 5678 for VS Code attach.
# Use "Django: Attach (Docker)" in VS Code after running this.
debug:
	docker compose -f docker-compose.yml -f docker-compose.debug.yml up --build

build:
	docker compose build

down:
	docker compose down

# Only Django's own apps (auth/admin/sessions/contenttypes) have migrations
# now; application data lives in Firestore. makemigrations is intentionally
# not run here.
mig:
	docker compose exec api python manage.py migrate

seed:
	docker compose exec api python manage.py seed

fetch-data:
	docker compose exec api python manage.py fetch_airports
	docker compose exec api python manage.py fetch_stations

user:
	docker compose exec api python manage.py createsuperuser

shell:
	docker compose exec api python manage.py shell

emulator:
	docker compose up firestore

ui:
	@echo "Emulator UI: http://localhost:4000"

test:
	docker compose exec api python manage.py test 2>&1 | tee .gemini/last_test_results.txt

# Backend tests under coverage, in random order like CI. Scope, exclusions and
# the gate (fail_under) live in backend/pyproject.toml ([tool.coverage.*]);
# html lands in backend/htmlcov/. Fails below the gate, as CI does.
test-cov:
	docker compose exec api coverage run manage.py test --shuffle
	-docker compose exec api coverage html
	docker compose exec api coverage report

# Frontend tests under coverage, in random order like CI, then the coverage
# gate (frontend/tool/check_coverage.dart). The goldens skip themselves
# anywhere but Linux x64; `make goldens` runs them.
FLUTTER ?= fvm flutter
DART ?= fvm dart
test-frontend-cov:
	cd frontend && $(FLUTTER) test --coverage --test-randomize-ordering-seed random
	cd frontend && $(DART) run tool/check_coverage.dart

# The web download budget, the same as CI: a release web build, then
# frontend/tool/check_web_size.dart against it.
web-size:
	cd frontend && $(FLUTTER) build web --release
	cd frontend && $(DART) run tool/check_web_size.dart build/web

.PHONY: web-size

# Static analysis, the same as CI. Ruff's version is read from
# `required-version` in backend/pyproject.toml; actionlint is pinned by digest
# here, and CI runs this target.
RUFF_VERSION := $(shell sed -n 's/^required-version = "==\(.*\)"/\1/p' backend/pyproject.toml)
ACTIONLINT_IMAGE := rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667

lint: lint-backend lint-frontend lint-workflows

lint-backend:
	uvx ruff@$(RUFF_VERSION) format --check backend/ smoke/
	uvx ruff@$(RUFF_VERSION) check backend/ smoke/

lint-frontend:
	cd frontend && $(DART) format --set-exit-if-changed .
	cd frontend && $(FLUTTER) analyze
	cd frontend/golden_harness && $(FLUTTER) pub get >/dev/null && $(FLUTTER) analyze

lint-workflows:
	docker run --rm -v "$(CURDIR):/repo" -w /repo $(ACTIONLINT_IMAGE) -color

# Everything the per-PR CI gates check except the Widgetbook catalog and the
# E2E journeys (`make e2e`). Needs the dev stack up (`make up`) for the
# backend tests.
check: lint test-cov test-frontend-cov

.PHONY: test-cov test-frontend-cov lint lint-backend lint-frontend lint-workflows check

# Golden tests, the app's and the Widgetbook catalog's, on Linux x64: the
# platform they are recorded on, and the one CI runs. Natively on Linux x64,
# in the pinned Flutter image (linux/amd64) anywhere else; see
# scripts/goldens.sh. update-goldens re-records them; review the images
# before committing.
goldens:
	scripts/goldens.sh

update-goldens:
	scripts/goldens.sh --update

.PHONY: goldens update-goldens

# E2E journeys (frontend/integration_test) in headless Chrome against a fresh
# throwaway stack (docker-compose.e2e.yml), separate from the one `make up`
# runs. One journey file: `make e2e JOURNEY=integration_test/journeys/auth_test.dart`.
e2e:
	scripts/e2e.sh $(JOURNEY)

# Security scans; docs/testing.md (Security scans) covers triage. CI runs
# these same targets.
#
# scan-deps: every lockfile against the OSV database (scripts/scan-deps.sh).
scan-deps:
	scripts/scan-deps.sh

# scan-secrets: gitleaks over the git history, with .gitleaks.toml. The whole
# history by default; one range with e.g.
# `make scan-secrets GITLEAKS_LOG_OPTS=origin/main..HEAD`. The GIT_CONFIG_*
# variables mark the mounted checkout as safe, since its owner isn't the
# container's user on Linux.
GITLEAKS_IMAGE := ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f
GITLEAKS_LOG_OPTS ?=
scan-secrets:
	docker run --rm -v "$(CURDIR):/repo:ro" \
		-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=/repo \
		$(GITLEAKS_IMAGE) git /repo --config /repo/.gitleaks.toml --redact --no-banner \
		$(if $(GITLEAKS_LOG_OPTS),--log-opts="$(GITLEAKS_LOG_OPTS)")

# dast: the OWASP ZAP API scan against a throwaway production-like stack
# (docker-compose.dast.yml), separate from the one `make up` runs. Reports go
# to build/dast/. See scripts/dast.sh.
dast:
	scripts/dast.sh

# The route check from `make dast` on its own: fails when the API serves a
# route the scan's OpenAPI document doesn't describe, or the other way round.
# Needs the dev stack up (`make up`).
check-dast-routes:
	@mkdir -p build/dast
	docker compose exec -T api python - < scripts/list_api_routes.py > build/dast/routes.json
	python3 scripts/dast_openapi.py --check-routes build/dast/routes.json

.PHONY: scan-deps scan-secrets dast check-dast-routes

# The production image (backend/Dockerfile's production target), built and
# checked the way Cloud Run will run it: hadolint, a read-only boot on $PORT
# at 1 vCPU / 512 MiB, what clients and probes see, SIGTERM, the SECRET_KEY
# guard, and a Trivy scan. See scripts/prod-image.sh.
prod-image:
	scripts/prod-image.sh

.PHONY: prod-image

# firestore.rules against the Firestore emulator: every kind of direct client
# access must be refused (docker/firebase-emulator/rules-test). About a
# minute, most of it building the emulator image the first time.
test-rules:
	scripts/test-rules.sh

.PHONY: test-rules

# infra/ (the GCP Terraform): fmt, validate, terraform test with the
# providers mocked, tflint and trivy config. No GCP credentials needed. See
# scripts/infra.sh.
check-infra:
	scripts/infra.sh

.PHONY: check-infra

# The post-deploy smoke test (smoke/smoke.py), its own tests, then the test
# itself against the production image on a throwaway stack. The release runs
# smoke.py against each new revision before it takes traffic; smoke.yml runs
# it hourly against production.
smoke:
	python3 -m unittest discover -s smoke
	scripts/smoke.sh

.PHONY: smoke

# Load test: perf/load.js in k6 against a throwaway stack shaped like one
# Cloud Run instance (docker-compose.perf.yml), with Firestore latency
# added. About 6 minutes; results in build/perf/. scripts/load.sh lists the
# settings, e.g. PERF_DURATION=1m make load. CI runs it nightly.
load:
	scripts/load.sh

.PHONY: load

# Poetry helpers
install:
	docker compose exec api poetry install

add:
	@read -p "Package name: " package; \
	docker compose exec api poetry add $$package

update:
	docker compose exec api poetry update

# Component catalog (frontend/widgetbook). Regenerates the navigation tree
# first, so a newly annotated use case appears without a separate step.
# Runs in Chrome by default; override with e.g. `make widgetbook DEVICE=macos`.
DEVICE ?= chrome
widgetbook:
	cd frontend/widgetbook && flutter pub get && dart run build_runner build && flutter run -d $(DEVICE)
