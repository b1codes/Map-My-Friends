#!/usr/bin/env bash
# Runs the E2E journeys (frontend/integration_test) against a fresh full stack.
#
#   scripts/e2e.sh                                      # every journey
#   scripts/e2e.sh integration_test/journeys/auth_test.dart   # one journey file
#
# Steps:
#   1. Recreate the E2E stack (docker-compose.e2e.yml): API, Firestore emulator
#      and third-party stubs. Recreating gives every run empty data and fresh
#      throttle counters.
#   2. Find or fetch a chromedriver that matches the installed Chrome.
#   3. Build the app with the E2E dart-defines and drive it in headless Chrome.
#
# Environment (all optional):
#   CHROMEDRIVER      chromedriver binary to use (CI passes setup-chrome's).
#   CHROME_EXECUTABLE Chrome binary, if not in the default location.
#   E2E_PROJECT       compose project name     (default map-my-friends-e2e)
#   E2E_API_PORT      host port for the API    (default 8100)
#   E2E_STUBS_PORT    host port for the stubs  (default 8190)
#   E2E_DRIVER_PORT   chromedriver port        (default 4444)
#   E2E_HEADED=1      show the browser instead of running headless
#   E2E_KEEP_STACK=1  leave the stack running afterwards (for debugging)
#   E2E_WINDOW        browser window size      (default 1280,800)
#
# Distinct ports and project names let several runs share one machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND="$ROOT/frontend"
TARGET="${1:-integration_test/all_test.dart}"

export E2E_API_PORT="${E2E_API_PORT:-8100}"
export E2E_STUBS_PORT="${E2E_STUBS_PORT:-8190}"
PROJECT="${E2E_PROJECT:-map-my-friends-e2e}"
DRIVER_PORT="${E2E_DRIVER_PORT:-4444}"
WINDOW="${E2E_WINDOW:-1280,800}"
API_URL="http://localhost:${E2E_API_PORT}/api/"
STUBS_URL="http://localhost:${E2E_STUBS_PORT}"

compose() { docker compose -p "$PROJECT" -f "$ROOT/docker-compose.e2e.yml" "$@"; }

if command -v fvm >/dev/null 2>&1; then FLUTTER=(fvm flutter); else FLUTTER=(flutter); fi

DRIVER_PID=""
cleanup() {
  local status=$?
  [[ -n "$DRIVER_PID" ]] && kill "$DRIVER_PID" 2>/dev/null || true
  if [[ $status -ne 0 ]]; then
    echo "--- E2E failed; last API log lines ---" >&2
    compose logs --tail=80 api >&2 || true
  fi
  if [[ "${E2E_KEEP_STACK:-}" != "1" ]]; then
    compose down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  exit $status
}
trap cleanup EXIT

# --- 1. Stack -------------------------------------------------------------
echo "==> Starting a fresh E2E stack ($PROJECT: API :$E2E_API_PORT, stubs :$E2E_STUBS_PORT)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --build --quiet-pull

wait_for() { # url, name
  for _ in $(seq 1 90); do
    # Any HTTP status means the server is answering (the API says 401).
    if [[ "$(curl -s -o /dev/null -w '%{http_code}' "$1" || true)" != "000" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "$2 did not come up at $1" >&2
  return 1
}
wait_for "${API_URL}user/profile/" "The API"
wait_for "${STUBS_URL}/_stub/health" "The stub server"

# The API answers before the emulator is ready; a list call touches Firestore.
for _ in $(seq 1 60); do
  if [[ "$(curl -s -o /dev/null -w '%{http_code}' "${API_URL}people/")" == "200" ]]; then
    break
  fi
  sleep 2
done

# --- 2. chromedriver ------------------------------------------------------
chrome_version() {
  local chrome="${CHROME_EXECUTABLE:-}"
  if [[ -z "$chrome" ]]; then
    for candidate in \
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
      google-chrome google-chrome-stable chromium chromium-browser; do
      if [[ -x "$candidate" ]] || command -v "$candidate" >/dev/null 2>&1; then
        chrome="$candidate"
        break
      fi
    done
  fi
  [[ -n "$chrome" ]] || { echo "Chrome not found; set CHROME_EXECUTABLE." >&2; return 1; }
  "$chrome" --version | grep -oE '[0-9]+(\.[0-9]+){3}'
}

if [[ -z "${CHROMEDRIVER:-}" ]]; then
  VERSION="$(chrome_version)"
  CACHE="$FRONTEND/build/e2e/chromedriver"
  CHROMEDRIVER="$(find "$CACHE" -path "*-$VERSION/*" -name chromedriver -type f 2>/dev/null | head -1 || true)"
  if [[ -z "$CHROMEDRIVER" ]]; then
    echo "==> Fetching chromedriver $VERSION to match Chrome"
    mkdir -p "$FRONTEND/build/e2e"
    (cd "$FRONTEND/build/e2e" && npx -y @puppeteer/browsers install "chromedriver@$VERSION" >/dev/null)
    CHROMEDRIVER="$(find "$CACHE" -path "*-$VERSION/*" -name chromedriver -type f | head -1)"
  fi
fi

echo "==> chromedriver: $CHROMEDRIVER (port $DRIVER_PORT)"
"$CHROMEDRIVER" --port="$DRIVER_PORT" >"$FRONTEND/build/e2e-chromedriver.log" 2>&1 &
DRIVER_PID=$!
sleep 1

# --- 3. Journeys ----------------------------------------------------------
HEADLESS=(--headless)
[[ "${E2E_HEADED:-}" == "1" ]] && HEADLESS=(--no-headless)

echo "==> Driving $TARGET"
mkdir -p "$FRONTEND/build/e2e/screenshots"
cd "$FRONTEND"
"${FLUTTER[@]}" drive \
  --driver=test_driver/integration_test.dart \
  --target="$TARGET" \
  -d web-server \
  --browser-name=chrome \
  "${HEADLESS[@]}" \
  --browser-dimension="$WINDOW" \
  --driver-port="$DRIVER_PORT" \
  --dart-define=API_BASE_URL="$API_URL" \
  --dart-define=E2E_STUBS_URL="$STUBS_URL" \
  --dart-define=OSRM_BASE_URL="$STUBS_URL/route/v1/driving" \
  --dart-define=TILE_URL_TEMPLATE="$STUBS_URL/tiles/{z}/{x}/{y}.png" \
  --dart-define=DEV_LOGIN=false
