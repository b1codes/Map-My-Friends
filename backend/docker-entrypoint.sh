#!/bin/sh
# The production image's entrypoint (see Dockerfile).
#
# Django's own tables live in SQLite on the instance's disk, which starts empty
# on every new instance. The image carries a database already migrated at
# build time, from this image's own migrations, so a cold start copies it
# instead of spending ~2 s starting Django to run migrate.
set -eu

if [ ! -e "$DJANGO_SQLITE_PATH" ]; then
    cp /app/django-template.sqlite3 "$DJANGO_SQLITE_PATH"
fi

exec "$@"
