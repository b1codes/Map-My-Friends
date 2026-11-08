# Two images from one file:
#
#   dev         the development, test and E2E stacks (docker-compose.yml,
#               docker-compose.e2e.yml). Dev extras, gettext, Poetry, and
#               runserver; the code is usually bind-mounted over /app.
#   production  what Cloud Run runs (and the DAST and load-test stacks, so
#               they test the real thing). Only the app's own dependencies,
#               no compilers or Poetry, a non-root user, gunicorn on $PORT.
#
# Build one with --target; compose files name theirs. The production image's
# checks are in .github/workflows/production-image.yml (`make prod-image`).

# 3.14-slim; the digest is the multi-arch index, so the same pin builds on x64
# CI and Apple Silicon.
FROM python:3.14-slim@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# Debian's security fixes since the base image was last published. The Trivy
# scan in CI fails on a fixable HIGH or CRITICAL CVE, and the base image can
# lag Debian by weeks (zlib1g did, in November 2026).
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app


# -----------------------------------------------------------------------------
# Tooling shared by dev and the production build: compilers (Python 3.14 still
# has to build a few wheels from source), gettext for the translations, and
# Poetry 2 (it reads the [project] table), pinned to the version that wrote
# poetry.lock.
# -----------------------------------------------------------------------------
FROM base AS tooling

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3-dev \
    gettext \
    && rm -rf /var/lib/apt/lists/*

RUN pip install "poetry==2.5.1"


# -----------------------------------------------------------------------------
# dev
# -----------------------------------------------------------------------------
FROM tooling AS dev

# The dependency files first, so a code change doesn't reinstall everything.
COPY pyproject.toml poetry.lock /app/

# No virtualenv: the container is the environment.
RUN poetry config virtualenvs.create false \
    && poetry install --no-interaction --no-ansi --extras dev

COPY . /app/

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]


# -----------------------------------------------------------------------------
# The production build: the app's dependencies into /venv, the translations
# compiled, the static files collected, and Django's own tables migrated into a
# template database. Nothing from this stage but its outputs ships.
# -----------------------------------------------------------------------------
FROM tooling AS build

ENV VIRTUAL_ENV=/venv \
    PATH=/venv/bin:$PATH

COPY pyproject.toml poetry.lock /app/

# Poetry installs into the active virtualenv, which has no pip of its own: the
# app never installs anything at runtime. Without the dev extras (debugpy,
# coverage, jsonschema), which are an optional group, not --only main.
RUN python -m venv --without-pip /venv \
    && poetry install --no-interaction --no-ansi

COPY . /app/

# Settings refuse the public development key with DEBUG off. This key exists
# only for these commands, none of which signs anything, and isn't kept.
RUN export DJANGO_SECRET_KEY=build-only-not-a-secret \
    && python manage.py compilemessages --ignore=/venv \
    && python manage.py collectstatic --noinput \
    && DJANGO_SQLITE_PATH=/app/django-template.sqlite3 python manage.py migrate --noinput


# -----------------------------------------------------------------------------
# production
# -----------------------------------------------------------------------------
FROM base AS production

# The base image's pip is unused at runtime (the app runs from /venv), and is
# where image scanners find fixable CVEs. The app runs as its own user.
RUN pip uninstall --yes pip \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid 10001 --no-create-home \
       --shell /usr/sbin/nologin app

COPY --from=build /venv /venv
# The code, compiled translations, collected static files and the template
# database, owned by root: the app can read its code but not change it.
COPY --from=build /app /app

ENV PATH=/venv/bin:$PATH \
    # Cloud Run sets PORT; 8080 is its default.
    PORT=8080 \
    # Django's own tables (users, the refresh-token blacklist) in SQLite, on
    # the instance's writable in-memory disk. They don't survive the
    # instance: see the warning in docs/deploy.md.
    DJANGO_SQLITE_PATH=/tmp/django.sqlite3

USER 10001:10001

EXPOSE 8080

# docker-entrypoint.sh starts the SQLite database from the template, then
# runs the command. gunicorn reads gunicorn.conf.py from /app.
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["gunicorn", "config.wsgi:application"]
