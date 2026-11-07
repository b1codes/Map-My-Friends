#!/usr/bin/env bash
# Runs the k6 load test against a throwaway stack shaped like one production
# Cloud Run instance.
#
#   scripts/load.sh
#
# Steps:
#   1. Start a fresh stack: docker-compose.e2e.yml (API, Firestore emulator,
#      third-party stubs) with docker-compose.perf.yml on top, which runs the
#      API as production would, on one vCPU and 512 MiB, and puts Toxiproxy
#      between it and the emulator. See that file for why.
#   2. Give every Firestore round trip a same-region latency (Toxiproxy).
#   3. Cold start: restart the API and time how long it takes to answer, and
#      how long its first hub lookups take (they load the airport and station
#      data). Cloud Run scales to zero, so a user can be the one who waits.
#   4. Run perf/load.js in k6 on the stack's network: it seeds accounts
#      through the API, then runs the scenarios for PERF_DURATION and checks
#      their thresholds.
#   5. Decide pass or fail: k6's thresholds, any 5xx in the API's log, and
#      the cold-start and memory budgets below.
#
# Results land in build/perf/: summary.md (also printed, and written to the
# job page on CI), k6-summary.json (every k6 metric), api.log and stack.log.
#
# Environment (all optional):
#   PERF_PROJECT              compose project name      (default map-my-friends-perf)
#   PERF_API_PORT             host port for the API     (default 8300)
#   PERF_DURATION             how long the scenarios run (default 3m)
#   PERF_RATE_SCALE           multiplies every scenario's rate (default 1)
#   PERF_USERS                accounts seeded            (default 20)
#   PERF_FIRESTORE_LATENCY_MS added each way per Firestore round trip (default 3)
#   PERF_KEEP_STACK=1         leave the stack running afterwards
#
# A separate project name and port from the dev (make up), E2E (make e2e) and
# DAST (make dast) stacks, so they can all run at once.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/perf"
PROJECT="${PERF_PROJECT:-map-my-friends-perf}"
export PERF_API_PORT="${PERF_API_PORT:-8300}"
API_URL="http://localhost:${PERF_API_PORT}/api/"
LATENCY_MS="${PERF_FIRESTORE_LATENCY_MS:-3}"

# k6 2.3.0. The digest is the multi-arch index, so the same pin runs on x64
# CI and Apple Silicon.
K6_IMAGE="grafana/k6:2.3.0@sha256:2dd4756ec6e14e62778916e1eb850108e4b499304c02df56760fa0bdb0fba0b8"

# Budgets outside k6's own thresholds (perf/load.js holds those).
BOOT_BUDGET_S=20            # restart to the first answer
FIRST_LOOKUP_BUDGET_MS=1500 # the first nearest-airports and nearest-stations
MEMORY_BUDGET_MIB=400       # peak, of the 512 MiB the instance has

# Production refuses the default SECRET_KEY, so the stack gets a random one.
PERF_SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')"
export PERF_SECRET_KEY

compose() {
  docker compose -p "$PROJECT" -f "$ROOT/docker-compose.e2e.yml" -f "$ROOT/docker-compose.perf.yml" "$@"
}

