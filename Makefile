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
# gate (frontend/tool/check_coverage.dart).
FLUTTER ?= fvm flutter
DART ?= fvm dart
test-frontend-cov:
	cd frontend && $(FLUTTER) test --exclude-tags golden --coverage --test-randomize-ordering-seed random
	cd frontend && $(DART) run tool/check_coverage.dart

# Static analysis, the same as CI. Ruff's version is read from
# `required-version` in backend/pyproject.toml; actionlint is pinned by digest
# here, and CI runs this target.
RUFF_VERSION := $(shell sed -n 's/^required-version = "==\(.*\)"/\1/p' backend/pyproject.toml)
ACTIONLINT_IMAGE := rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667

lint: lint-backend lint-frontend lint-workflows

lint-backend:
	uvx ruff@$(RUFF_VERSION) format --check backend/
	uvx ruff@$(RUFF_VERSION) check backend/

lint-frontend:
	cd frontend && $(DART) format --set-exit-if-changed .
	cd frontend && $(FLUTTER) analyze

lint-workflows:
	docker run --rm -v "$(CURDIR):/repo" -w /repo $(ACTIONLINT_IMAGE) -color

# Everything the per-PR CI gates check except the Widgetbook catalog and the
# E2E journeys (`make e2e`). Needs the dev stack up (`make up`) for the
# backend tests.
check: lint test-cov test-frontend-cov

.PHONY: test-cov test-frontend-cov lint lint-backend lint-frontend lint-workflows check

# E2E journeys (frontend/integration_test) in headless Chrome against a fresh
# throwaway stack (docker-compose.e2e.yml), separate from the one `make up`
# runs. One journey file: `make e2e JOURNEY=integration_test/journeys/auth_test.dart`.
e2e:
	scripts/e2e.sh $(JOURNEY)

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
