#!/bin/bash
# .gemini/hooks/db_schema.sh
# Only run if docker compose is up
if docker compose ps api --format "{{.State}}" | grep -q "running"; then
  SCHEMA=$(docker compose exec -T api poetry run python manage.py inspectdb 2>/dev/null | grep -E "^class |    location =" | sed 's/"/"/g' | tr '
' ' ')
  echo "{"db_schema": "$SCHEMA"}"
else
  echo "{"db_schema": "Database service not running."}"
fi
