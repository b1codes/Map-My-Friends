#!/usr/bin/env bash
# Checks the production image (backend/Dockerfile's production target) the way
# Cloud Run will run it: `make prod-image`, the Production Image job in CI, and
# the release, which runs it on the exact image it's about to push.
#
#   1. Lint the Dockerfile (hadolint).
#   2. Start the image as Cloud Run would: configured only through env, on
#      $PORT, 1 vCPU and 512 MiB. The root filesystem is read-only apart from
#      /tmp, so anything that writes elsewhere fails here and not in
#      production (Cloud Run's disk is in memory and counts against the limit).
#   3. Check what a client and Cloud Run's probes see: /health, the host
#      check, the HTTPS redirect, DEBUG off, CORS, HSTS, static files.
#   4. Check it stops cleanly on SIGTERM within Cloud Run's 10 s, and that it
#      refuses to start without its own SECRET_KEY.
#   5. Check the image carries no build or dev tooling, and runs as non-root.
#   6. Scan it with Trivy: a HIGH or CRITICAL CVE with a fix available, or a
#      secret baked into a layer, fails.
#
# No Firestore is needed: nothing checked here reads it.
#
# Environment:
#   PROD_IMAGE             image to check     (default map-my-friends-backend:prod)
#   PROD_IMAGE_SKIP_BUILD  1 = don't build it first (the release builds its own)
#   PROD_IMAGE_PORT        host port          (default 8400)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${PROD_IMAGE:-map-my-friends-backend:prod}"
HOST_PORT="${PROD_IMAGE_PORT:-8400}"
NAME="mmf-prod-image-check-$$"
BASE="http://127.0.0.1:$HOST_PORT"

# shellcheck source=scripts/tool-images.sh
source "$ROOT/scripts/tool-images.sh"

API_HOST=api.example.test
APP_ORIGIN=https://app.example.test

failures=0
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1" >&2; failures=$((failures + 1)); }
check() { # check <description> <command...>
  local what="$1"; shift
  if "$@"; then pass "$what"; else fail "$what"; fi
}

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== Dockerfile lint (hadolint)"
check "backend/Dockerfile passes hadolint" \
  docker run --rm -i "$HADOLINT_IMAGE" hadolint - <"$ROOT/backend/Dockerfile"

if [ "${PROD_IMAGE_SKIP_BUILD:-0}" != 1 ]; then
  echo "== Building $IMAGE"
  docker build --quiet --target production -t "$IMAGE" "$ROOT/backend" >/dev/null
fi

# A Cloud Run revision's settings, as infra/cloud_run.tf sets them.
run_image() { # run_image <extra docker args...>
  docker run -d --name "$NAME" \
    --read-only --tmpfs /tmp:rw,mode=1777 \
    --cpus 1 --memory 512m \
    -p "127.0.0.1:$HOST_PORT:8080" \
    -e PORT=8080 \
    -e DJANGO_DEBUG=False \
    -e ALLOWED_HOSTS="$API_HOST" \
    -e CORS_ALLOWED_ORIGINS="$APP_ORIGIN" \
    -e CSRF_TRUSTED_ORIGINS="$APP_ORIGIN" \
    -e SECURE_SSL_REDIRECT=True \
    -e DJANGO_NUM_PROXIES=1 \
    -e FIRESTORE_PROJECT_ID=mmf-prod-image-check \
    "$@" "$IMAGE" >/dev/null
}

# curl's status code (and headers, with -D) for a request to the container.
status() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@"; }
# A failed request yields no headers, which the checks then report, rather
# than stopping the script.
headers() { { curl -s -o /dev/null -D - --max-time 5 "$@" || true; } | tr -d '\r'; }
# A request as Cloud Run's front end forwards it: the service's host, HTTPS.
as_client() { curl -s --max-time 5 -H "Host: $API_HOST" -H "X-Forwarded-Proto: https" "$@"; }

echo "== Starting the image as Cloud Run would"
run_image -e DJANGO_SECRET_KEY="$(openssl rand -hex 32)"
started=$(date +%s)
ready=""
for _ in $(seq 1 60); do
  if [ "$(status "$BASE/health")" = 200 ]; then ready=1; break; fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" != true ]; then break; fi
  sleep 0.5
