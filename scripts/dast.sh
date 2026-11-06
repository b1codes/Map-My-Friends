#!/usr/bin/env bash
# Runs the OWASP ZAP API scan against a throwaway, production-like stack.
#
#   scripts/dast.sh
#
# Steps:
#   1. Start a fresh stack: docker-compose.e2e.yml (API, Firestore emulator,
#      third-party stubs) with docker-compose.dast.yml on top, which runs the
#      API with DEBUG off under gunicorn. See that file for why.
#   2. Check the scan still covers every route the API serves
#      (scripts/list_api_routes.py, scripts/dast_openapi.py --check-routes).
#   3. Register a user, sign in for an access token, and create a person,
#      a contact log and a trip for ZAP to attack (scripts/dast_seed.py).
#   4. Build the OpenAPI document from the contracts, with those ids
#      (scripts/dast_openapi.py).
#   5. Run zap-api-scan.py on the stack's network, sending the token on every
#      request: it imports the document, spiders it, passive scans, then runs
#      the active scan rules.
#   6. Decide pass or fail: medium and high alerts fail unless triaged in
#      .zap/rules.tsv (scripts/zap_gate.py), and so does any 5xx the API
#      answered during the scan.
#
# Reports land in build/dast/: zap-report.html, .json and .md, plus the
# OpenAPI document, the API's log (access log and tracebacks) and the
# stack's logs.
#
# Environment (all optional):
#   DAST_PROJECT      compose project name      (default map-my-friends-dast)
#   DAST_API_PORT     host port for the API     (default 8200)
#   DAST_KEEP_STACK=1 leave the stack running afterwards (for debugging)
#   DAST_ZAP_OPTIONS  extra zap-api-scan.py options, e.g. "-S" for a passive-only run
#
# A separate project name and port from the dev stack (make up) and the E2E
# stack (make e2e), so all three can run at once.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/dast"
PROJECT="${DAST_PROJECT:-map-my-friends-dast}"
export DAST_API_PORT="${DAST_API_PORT:-8200}"
API_URL="http://localhost:${DAST_API_PORT}/api/"

# ZAP 2.17.0 (the `stable` tag when pinned). The digest is the multi-arch
# index, so the same pin runs on x64 CI and Apple Silicon.
ZAP_IMAGE="ghcr.io/zaproxy/zaproxy:2.17.0@sha256:9624669db72f54d86c4b46a7064518bd9bf79d8c61a4c31befa9923489f328af"

# Time limits, so a slow or stuck run ends with a report instead of hanging:
# the whole active scan stops after 20 minutes and any one rule after 4
# (a rule that hits its limit is listed as skipped in the report), and ZAP
# gets 10 minutes to start and finish passive scanning. An uncapped run took
# over 16 minutes locally and was still going.
ZAP_PASSIVE_MINUTES=10
ZAP_LIMITS="-config scanner.maxScanDurationInMins=20 -config scanner.maxRuleDurationInMins=4"

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
  if [[ "${DAST_KEEP_STACK:-}" != "1" ]]; then
    compose down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT

rm -rf "$OUT"
mkdir -p "$OUT"
# ZAP runs as its own user (uid 1000) and writes its reports here.
chmod 777 "$OUT"

# --- 1. Stack -------------------------------------------------------------
started=$(date +%s)
echo "==> Starting a fresh DAST stack ($PROJECT: API :$DAST_API_PORT)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --build --quiet-pull

ready=""
for _ in $(seq 1 90); do
  # Any HTTP status means gunicorn is answering (the profile says 401).
  if [[ "$(curl -s -o /dev/null -w '%{http_code}' "${API_URL}user/profile/" || true)" != "000" ]]; then
    ready=1
    break
  fi
  sleep 2
done
[[ -n "$ready" ]] || { echo "The API did not come up at $API_URL" >&2; exit 1; }

