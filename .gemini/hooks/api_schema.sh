#!/bin/bash
# .gemini/hooks/api_schema.sh
SCHEMA=$(grep -r "path(" backend/apps/*/urls.py 2>/dev/null | awk -F: '{print $1 ": " $2}' | sed 's/"/\\"/g' | tr '\n' ' ')
echo "{\"api_schema\": \"$SCHEMA\"}"
