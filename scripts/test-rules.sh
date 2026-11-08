#!/usr/bin/env bash
# Checks firestore.rules against the Firestore emulator: `make test-rules`,
# and CI's Firestore Rules job. The checks are in
# docker/firebase-emulator/rules-test/rules.test.js.
#
# Runs in the dev stack's emulator image (docker/firebase-emulator), so the
# emulator is the same version the API's tests use, with the rules test's own
# firebase.json (no single-project mode: the tests use one project per set of
# rules) and the repository's firestore.rules mounted read-only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE=map-my-friends-firebase-emulator:rules-test
TEST_DIR="$ROOT/docker/firebase-emulator/rules-test"

docker build --quiet -t "$IMAGE" "$ROOT/docker/firebase-emulator" >/dev/null

# node_modules lives in a volume, not the host checkout.
docker run --rm \
  -v "$TEST_DIR:/rules-test" \
  -v /rules-test/node_modules \
  -v "$ROOT/firestore.rules:/rules/firestore.rules:ro" \
  -e FIRESTORE_RULES=/rules/firestore.rules \
  -w /rules-test \
  "$IMAGE" \
  sh -c 'npm ci --no-audit --no-fund --loglevel=error &&
         firebase emulators:exec --only firestore --project demo-rules "npm test"'