# shellcheck disable=SC2329 # run by the EXIT trap below
cleanup() {
  local status=$?
  compose logs --no-color api firestore stubs toxiproxy >"$OUT/stack.log" 2>&1 || true
  if [[ "${PERF_KEEP_STACK:-}" != "1" ]]; then
    compose down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT

rm -rf "$OUT"
mkdir -p "$OUT"
# k6 runs as its own user (uid 12345) and writes k6-summary.* here. Files
# it creates aren't writable by this script, so summary.md is written
# fresh below, from k6's part and this script's.
chmod 777 "$OUT"

now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

# Seconds until the public people list (which touches Firestore) answers 200.
wait_for_api() {
  local limit=$1 start
  start=$(now_ms)
  for _ in $(seq 1 $((limit * 10))); do
    if [[ "$(curl -s -o /dev/null -w '%{http_code}' "${API_URL}people/" || true)" == "200" ]]; then
      echo $(( $(now_ms) - start ))
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# --- 1. Stack -------------------------------------------------------------
echo "==> Starting a fresh load-test stack ($PROJECT: API :$PERF_API_PORT)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --build --quiet-pull
wait_for_api 180 >/dev/null || { echo "The API did not come up at $API_URL" >&2; exit 1; }

# --- 2. Firestore latency -------------------------------------------------
echo "==> Adding ${LATENCY_MS} ms each way to every Firestore round trip"
for direction in upstream downstream; do
  compose exec -T toxiproxy /toxiproxy-cli toxic add \
    --type latency --toxicName "latency-$direction" --"$direction" \
    --attribute "latency=$LATENCY_MS" --attribute jitter=1 firestore >/dev/null
done

# --- 3. Cold start --------------------------------------------------------
echo "==> Timing a cold start"
username="cold-start-$(date +%s)"
# Random, because the API refuses a password that resembles the username.
password="$(python3 -c 'import secrets; print("Pw!" + secrets.token_hex(12) + "9Z")')"
curl -sf -o /dev/null -H 'Content-Type: application/json' \
  -d "{\"username\":\"$username\",\"email\":\"$username@example.com\",\"password\":\"$password\",\"password_confirm\":\"$password\"}" \
  "${API_URL}user/auth/register/"
token="$(curl -sf -H 'Content-Type: application/json' \
  -d "{\"username\":\"$username\",\"password\":\"$password\"}" "${API_URL}user/auth/token/" |
  python3 -c 'import json, sys; print(json.load(sys.stdin)["access"])')"

compose restart api >/dev/null
boot_ms="$(wait_for_api 120)" || { echo "The API did not come back after a restart" >&2; exit 1; }
first_lookup() {
  curl -s -o /dev/null -w '%{time_total}' -H "Authorization: Bearer $token" \
    "${API_URL}$1/nearest/?lat=51.5&lon=-0.12" | python3 -c 'import sys; print(round(float(sys.stdin.read()) * 1000))'
}
airports_ms="$(first_lookup airports)"
stations_ms="$(first_lookup stations)"
echo "    answering ${boot_ms} ms after the restart; first airport lookup ${airports_ms} ms, first station lookup ${stations_ms} ms"

# --- 4. Load --------------------------------------------------------------
echo "==> Running perf/load.js for ${PERF_DURATION:-3m}"
set +e
docker run --rm \
  --network "${PROJECT}_default" \
  -v "$ROOT/perf:/perf:ro" \
  -v "$OUT:/out:rw" \
  -e PERF_BASE_URL=http://api:8000/api/ \
  -e PERF_OUT=/out \
  -e PERF_DURATION="${PERF_DURATION:-3m}" \
  -e PERF_RATE_SCALE="${PERF_RATE_SCALE:-1}" \
  -e PERF_USERS="${PERF_USERS:-20}" \
  "$K6_IMAGE" run --quiet /perf/load.js
k6_status=$?
set -e

# The cgroup's peak memory since the restart, so the cold start and the load
# both count.
peak_bytes="$(compose exec -T api cat /sys/fs/cgroup/memory.peak 2>/dev/null || echo 0)"
peak_mib=$(( ${peak_bytes//[^0-9]/} / 1024 / 1024 ))

compose logs --no-color api >"$OUT/api.log" 2>&1 || true
echo "==> API responses during the run, by status:"
grep -oE '" [1-5][0-9]{2} ' "$OUT/api.log" | sort | uniq -c | sort -rn || true

# --- 5. Gate --------------------------------------------------------------
result=0
failures=()
fail() {
  echo "FAIL: $*" >&2
  failures+=("- ❌ $*")
  result=1
}
measures="$OUT/measures.md"
{
  echo "### Cold start and memory"
  echo
  echo "| Measure | Value | Budget |"
  echo "|---|---|---|"
  echo "| Restart to first answer | ${boot_ms} ms | ${BOOT_BUDGET_S} s |"
  echo "| First airport lookup | ${airports_ms} ms | ${FIRST_LOOKUP_BUDGET_MS} ms |"
  echo "| First station lookup | ${stations_ms} ms | ${FIRST_LOOKUP_BUDGET_MS} ms |"
  echo "| Peak memory | ${peak_mib} MiB | ${MEMORY_BUDGET_MIB} MiB of 512 |"
  echo "| Firestore latency added | ${LATENCY_MS} ms each way | |"
  echo
} >"$measures"

[[ $k6_status -eq 0 ]] || fail "k6 thresholds failed (exit $k6_status); see the table above"
(( boot_ms <= BOOT_BUDGET_S * 1000 )) || fail "the API took ${boot_ms} ms to answer after a restart"
(( airports_ms <= FIRST_LOOKUP_BUDGET_MS )) || fail "the first airport lookup took ${airports_ms} ms"
(( stations_ms <= FIRST_LOOKUP_BUDGET_MS )) || fail "the first station lookup took ${stations_ms} ms"
(( peak_mib <= MEMORY_BUDGET_MIB )) || fail "the API peaked at ${peak_mib} MiB"

# A 5xx is an unhandled exception, or a worker that died under load. The
# tracebacks are in build/perf/api.log.
server_errors="$(grep -E '" 5[0-9]{2} ' "$OUT/api.log" | grep -oE '"(GET|POST|PUT|PATCH|DELETE) [^ ?]+' |
  sed -E 's#/[A-Za-z0-9]{20}/#/{id}/#g' | sort | uniq -c | sort -rn || true)"
if [[ -n "$server_errors" ]]; then
  echo "$server_errors" >&2
  fail "the API answered 5xx (by endpoint above; tracebacks in build/perf/api.log)"
fi

{
  cat "$OUT/k6-summary.md" 2>/dev/null || echo "## Load test (k6 wrote no summary)"
  cat "$measures"
  for line in "${failures[@]+"${failures[@]}"}"; do echo "$line"; done
} >"$OUT/summary.md"
cat "$OUT/summary.md"
exit "$result"
