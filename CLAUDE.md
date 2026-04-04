# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Map My Friends is a geospatial social app: a **GeoDjango** backend serving a REST API with GeoJSON support, and a **Flutter** mobile/web frontend using OpenStreetMap. The backend runs inside Docker; you do not need Python, GDAL, or PostGIS installed locally.

## Commands

### Backend (Docker-based, all commands from repo root)

```bash
make up          # Start Django + PostGIS containers
make down        # Stop containers
make build       # Rebuild images
make mig         # makemigrations + migrate inside container
make test        # Run backend tests (output tee'd to .gemini/last_test_results.txt)
make user        # Create Django superuser
make airports    # Import airport data
make stations    # Import train station data (prompts for JSON file path)
make shell       # Django shell
make db          # PostgreSQL shell (mapuser / mapfriends_db)
make add         # Add a Poetry package (prompts for name)
```

Run arbitrary management commands inside the container:
```bash
docker compose exec api poetry run python manage.py <command>
```

### Frontend (Flutter)

```bash
cd frontend
flutter pub get
flutter run                  # requires simulator/device
flutter test                 # run all widget/unit tests
flutter test test/path/to_test.dart   # run a single test file
flutter build web
```

## Architecture

### Backend (`backend/`)

- **Settings & URLs:** `backend/config/settings.py` and `backend/config/urls.py`
- **Apps:** `backend/apps/` — `people/`, `users/`, `airports/`, `stations/`
- **Geospatial:** Uses `django.contrib.gis` (GeoDjango). The `Person` model auto-geocodes street addresses to a `PointField` on `save()` using Geopy/Nominatim and auto-detects timezone via TimezoneFinder.
- **Serializers:** People endpoint returns GeoJSON `FeatureCollection` via `GeoFeatureModelSerializer` from `rest_framework_gis`.
- **Auth:** SimpleJWT — 60-min access tokens, 7-day refresh tokens with rotation + blacklist.
- **Throttling:** Custom `BurstAnonRateThrottle` and `SustainedAnonRateThrottle` on registration/password-reset endpoints.
- **Database:** PostgreSQL 16 + PostGIS 3.4 via `dj-database-url` with `postgis://` scheme.

### Frontend (`frontend/lib/`)

- **Entry point:** `main.dart`
- **State management:** Strict BLoC pattern. All blocs/cubits live in `lib/bloc/`, organized by feature: `auth/`, `people/`, `location/`, `airport/`, `station/`, `profile/`, `theme/` (ThemeCubit), `map/` (MapSettingsCubit).
- **Networking:** Dio singleton in `lib/services/api_service.dart` with interceptors for JWT injection and automatic token refresh on 401.
- **API base URL:** Configured in `lib/services/api_config.dart` — branches on `kIsWeb` and platform for localhost vs. emulator vs. production URLs.
- **Theming:** Centralized in `lib/utils/app_theme.dart`. Light/Dark mode driven by `ThemeCubit`.
- **UI structure:** `lib/screens/` for full screens, `lib/components/` for reusable widgets.
- **Models:** `lib/models/` — support both plain JSON and GeoJSON parsing.

### API Endpoints

| Prefix | App |
|---|---|
| `/api/user/` | Authentication & user profiles |
| `/api/people/` | Contact CRUD + GeoJSON |
| `/api/airports/` | Nearest airports query |
| `/api/stations/` | Train station data |

Django Admin: `http://localhost:8000/admin`

### Infrastructure

- Development: `docker-compose.yml` (Django `runserver`)
- Production: `docker-compose.prod.yml` (Gunicorn, 3 workers, WhiteNoise for static files)
- IaC: `infra/` (Terraform, AWS)
- Deployment script: `deploy.sh`
