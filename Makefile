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
