#!/usr/bin/env bash
# Checks every dependency lockfile against the OSV vulnerability database.
#
#   scripts/scan-deps.sh
#
# The lockfiles come from the manifests git tracks: each pyproject.toml's
# poetry.lock, each pubspec.yaml's pubspec.lock and each package.json's
# package-lock.json. A new package is scanned
# without editing this script, and one whose lockfile is missing fails, so
# nothing is skipped quietly.
#
# Fails on any known vulnerability not ignored in .osv-scanner.toml. Each
# ignore there has a reason and an expiry date. OSV_FORMAT=json gives the
# full machine-readable report.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# OSV-Scanner v2.7.0. The digest is the multi-arch index, so the same pin
# runs on x64 CI and Apple Silicon.
IMAGE="ghcr.io/google/osv-scanner:v2.7.0@sha256:4f3b7e2c64b9d38a5febc5a7e4a3dfef1d1362f726dea7a2ef4762b46469fcd0"

lockfiles=()
missing=()
while IFS= read -r manifest; do
  dir="$(dirname "$manifest")"
  case "$(basename "$manifest")" in
    pyproject.toml) lock="$dir/poetry.lock" ;;
    pubspec.yaml) lock="$dir/pubspec.lock" ;;
    package.json) lock="$dir/package-lock.json" ;;
  esac
  if [[ -f "$lock" ]]; then
    lockfiles+=(-L "$lock")
  else
    missing+=("$lock")
  fi
done < <(git ls-files '*pyproject.toml' '*pubspec.yaml' '*package.json')

if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'Missing lockfile: %s\n' "${missing[@]}" >&2
  echo "Run poetry lock, flutter pub get or npm install next to its manifest first." >&2
  exit 1
fi

docker run --rm -v "$ROOT:/src:ro" -w /src "$IMAGE" \
  scan source --config=/src/.osv-scanner.toml --format="${OSV_FORMAT:-table}" "${lockfiles[@]}"