done
if [ -z "$ready" ]; then
  fail "the image serves /health within 30 s"
  docker logs "$NAME" >&2 || true
  exit 1
fi
pass "the image serves /health, $(( $(date +%s) - started )) s after starting"

echo "== What clients and probes see"
check "/health answers a probe's own Host, over plain HTTP" \
  test "$(status -H 'Host: 169.254.8.1:8080' "$BASE/health")" = 200
check "another Host is refused (400)" \
  test "$(status -H 'Host: evil.example' -H 'X-Forwarded-Proto: https' "$BASE/api/user/profile/")" = 400
check "plain HTTP is redirected to HTTPS (301)" \
  test "$(status -H "Host: $API_HOST" "$BASE/api/user/profile/")" = 301
check "the API asks an anonymous caller to sign in (401)" \
  test "$(as_client -o /dev/null -w '%{http_code}' "$BASE/api/user/profile/")" = 401
not_found="$(as_client -w '\n%{http_code}' "$BASE/no-such-page/")"
check "an unknown page is a plain 404" test "${not_found##*$'\n'}" = 404
no_debug_page() { ! grep -qiE 'traceback|DEBUG = True|URLconf' <<<"$1"; }
check "with no debug page (DEBUG is off)" no_debug_page "$not_found"
hsts="$(headers -H "Host: $API_HOST" -H 'X-Forwarded-Proto: https' "$BASE/api/user/profile/")"
check "HTTPS responses carry HSTS" grep -qi '^strict-transport-security: max-age=31536000' <<<"$hsts"
preflight() { # preflight <origin>: the Access-Control-Allow-Origin it gets
  headers -X OPTIONS -H "Host: $API_HOST" -H 'X-Forwarded-Proto: https' \
    -H "Origin: $1" -H 'Access-Control-Request-Method: GET' "$BASE/api/user/profile/" |
    sed -n 's/^access-control-allow-origin: //Ip'
}
check "CORS allows the web app's origin" test "$(preflight "$APP_ORIGIN")" = "$APP_ORIGIN"
check "CORS allows no other origin" test -z "$(preflight https://evil.example)"
check "static files are served (WhiteNoise)" \
  test "$(as_client -o /dev/null -w '%{http_code}' "$BASE/static/admin/css/base.css")" = 200

echo "== The container"
check "it runs as a non-root user" \
  test "$(docker exec "$NAME" id -u)" != 0
check "it carries no compiler, pip or Poetry" \
  docker exec "$NAME" sh -c '! command -v gcc && ! command -v pip && ! command -v poetry'
check "it carries none of the dev extras" \
  docker exec "$NAME" python -c 'import importlib.util as u, sys; sys.exit(any(u.find_spec(m) for m in ("coverage", "debugpy", "jsonschema")))'

stop_started=$(date +%s)
docker stop --timeout 10 "$NAME" >/dev/null
stop_took=$(( $(date +%s) - stop_started ))
check "it stops on SIGTERM within Cloud Run's 10 s (took ${stop_took} s)" test "$stop_took" -lt 10
check "and exits cleanly" test "$(docker inspect -f '{{.State.ExitCode}}' "$NAME")" = 0
cleanup

echo "== Refusing to start misconfigured"
run_image
exited=""
for _ in $(seq 1 60); do
  if [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" != true ]; then exited=1; break; fi
  sleep 0.5
done
check "without DJANGO_SECRET_KEY it exits instead of serving" test -n "$exited"
check "with a non-zero status" test "$(docker inspect -f '{{.State.ExitCode}}' "$NAME")" != 0
check "and says why" grep -q DJANGO_SECRET_KEY <<<"$(docker logs "$NAME" 2>&1)"
cleanup

echo "== Image scan (Trivy)"
mkdir -p "$ROOT/build/trivy-cache"
check "no fixable HIGH or CRITICAL CVE, and no secret in any layer" \
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$ROOT/build/trivy-cache:/root/.cache" \
    "$TRIVY_IMAGE" image --quiet --scanners vuln,secret --table-mode detailed \
    --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$IMAGE"

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures check(s) failed." >&2
  exit 1
fi
echo "All production image checks passed."
