#!/usr/bin/env bash
# Runs the post-deploy smoke test (smoke/smoke.py) against the production
# image on a throwaway stack: `make smoke`, and the Smoke Test job in CI.
#
# The stack is the DAST one (docker-compose.e2e.yml + docker-compose.dast.yml):
# the production image with DEBUG off, the Firestore emulator, and stubs for
# the third-party services. That's what a release deploys, short of Google's
# own Firestore. The release runs the same smoke.py against the real thing.
#
# Environment:
#   SMOKE_PROJECT      compose project name   (default map-my-friends-smoke)
#   SMOKE_API_PORT     host port for the API  (default 8250)
#   SMOKE_KEEP_STACK   1 = leave the stack running afterwards
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${SMOKE_PROJECT:-map-my-friends-smoke}"
export DAST_API_PORT="${SMOKE_API_PORT:-8250}"
BASE_URL="http://localhost:${DAST_API_PORT}"
OUT="$ROOT/build/smoke"

# Production refuses the default SECRET_KEY, so the stack gets a random one.
DAST_SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')"
export DAST_SECRET_KEY

compose() {
  docker compose -p "$PROJECT" -f "$ROOT/docker-compose.e2e.yml" -f "$ROOT/docker-compose.dast.yml" "$@"
}

# shellcheck disable=SC2329 # run by the EXIT trap below
cleanup() {
  local status=$?
  compose logs --no-color api firestore stubs >"$OUT/stack.log" 2>&1 || true
  if [[ "${SMOKE_KEEP_STACK:-}" != "1" ]]; then
    compose down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  if [[ "$status" != 0 ]]; then
    echo "The stack's logs are in build/smoke/stack.log." >&2
  fi
  exit "$status"
}
trap cleanup EXIT

rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Starting the production image on a fresh stack ($PROJECT: API :$DAST_API_PORT)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --build --quiet-pull

# /health answers as soon as gunicorn does; the emulator can take longer, and
# the public people list is the cheapest request that touches Firestore.
for _ in $(seq 1 90); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/health" || true)" == 200 ]] && break
  sleep 2
done
for _ in $(seq 1 60); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/people/" || true)" == 200 ]] && break
  sleep 2
done

echo "==> Smoke test"
SMOKE_BASE_URL="$BASE_URL" SMOKE_WEB_ORIGIN=http://localhost:3000 \
  python3 "$ROOT/smoke/smoke.py"
