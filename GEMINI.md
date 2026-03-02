# Gemini Context: Map My Friends

This project is a geospatial "Friends Tracking" application consisting of a **GeoDjango** backend and a **Flutter** mobile/web frontend.

## 🚀 Project Overview
- **Backend:** Django 6.0 + Django REST Framework (DRF) + PostGIS. It serves a REST API with GeoJSON support for location data.
- **Frontend:** Flutter application using the BLoC pattern for state management and `flutter_map` for OpenStreetMap visualization.
- **Infrastructure:** Fully containerized backend using Docker Compose, with a PostgreSQL/PostGIS database.
- **Key Features:** Automatic geocoding of addresses (via Geopy/Nominatim), JWT-based authentication, and interactive map visualization.

## 🛠 Building and Running

### Backend (Docker-based)
Most backend operations are orchestrated via the root `Makefile`.
- **Start Services:** `make up` (Starts Django and PostGIS)
- **Build/Rebuild:** `make build`
- **Migrations:** `make mig` (Runs `makemigrations` and `migrate` inside the container)
- **Create Superuser:** `make user`
- **Run Tests:** `make test`
- **Shell Access:** `make shell` (Django shell) or `make db` (Postgres shell)
- **Dependency Management:** Handled by **Poetry** inside the container. Use `make install`, `make add`, or `make update`.

### Frontend (Flutter)
- **Install Dependencies:** `cd frontend && flutter pub get`
- **Run App:** `flutter run` (Ensure a simulator or device is connected)
- **Build Web:** `flutter build web`

## 📂 Development Conventions

### Backend (Django)
- **App Structure:** Located in `backend/apps/`. Currently contains `people` (contacts/locations) and `users` (auth/profiles).
- **Geospatial Logic:** Uses `django.contrib.gis`. The `Person` model automatically geocodes street addresses to `PointField` coordinates on `save()`.
- **API Style:** Uses DRF with `rest_framework_gis` for GeoJSON serialization. Interceptors in the frontend handle JWT rotation automatically.
- **Configuration:** Main settings are in `backend/config/settings.py`. Uses `dj-database-url` for environment-based DB config.

### Frontend (Flutter)
- **State Management:** Strict adherence to the **BLoC** pattern (`frontend/lib/bloc/`).
- **Networking:** Uses **Dio** with interceptors for auth token management (`frontend/lib/services/api_service.dart`).
- **Theming:** Centralized theme configuration in `frontend/lib/utils/app_theme.dart`. Supports Light/Dark modes via `ThemeCubit`.
- **UI Architecture:** Screens are in `frontend/lib/screens/`, reusable components in `frontend/lib/components/`.

### General
- **Environment Variables:** Managed via Docker Compose for the backend.
- **Database:** PostGIS is required. The `db` service in `docker-compose.yml` provides this.
- **Testing:** Backend tests are located in `backend/tests/`. Always run `make test` before submitting changes.
