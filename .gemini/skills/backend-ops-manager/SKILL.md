---
name: backend-ops-manager
description: Operational guidance for the Django backend, including Docker, Poetry, and Makefile workflows. Use when managing migrations, dependencies, or infrastructure.
---

# Backend Ops Manager

This skill manages the project's containerized infrastructure and backend maintenance.

## Key Operations

### Makefile Workflows
- `make up`: Start the Django and PostGIS services.
- `make build`: Rebuild the backend container.
- `make mig`: Generate and apply Django migrations.
- `make user`: Create a Django superuser.
- `make test`: Run the backend test suite inside the container.
- `make shell`: Access the Django shell.
- `make db`: Access the PostgreSQL shell.

### Dependency Management
- Use **Poetry** inside the container.
- `make install`: Install all dependencies.
- `make add package=<name>`: Add a new dependency.
- `make update`: Update existing dependencies.

### Database (PostGIS)
- The database is PostgreSQL with the PostGIS extension.
- Always use the `db` service defined in `docker-compose.yml`.
- Ensure spatial extensions are enabled (`CREATE EXTENSION postgis;`).

## Common Workflows

### Creating a New Model
1. Define the model in `backend/apps/*/models.py`.
2. Run `make mig` to create and apply the migration.

### Debugging with Shell
1. Run `make shell`.
2. Import the model and test logic.
3. Exit when finished.

### Environment Variables
- Managed via `docker-compose.yml` and `.env` (if present).
- Never hardcode sensitive credentials.