# The API answers before the emulator is ready; the public people list
# touches Firestore.
for _ in $(seq 1 60); do
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "${API_URL}people/")" == "200" ]] && break
  sleep 2
done

# --- 2. Route coverage ----------------------------------------------------
echo "==> Checking the scan covers every route"
compose exec -T api python - <"$ROOT/scripts/list_api_routes.py" >"$OUT/routes.json"
python3 "$ROOT/scripts/dast_openapi.py" --check-routes "$OUT/routes.json"

# --- 3. User and data -----------------------------------------------------
echo "==> Registering the scan's user and creating its data"
seed="$(python3 "$ROOT/scripts/dast_seed.py" "$API_URL")"
TOKEN="$(head -n 1 <<<"$seed")"
id_args=()
while read -r pair; do
  [[ -n "$pair" ]] && id_args+=(--id "$pair")
done < <(tail -n +2 <<<"$seed")

# --- 4. API definition ----------------------------------------------------
python3 "$ROOT/scripts/dast_openapi.py" --out "$OUT/openapi.json" --server http://api:8000 ${id_args[@]+"${id_args[@]}"}
cp "$ROOT/.zap/rules.tsv" "$OUT/rules.tsv"
stack_ready=$(date +%s)

# --- 5. Scan --------------------------------------------------------------
echo "==> Scanning with ZAP (stack ready in $((stack_ready - started))s)"
# -I: warnings alone don't fail zap-api-scan.py; scripts/zap_gate.py decides.
# Its exit codes: 0 pass, 1 a FAIL rule fired, 2 warnings, 3 ZAP itself failed.
set +e
# shellcheck disable=SC2086 # DAST_ZAP_OPTIONS is a list of options
docker run --rm \
  --network "${PROJECT}_default" \
  -v "$OUT:/zap/wrk:rw" \
  -e ZAP_AUTH_HEADER=Authorization \
  -e ZAP_AUTH_HEADER_VALUE="Bearer $TOKEN" \
  "$ZAP_IMAGE" \
  zap-api-scan.py -t openapi.json -f openapi -c rules.tsv -I \
  -r zap-report.html -J zap-report.json -w zap-report.md \
  -T "$ZAP_PASSIVE_MINUTES" -z "$ZAP_LIMITS" \
  ${DAST_ZAP_OPTIONS:-}
zap_status=$?
set -e
finished=$(date +%s)
echo "==> ZAP finished in $((finished - stack_ready))s (whole run $((finished - started))s), exit $zap_status"
if [[ $zap_status -ge 3 || ! -s "$OUT/zap-report.json" ]]; then
  echo "ZAP did not complete the scan." >&2
  exit 1
fi

# What the API answered, by status. Many 429s would mean the throttles
# blocked the scan.
compose logs --no-color api >"$OUT/api.log" 2>&1 || true
echo "==> API responses during the run, by status:"
grep -oE '" [1-5][0-9]{2} ' "$OUT/api.log" | sort | uniq -c | sort -rn || true

# --- 6. Gate --------------------------------------------------------------
# A 5xx is an unhandled exception: input the API should have rejected with a
# 4xx. ZAP only rates it Low, but it fails the scan here. The tracebacks are
# in build/dast/api.log (docker/dast/dast_settings.py logs them).
result=0
server_errors="$(grep -E '" 5[0-9]{2} ' "$OUT/api.log" | grep -oE '"(GET|POST|PUT|PATCH|DELETE) [^ ?]+' |
  sed -E 's#/[A-Za-z0-9]{20}/#/{id}/#g' | sort | uniq -c | sort -rn || true)"
if [[ -n "$server_errors" ]]; then
  echo "FAIL: the API answered 5xx (by endpoint; tracebacks in build/dast/api.log):" >&2
  echo "$server_errors" >&2
  result=1
fi
python3 "$ROOT/scripts/zap_gate.py" "$OUT/zap-report.json" "$ROOT/.zap/rules.tsv" || result=1
exit "$result"
